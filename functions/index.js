// Avisos automáticos de pedidos.
// - Pedido nuevo → aviso al dueño (tema "dueno").
// - Cambio de estado → aviso al cliente que hizo el pedido.
// - Repartidor cerca → aviso al cliente (una sola vez por pedido).
// Cupos de pan por día:
// - hacerPedido: el cliente pide por aquí; se revisa el cupo y se aparta en un solo paso.
// - recontarCupo*: cuando un pedido se cancela, se borra o cambia, se recuenta el día.
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');

initializeApp();

// Tope de copias de cada función corriendo a la vez. Si alguien manda miles de
// peticiones de golpe, no se multiplican los servidores (ni el cobro): las de más esperan
// o fallan. Para una panadería, 10 alcanza de sobra (cada copia atiende muchas a la vez).
setGlobalOptions({ maxInstances: 10 });

// App Check en las funciones que llama la app (hacerPedido, cambiarDireccion, moverDia, mandarRecuperacion).
// Fase 1 y 2 (monitoreo): false. Se aceptan todas, pero cada llamada deja en el registro
// si traía el "pase" de la app original o no (busca "appcheck" en los registros).
// Fase 3: true, cuando casi todos tengan la APK nueva. Sin pase válido, se rechaza.
const EXIGIR_APP_CHECK = false;

function anotarPase(funcion, req) {
  logger.info('appcheck', { funcion, pase: req.app ? 'valido' : 'sin-pase' });
}

const STATUS_TEXT = {
  confirmado: 'Tu pedido está confirmado.',
  enCamino: 'Tu pedido va en camino.',
  entregado: 'Tu pedido fue entregado. ¡Buen provecho!',
  cancelado: 'Tu pedido fue cancelado. Escríbenos si tienes dudas.',
};

// Dirección de la versión web (Firebase Hosting).
const PAGINA_WEB = 'https://panaderoso.web.app';

exports.avisoPedidoNuevo = onDocumentCreated('orders/{id}', async (event) => {
  const o = event.data?.data();
  if (!o) return;
  const piezas = (o.items || []).reduce((s, i) => s + (i.qty || 0), 0);
  await getMessaging().send({
    topic: 'dueno',
    notification: {
      title: `Pedido nuevo de ${o.customerName}`,
      body: `${piezas} piezas para el ${o.deliveryDate} a las ${o.slot} · ${o.paymentMethod}`,
    },
    android: { priority: 'high', notification: { sound: 'default' } },
  });
});

exports.avisoCambioDeEstado = onDocumentUpdated('orders/{id}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.status === after.status) return;
  const text = STATUS_TEXT[after.status];
  if (!text) return;

  // Al picarle "Empezar a repartir" los pedidos pasan a "en camino", pero a
  // esos clientes ya les llega el aviso de "¡Ya salimos a repartir!"
  // (avisoSalidaReparto); así no les llegan dos avisos.
  if (after.status === 'enCamino') {
    const t = (await getFirestore().collection('tracking').doc('current').get()).data();
    if (t && t.active && t.date === after.deliveryDate) return;
  }

  await avisarCliente(after.customerId, 'Panaderoso', text);
});

// Cuando el dueño le pica "Empezar a repartir": avisa a TODOS los clientes con
// pedido pendiente ese día (confirmado o no), en Android y en la versión web.
// Solo una vez por día, aunque pause y vuelva a empezar.
exports.avisoSalidaReparto = onDocumentWritten('tracking/current', async (event) => {
  const before = event.data?.before.data();
  const t = event.data?.after.data();
  if (!t || !t.active || !t.date || (before && before.active)) return;

  const db = getFirestore();
  const dia = db.collection('deliveryDays').doc(t.date);
  let punto = null;
  const yaAvisado = await db.runTransaction(async (tx) => {
    const d = await tx.get(dia);
    punto = puntoDelDia(d);
    if (d.exists && d.get('salidaAvisada') === true) return true;
    tx.set(dia, { salidaAvisada: true }, { merge: true });
    return false;
  });
  if (yaAvisado) return;

  const pedidos = await db.collection('orders')
    .where('deliveryDate', '==', t.date)
    .where('status', 'in', PENDIENTES)
    .get();
  const clientes = [...new Set(pedidos.docs.map((d) => d.get('customerId')).filter(Boolean))];
  const cuerpo = punto
    ? `Vamos en camino a ${punto.name} con tu pan. Toca para ver en el mapa por dónde vamos.`
    : 'Tu pan va en camino. Toca para ver en el mapa por dónde va.';
  await Promise.all(clientes.map((uid) => avisarCliente(uid, '¡Ya salimos a repartir! 🥐', cuerpo).catch((e) => logger.warn('aviso salida', uid, e))));
  logger.info('aviso salida', { dia: t.date, clientes: clientes.length });
});

// Cada vez que el repartidor manda su ubicación (más o menos cada 30 m recorridos),
// revisa los pedidos pendientes del día y avisa a quien ya está cerca.
exports.avisoRepartidorCerca = onDocumentUpdated('tracking/current', async (event) => {
  const t = event.data?.after.data();
  if (!t || !t.active || typeof t.lat !== 'number' || typeof t.lng !== 'number' || !t.date) return;
  const radio = t.alertMeters || 1000;

  const db = getFirestore();
  const pedidos = await db.collection('orders')
    .where('deliveryDate', '==', t.date)
    .where('status', 'in', ['recibido', 'confirmado', 'enCamino'])
    .get();

  for (const doc of pedidos.docs) {
    const o = doc.data();
    if (o.puntoEntrega) {
      // Día especial: "ya casi llego" y, al estar en el lugar, "ya llegué".
      if (o.llegadaAvisada || typeof o.lat !== 'number' || typeof o.lng !== 'number') continue;
      const m = distanciaMetros(t.lat, t.lng, o.lat, o.lng);
      if (m <= LLEGADA_METROS) {
        await avisarLlegada(t.date);
      } else if (m <= radio && !o.nearNotified) {
        await doc.ref.update({ nearNotified: true });
        await avisarCliente(o.customerId, `¡Ya casi llegamos a ${o.puntoEntrega}! 🥐`,
          `Estamos muy cerca de ${o.puntoEntrega}. Ve preparándote para recoger tu pan.`);
      }
      continue;
    }
    if (o.nearNotified) continue;
    let { lat, lng } = o;
    if (typeof lat !== 'number' || typeof lng !== 'number') {
      // Pedido de antes del mapa: usar la casa marcada en el perfil.
      const u = await db.collection('users').doc(o.customerId).get();
      lat = u.get('lat');
      lng = u.get('lng');
      if (typeof lat !== 'number' || typeof lng !== 'number') continue;
    }
    const metros = distanciaMetros(t.lat, t.lng, lat, lng);
    if (metros > radio) continue;

    // Marcar primero para no mandar el aviso dos veces.
    await doc.ref.update({ nearNotified: true });
    await avisarCliente(o.customerId, '¡Tu pan está por llegar! 🥐',
      'El repartidor ya está muy cerca de tu casa. Ve preparándote para recibirlo.');
  }
});

// ---------------------------------------------------------------------------
// Días especiales: entrega en un solo lugar (FIME, …)
// ---------------------------------------------------------------------------
// deliveryDays/{fecha}.punto = { name, lat, lng, notes }. Los pedidos de ese día
// llevan la ubicación del lugar, `puntoEntrega` con su nombre, envío 0 y sin pan
// de bienvenida (sí cuentan para la tarjeta de lealtad).

// A cuántos metros del lugar se considera que ya llegó el repartidor.
const LLEGADA_METROS = 150;

function puntoDelDia(dia) {
  const p = dia && dia.exists ? dia.get('punto') : null;
  if (!p || typeof p !== 'object') return null;
  const name = texto(p.name, 80);
  if (!name || typeof p.lat !== 'number' || typeof p.lng !== 'number') return null;
  return { name, lat: p.lat, lng: p.lng, notes: texto(p.notes, 300) };
}

// "Ya llegué a FIME": a cada cliente del día con pedido pendiente, una sola vez.
async function avisarLlegada(date) {
  const db = getFirestore();
  const pedidos = await db.collection('orders')
    .where('deliveryDate', '==', date)
    .where('status', 'in', PENDIENTES)
    .get();
  const avisar = [];
  for (const doc of pedidos.docs) {
    const o = doc.data();
    if (!o.puntoEntrega) continue;
    // Marcar en transacción para no mandar dos veces el mismo aviso.
    const toca = await db.runTransaction(async (tx) => {
      const d = await tx.get(doc.ref);
      if (!d.exists || d.get('llegadaAvisada') === true) return false;
      tx.update(doc.ref, { llegadaAvisada: true, nearNotified: true });
      return true;
    });
    if (toca) avisar.push(o);
  }
  await db.collection('deliveryDays').doc(date).set({ llegue: true }, { merge: true });
  await Promise.all(avisar.map((o) => avisarCliente(o.customerId, `¡Ya llegamos a ${o.puntoEntrega}! 📍`,
    `Tu pan ya está en ${o.puntoEntrega}. Pasa a recogerlo.`).catch((e) => logger.warn('aviso llegada', o.customerId, e))));
  logger.info('aviso llegada', { dia: date, clientes: avisar.length });
}

// El dueño le picó "Ya llegué" en la app.
exports.avisoLlegadaPunto = onDocumentUpdated('deliveryDays/{date}', async (event) => {
  const antes = event.data?.before.data();
  const despues = event.data?.after.data();
  if (!despues || despues.llegue !== true || (antes && antes.llegue === true)) return;
  await avisarLlegada(event.params.date);
});

// Un token de FCM es largo (unas 150 letras, con ":"). Las versiones anteriores de la
// app de Android guardaban por error el "FID" del celular (22 letras), que no sirve
// como token: FCM lo rechaza y el aviso no llegaba. Esos se quitan de la cuenta.
function esTokenFcm(t) {
  return typeof t === 'string' && t.length > 64;
}

// Errores de FCM que quieren decir "este token ya no sirve, bórralo".
function tokenMuerto(error) {
  if (!error) return false;
  const code = error.code || '';
  return code === 'messaging/registration-token-not-registered'
    || code === 'messaging/invalid-registration-token'
    || (code === 'messaging/invalid-argument' && /token/i.test(error.message || ''));
}

// Manda un aviso a todos los celulares de un cliente. Regresa true si le llegó a
// por lo menos uno. Limpia los tokens que ya no sirven y, si no le queda ninguno,
// marca pushOk = false para que el dueño vea 🔕 (la app lo vuelve a poner en true
// sola en cuanto el cliente la abre con los avisos prendidos).
async function avisarCliente(uid, title, body) {
  const userRef = getFirestore().collection('users').doc(uid);
  const user = await userRef.get();
  if (!user.exists) return false;
  const guardados = user.get('fcmTokens') || [];
  const tokens = [...new Set(guardados.filter(esTokenFcm))];
  const quitar = guardados.filter((t) => !esTokenFcm(t));

  let llego = false;
  if (tokens.length > 0) {
    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      android: { priority: 'high', notification: { sound: 'default' } },
      // Versión web (iPhone): el ícono del oso y, al tocar el aviso, abrir la app.
      webpush: {
        notification: { icon: `${PAGINA_WEB}/icons/Icon-192.png` },
        fcmOptions: { link: `${PAGINA_WEB}/` },
      },
    });
    res.responses.forEach((r, i) => {
      if (r.success) return;
      if (tokenMuerto(r.error)) {
        quitar.push(tokens[i]);
      } else {
        // Otro error (FCM caído, credenciales...): se deja el token y queda en el registro.
        logger.warn('aviso no enviado', { uid, code: r.error?.code, message: r.error?.message });
      }
    });
    llego = res.successCount > 0;
  }

  const cambios = {};
  if (quitar.length) cambios.fcmTokens = FieldValue.arrayRemove(...quitar);
  const vivos = tokens.filter((t) => !quitar.includes(t));
  if (vivos.length === 0 && user.get('pushOk') !== false) cambios.pushOk = false;
  if (Object.keys(cambios).length) {
    await userRef.update(cambios).catch((e) => logger.warn('limpiar tokens', uid, e));
  }
  if (!llego) logger.info('aviso sin llegar', { uid, tokens: tokens.length, vivos: vivos.length });
  return llego;
}

// Distancia en metros, en línea recta (haversine). Igual que lib/logic/geo.dart.
// Costo de envío: igual que ShippingRules.feeForTrip en lib/logic/shipping.dart.
// km de ida (línea recta × roadFactor) × precio por km × parte que paga el cliente
// según piezas, redondeado hacia arriba a múltiplos de roundTo. 0 si está apagado
// o falta el punto de salida o la casa.
function costoEnvio(config, lat, lng, piezas) {
  const r = config.shipping || {};
  const baseLat = config.baseLat;
  const baseLng = config.baseLng;
  if (r.enabled !== true || piezas <= 0) return 0;
  if (typeof baseLat !== 'number' || typeof baseLng !== 'number' || lat === null || lng === null) return 0;
  const porKm = typeof r.pricePerKm === 'number' ? r.pricePerKm : 2.8;
  const factor = typeof r.roadFactor === 'number' ? r.roadFactor : 1.3;
  const redondeo = typeof r.roundTo === 'number' && r.roundTo > 0 ? Math.round(r.roundTo) : 5;
  let rangos = Array.isArray(r.tiers) && r.tiers.length ? r.tiers
    : [{ minPieces: 1, customerShare: 1 }, { minPieces: 2, customerShare: 0.25 }, { minPieces: 6, customerShare: 0 }];
  rangos = [...rangos].sort((a, b) => a.minPieces - b.minPieces);
  let parte = 1;
  for (const t of rangos) if (piezas >= t.minPieces) parte = t.customerShare;
  const km = distanciaMetros(baseLat, baseLng, lat, lng) / 1000 * factor;
  const bruto = km * porKm * parte;
  if (!(bruto > 0)) return 0;
  return Math.min(10000, Math.ceil((bruto - 1e-9) / redondeo) * redondeo);
}

function distanciaMetros(lat1, lng1, lat2, lng2) {
  const rad = (d) => d * Math.PI / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(a));
}

// ---------------------------------------------------------------------------
// Cupos de pan por día
// ---------------------------------------------------------------------------
// deliveryDays/{fecha}.stock = { llave: límite }   ← lo pone el dueño
// dayStock/{fecha}.used      = { llave: apartados } ← solo lo escribe el servidor
// La llave junta los productos de la misma masa. Igual que lib/logic/stock.dart.
function stockKey(productId, product) {
  const g = String((product && product.stockGroup) || '').trim().toLowerCase();
  return g ? `g:${g}` : `p:${productId}`;
}

function stockLabel(productId, product) {
  const g = String((product && product.stockGroup) || '').trim();
  return g || (product && product.name) || 'ese producto';
}

// ---------------------------------------------------------------------------
// Promociones: tarjeta de lealtad y pan de bienvenida
// ---------------------------------------------------------------------------
// Igual que lib/logic/promos.dart. Aquí es donde de verdad se pone el pan gratis.
// - Lealtad: cada `meta` piezas compradas de los panes que suman (`suman`; si no
//   eligió ninguno, chocolatín y croissants), desde que salió la promo y sin contar
//   pedidos cancelados = 1 pan gratis, que va en el pedido que llega a la meta.
// - Bienvenida: 1 pan gratis en el primer pedido de la cuenta, si lleva al menos
//   `minimo` piezas. Uno por cuenta y uno por domicilio.
// Los panes regalados van en `items` con precio 0 y `regalo: 'lealtad' | 'bienvenida'`,
// así cuentan en el cupo del día y en la demanda para hornear.
function reglasPromo(config) {
  const p = config.promos || {};
  const entero = (v, def, min, max) => (typeof v === 'number' && Number.isFinite(v)
    ? Math.min(max, Math.max(min, Math.round(v))) : def);
  return {
    lealtad: p.loyaltyEnabled !== false,
    meta: entero(p.loyaltyGoal, 10, 2, 100),
    bienvenida: p.welcomeEnabled !== false,
    minimo: entero(p.welcomeMinPieces, 2, 1, 50),
    productoId: typeof p.giftProductId === 'string' ? p.giftProductId : '',
    // Panes que suman a la tarjeta. Vacío = chocolatín y croissants (donas no).
    suman: Array.isArray(p.loyaltyProductIds)
      ? p.loyaltyProductIds.filter((x) => typeof x === 'string' && x) : [],
  };
}

// Piezas de un pedido que suman a la tarjeta (los regalados nunca suman).
// Igual que loyaltyPiecesOf en lib/logic/promos.dart.
function piezasLealtad(reglas, items) {
  let n = 0;
  for (const it of items || []) {
    if (it.regalo) continue;
    const ok = reglas.suman.length
      ? reglas.suman.includes(it.productId)
      : /chocolat|croissant|cuernito/.test(sinAcentos(it.name));
    if (ok) n += Number(it.qty) || 0;
  }
  return n;
}

const sinAcentos = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

// El pan que se regala: el que eligió el dueño o, si no, el chocolatín.
async function productoRegalo(db, reglas) {
  let doc = null;
  if (reglas.productoId) {
    const d = await db.collection('products').doc(reglas.productoId).get();
    if (d.exists) doc = d;
  } else {
    const todos = await db.collection('products').get();
    doc = todos.docs.find((d) => sinAcentos(d.get('name')).includes('chocolat')) || null;
  }
  if (!doc || doc.get('available') === false) return null;
  return { id: doc.id, data: doc.data() };
}

// Domicilio "en limpio" para comparar: sin acentos, mayúsculas ni signos.
const direccionLimpia = (s) => sinAcentos(s).replace(/[^a-z0-9]+/g, ' ').trim();

// Metros entre dos casas para considerarlas el mismo domicilio.
const MISMO_DOMICILIO_METROS = 25;

// ¿Otra cuenta ya recibió el pan de bienvenida en este domicilio?
async function domicilioYaRegalado(db, uid, lat, lng, direccion) {
  const limpia = direccionLimpia(direccion);
  const otros = await db.collection('promoClientes').where('bienvenida.activa', '==', true).get();
  return otros.docs.some((d) => {
    if (d.id === uid) return false;
    const b = d.get('bienvenida') || {};
    // Si el cliente cambió la dirección del pedido con regalo, también cuentan las otras.
    const lugares = [b, ...(Array.isArray(b.otras) ? b.otras : [])];
    return lugares.some((l) => {
      if (limpia.length >= 8 && l.direccion === limpia) return true;
      return lat !== null && lng !== null && typeof l.lat === 'number' && typeof l.lng === 'number'
        && distanciaMetros(lat, lng, l.lat, l.lng) < MISMO_DOMICILIO_METROS;
    });
  });
}

const texto = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const numeroONull = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// El cliente hace su pedido. Todo pasa dentro de una transacción: si dos personas
// piden los últimos panes al mismo tiempo, solo una se los lleva.
exports.hacerPedido = onCall({ enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('hacerPedido', req);
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Inicia sesión para hacer tu pedido.');
  const d = req.data || {};

  const date = d.deliveryDate;
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new HttpsError('invalid-argument', 'Falta el día de entrega.');
  }
  if (!['transferencia', 'efectivo'].includes(d.paymentMethod)) {
    throw new HttpsError('invalid-argument', 'Forma de pago no válida.');
  }
  const pedidos = Array.isArray(d.items) ? d.items : [];
  const qtyById = {};
  for (const it of pedidos) {
    const qty = Number(it && it.qty);
    if (!it || typeof it.productId !== 'string' || !it.productId || !Number.isInteger(qty) || qty < 1 || qty > 500) {
      throw new HttpsError('invalid-argument', 'Revisa las cantidades de tu pedido.');
    }
    qtyById[it.productId] = (qtyById[it.productId] || 0) + qty;
  }
  const ids = Object.keys(qtyById);
  if (ids.length === 0 || ids.length > 30) throw new HttpsError('invalid-argument', 'Tu carrito está vacío.');

  let proof = d.paymentProofPath;
  if (typeof proof !== 'string' || !proof.startsWith(`payment-proofs/${uid}/`)) proof = null;

  const db = getFirestore();
  const dayRef = db.collection('deliveryDays').doc(date);
  const stockRef = db.collection('dayStock').doc(date);
  const orderRef = db.collection('orders').doc();
  // El envío lo calcula el servidor (lo que mande el celular no cuenta).
  const config = (await db.collection('config').doc('app').get()).data() || {};
  const lat = numeroONull(d.lat);
  const lng = numeroONull(d.lng);
  const direccion = texto(d.address, 300);

  // Promociones (ver arriba). Lo que se puede revisar antes de la transacción.
  const reglas = reglasPromo(config);
  const regalo = (reglas.lealtad || reglas.bienvenida) ? await productoRegalo(db, reglas) : null;
  const domicilioUsado = reglas.bienvenida && regalo
    ? await domicilioYaRegalado(db, uid, lat, lng, direccion) : false;
  const promoRef = db.collection('promoClientes').doc(uid);
  const regalados = { lealtad: 0, bienvenida: 0 };

  await db.runTransaction(async (tx) => {
    const day = await tx.get(dayRef);
    if (!day.exists || day.get('open') !== true || day.get('closed') === true) {
      throw new HttpsError('failed-precondition', 'Ese día ya no recibe pedidos. Elige otro día.');
    }
    // Se puede pedir hasta que termina el día en México (00:00 UTC + 30 h).
    const [y, m, dd] = date.split('-').map(Number);
    if (Date.now() >= Date.UTC(y, m - 1, dd) + 30 * 3600 * 1000) {
      throw new HttpsError('failed-precondition', 'Ese día ya pasó. Elige otro día.');
    }
    const slots = day.get('slots') || [];
    if (!slots.includes(d.slot)) throw new HttpsError('failed-precondition', 'Ese horario ya no está disponible.');
    // Día especial: se entrega en el lugar, no en la dirección que mande el celular.
    const punto = puntoDelDia(day);

    const prods = await tx.getAll(...ids.map((id) => db.collection('products').doc(id)));
    const stock = await tx.get(stockRef);
    // Leer la ficha del cliente dentro de la transacción hace que dos pedidos suyos
    // al mismo tiempo vayan en fila (y no se lleven dos veces el mismo pan gratis).
    const promo = await tx.get(promoRef);
    const misPedidos = await tx.get(db.collection('orders').where('customerId', '==', uid));

    // Nombre y precio salen del catálogo, no del celular.
    const items = [];
    const need = {};
    const labels = {};
    for (const p of prods) {
      const pd = p.data();
      if (!p.exists || pd.available === false) {
        throw new HttpsError('failed-precondition',
          `${(pd && pd.name) || 'Un producto'} ya no está disponible. Quítalo de tu carrito.`);
      }
      const qty = qtyById[p.id];
      items.push({ productId: p.id, name: pd.name || '', price: Number(pd.price) || 0, qty });
      const key = stockKey(p.id, pd);
      need[key] = (need[key] || 0) + qty;
      labels[key] = stockLabel(p.id, pd);
    }

    const limits = day.get('stock') || {};
    const used = { ...(stock.get('used') || {}) };
    for (const [key, qty] of Object.entries(need)) {
      const limit = limits[key];
      if (typeof limit === 'number') {
        const left = Math.max(0, limit - (used[key] || 0));
        if (qty > left) {
          throw new HttpsError('resource-exhausted', left === 0
            ? `Ya no quedan panes de ${labels[key]} para ese día. Prueba otro día.`
            : `Solo quedan ${left} de ${labels[key]} para ese día. Ajusta tu pedido.`);
        }
      }
      used[key] = (used[key] || 0) + qty;
    }

    // Piezas compradas: las que pagan, cuentan para el envío y para la tarjeta.
    const pagadas = items.reduce((s, i) => s + i.qty, 0);
    const subtotal = items.reduce((s, i) => s + i.price * i.qty, 0);
    const shippingFee = punto ? 0 : costoEnvio(config, lat, lng, pagadas);

    // ----- Pan gratis -----
    if (regalo) {
      const activos = misPedidos.docs.filter((o) => o.get('status') !== 'cancelado');
      const quiere = { bienvenida: 0, lealtad: 0 };
      const yaTuvoBienvenida = promo.exists && promo.get('bienvenida.activa') === true;
      // Los pedidos de días especiales no cuentan como "ya pidió": la bienvenida
      // se queda para su primer pedido a domicilio. Y en día especial no se da.
      const aDomicilio = activos.filter((o) => !o.get('puntoEntrega'));
      if (reglas.bienvenida && !punto && aDomicilio.length === 0 && pagadas >= reglas.minimo
        && !yaTuvoBienvenida && !domicilioUsado) {
        quiere.bienvenida = 1;
      }
      if (reglas.lealtad) {
        // En orden: cada pedido suma sus piezas que cuentan y cada pan de lealtad
        // que se le dio resta una tarjeta llena, sin bajar de 0 (lo que se regaló
        // cuando contaba cualquier pan no se cobra). Igual que LoyaltyCard en Dart.
        const ms = (o) => { const t = o.get('createdAt'); return t && t.toMillis ? t.toMillis() : Infinity; };
        const conTarjeta = activos
          .filter((o) => typeof o.get('lealtadPiezas') === 'number') // los de antes de la promo no
          .sort((a, b) => ms(a) - ms(b));
        let saldo = 0;
        for (const o of conTarjeta) {
          const its = o.get('items') || [];
          let dados = 0;
          for (const it of its) if (it.regalo === 'lealtad') dados += Number(it.qty) || 0;
          saldo = Math.max(0, saldo + piezasLealtad(reglas, its) - dados * reglas.meta);
        }
        quiere.lealtad = Math.min(10, Math.floor((saldo + piezasLealtad(reglas, items)) / reglas.meta));
      }
      // El regalo también usa cupo. Si ya no cabe, no se pone: el de lealtad se
      // queda guardado para el siguiente pedido.
      const key = stockKey(regalo.id, regalo.data);
      const limit = limits[key];
      let cabe = typeof limit === 'number' ? Math.max(0, limit - (used[key] || 0)) : Infinity;
      for (const tipo of ['bienvenida', 'lealtad']) {
        const n = Math.min(quiere[tipo], cabe);
        if (n <= 0) continue;
        items.push({ productId: regalo.id, name: regalo.data.name || '', price: 0, qty: n, regalo: tipo });
        used[key] = (used[key] || 0) + n;
        cabe -= n;
        regalados[tipo] = n;
      }
    }
    const pieces = items.reduce((s, i) => s + i.qty, 0);

    tx.set(promoRef, {
      actualizado: FieldValue.serverTimestamp(),
      ...(regalados.bienvenida ? {
        bienvenida: {
          activa: true,
          orderId: orderRef.id,
          direccion: direccionLimpia(direccion),
          lat,
          lng,
          fecha: FieldValue.serverTimestamp(),
        },
      } : {}),
    }, { merge: true });

    tx.set(stockRef, { used, updatedAt: FieldValue.serverTimestamp() });
    tx.create(orderRef, {
      customerId: uid,
      customerName: texto(d.customerName, 120),
      phone: texto(d.phone, 40),
      address: punto ? `Entrega en ${punto.name}` : direccion,
      addressNotes: punto ? punto.notes : texto(d.addressNotes, 300),
      ...(punto ? { puntoEntrega: punto.name, llegadaAvisada: false } : {}),
      items,
      pieces,
      lealtadPiezas: pagadas,
      subtotal,
      shippingFee,
      total: subtotal + shippingFee,
      deliveryDate: date,
      slot: d.slot,
      slotMinutes: Number(day.get('slotMinutes')) || 60,
      paymentMethod: d.paymentMethod,
      paymentProofPath: proof,
      paymentVerified: false,
      cashCollected: false,
      status: 'recibido',
      notes: texto(d.notes, 500),
      lat: punto ? punto.lat : lat,
      lng: punto ? punto.lng : lng,
      nearNotified: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { id: orderRef.id, regalos: regalados };
});

// Si se cancela el pedido que traía el pan de bienvenida, el cliente lo puede
// volver a usar en su siguiente pedido.
exports.liberarBienvenida = onDocumentUpdated('orders/{id}', async (event) => {
  const antes = event.data.before.data();
  const despues = event.data.after.data();
  if (antes.status === 'cancelado' || despues.status !== 'cancelado') return;
  if (!(antes.items || []).some((it) => it.regalo === 'bienvenida')) return;
  const ref = getFirestore().collection('promoClientes').doc(antes.customerId);
  await getFirestore().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (doc.exists && doc.get('bienvenida.orderId') === event.params.id) {
      tx.update(ref, { 'bienvenida.activa': false });
    }
  });
});

// El cliente cambia a qué dirección se entrega un pedido que todavía no sale
// (de sus direcciones guardadas). Se vuelve a calcular el envío con la nueva.
exports.cambiarDireccion = onCall({ enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('cambiarDireccion', req);
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Inicia sesión para cambiar tu pedido.');
  const d = req.data || {};
  if (typeof d.orderId !== 'string' || !d.orderId || d.orderId.includes('/')) {
    throw new HttpsError('invalid-argument', 'Falta el pedido.');
  }
  const lat = numeroONull(d.lat);
  const lng = numeroONull(d.lng);
  const direccion = texto(d.address, 300);
  if (!direccion || lat === null || lng === null) {
    throw new HttpsError('invalid-argument', 'Marca la dirección en el mapa.');
  }

  const db = getFirestore();
  const orderRef = db.collection('orders').doc(d.orderId);
  const config = (await db.collection('config').doc('app').get()).data() || {};
  const promoRef = db.collection('promoClientes').doc(uid);
  // Se revisa antes de la transacción (es una consulta de muchos documentos).
  const domicilioUsado = await domicilioYaRegalado(db, uid, lat, lng, direccion);
  let aviso = null;

  const shippingFee = await db.runTransaction(async (tx) => {
    const order = await tx.get(orderRef);
    if (!order.exists || order.get('customerId') !== uid) {
      throw new HttpsError('permission-denied', 'No encontramos ese pedido.');
    }
    const o = order.data();
    if (!['recibido', 'confirmado'].includes(o.status)) {
      throw new HttpsError('failed-precondition', 'Ese pedido ya salió o ya no está activo. Escríbenos por WhatsApp.');
    }
    const day = await tx.get(db.collection('deliveryDays').doc(o.deliveryDate));
    if (day.exists && day.get('closed') === true) {
      throw new HttpsError('failed-precondition', 'Ya salimos a repartir ese día. Escríbenos por WhatsApp.');
    }
    if (o.puntoEntrega || puntoDelDia(day)) {
      throw new HttpsError('failed-precondition',
        `Ese día la entrega es en ${o.puntoEntrega || 'un solo lugar'}, no a domicilio.`);
    }
    const [y, m, dd] = String(o.deliveryDate).split('-').map(Number);
    if (Date.now() >= Date.UTC(y, m - 1, dd) + 30 * 3600 * 1000) {
      throw new HttpsError('failed-precondition', 'Ese día ya pasó.');
    }

    // El pan de bienvenida es uno por domicilio: no se puede mover a uno que ya lo tuvo.
    const items = Array.isArray(o.items) ? o.items : [];
    const traeBienvenida = items.some((it) => it.regalo === 'bienvenida');
    if (traeBienvenida && domicilioUsado) {
      throw new HttpsError('failed-precondition',
        'Este pedido trae pan de bienvenida y esa dirección ya lo recibió. Elige otra o escríbenos.');
    }
    const promo = traeBienvenida ? await tx.get(promoRef) : null;

    const pagadas = typeof o.lealtadPiezas === 'number' ? o.lealtadPiezas
      : items.filter((it) => !it.regalo).reduce((s, it) => s + (Number(it.qty) || 0), 0);
    const subtotal = items.reduce((s, it) => s + (Number(it.price) || 0) * (Number(it.qty) || 0), 0);
    const fee = costoEnvio(config, lat, lng, pagadas);

    if (promo && promo.exists && promo.get('bienvenida.orderId') === orderRef.id) {
      // La nueva dirección también queda como "ya recibió bienvenida".
      tx.update(promoRef, {
        'bienvenida.otras': FieldValue.arrayUnion({ direccion: direccionLimpia(direccion), lat, lng }),
      });
    }
    tx.update(orderRef, {
      address: direccion,
      addressNotes: texto(d.addressNotes, 300),
      lat,
      lng,
      shippingFee: fee,
      total: subtotal + fee,
      nearNotified: false,
      addressChangedAt: FieldValue.serverTimestamp(),
    });
    const antes = Number(o.shippingFee) || 0;
    aviso = {
      title: `📍 ${o.customerName || 'Un cliente'} cambió la dirección`,
      body: `Pedido del ${o.deliveryDate} a las ${o.slot}: ${direccion}`
        + (fee !== antes ? ` · envío $${antes} → $${fee}` : ''),
    };
    return fee;
  });

  if (aviso) {
    await getMessaging().send({
      topic: 'dueno',
      notification: aviso,
      android: { priority: 'high', notification: { sound: 'default' } },
    }).catch((e) => logger.warn('aviso cambio de direccion', e));
  }
  return { shippingFee };
});

// Vuelve a contar los panes apartados de un día a partir de sus pedidos
// (los cancelados no cuentan). Se puede correr las veces que sea: siempre da lo mismo.
async function recontarDia(date) {
  if (!date) return;
  const db = getFirestore();
  const prods = await db.collection('products').get();
  const byId = Object.fromEntries(prods.docs.map((p) => [p.id, p.data()]));
  const stockRef = db.collection('dayStock').doc(date);
  await db.runTransaction(async (tx) => {
    await tx.get(stockRef); // para que un pedido al mismo tiempo no se pierda
    const orders = await tx.get(db.collection('orders').where('deliveryDate', '==', date));
    const used = {};
    for (const o of orders.docs) {
      if (o.get('status') === 'cancelado') continue;
      for (const it of o.get('items') || []) {
        const key = stockKey(it.productId, byId[it.productId]);
        used[key] = (used[key] || 0) + (Number(it.qty) || 0);
      }
    }
    tx.set(stockRef, { used, updatedAt: FieldValue.serverTimestamp() });
  });
}

// Lo que importa para el cupo de un pedido: día, si está cancelado y qué lleva.
const huellaCupo = (o) => (o ? JSON.stringify([o.deliveryDate, o.status === 'cancelado', o.items]) : '');

exports.recontarCupoPorPedido = onDocumentWritten('orders/{id}', async (event) => {
  const before = event.data && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after.exists ? event.data.after.data() : null;
  if (huellaCupo(before) === huellaCupo(after)) return;
  const dates = new Set([before && before.deliveryDate, after && after.deliveryDate].filter(Boolean));
  for (const date of dates) await recontarDia(date);
});

// Al poner o cambiar el cupo de un día, se cuentan los pedidos que ya tenía.
exports.recontarCupoPorDia = onDocumentWritten('deliveryDays/{date}', async (event) => {
  if (!event.data || !event.data.after.exists) return;
  const before = event.data.before.exists ? event.data.before.get('stock') : undefined;
  const after = event.data.after.get('stock');
  if (event.data.before.exists && JSON.stringify(before) === JSON.stringify(after)) return;
  await recontarDia(event.params.date);
});

// Si el dueño junta o separa productos en grupos de masa, se recuentan los días que vienen.
exports.recontarCupoPorProducto = onDocumentWritten('products/{id}', async (event) => {
  const before = event.data && event.data.before.exists ? event.data.before.get('stockGroup') || '' : null;
  const after = event.data && event.data.after.exists ? event.data.after.get('stockGroup') || '' : null;
  if (before === after) return;
  const hoy = new Date(Date.now() - 6 * 3600 * 1000).toISOString().slice(0, 10); // hora de México
  const db = getFirestore();
  const dias = await db.collection('deliveryDays').where('__name__', '>=', hoy).get();
  for (const dia of dias.docs) await recontarDia(dia.id);
});

// Al borrar un pedido, también se borra la captura de la transferencia.
exports.limpiarPedidoBorrado = onDocumentDeleted('orders/{id}', async (event) => {
  const path = event.data && event.data.get('paymentProofPath');
  if (typeof path !== 'string' || !path.startsWith('payment-proofs/')) return;
  await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
});

// ---------------------------------------------------------------------------
// Mover o editar un día de entrega (solo el dueño)
// ---------------------------------------------------------------------------
// Cambia la fecha y/o el horario de un día. Sus pedidos se pasan al día nuevo
// (con su cupo) y a cada cliente con pedido pendiente le llega un aviso.
const DIA_RE = /^\d{4}-\d{2}-\d{2}$/;
const HORA_RE = /^\d{2}:\d{2}$/;

async function esDueno(uid) {
  if (!uid) return false;
  const u = await getFirestore().collection('users').doc(uid).get();
  return u.get('role') === 'dueno';
}

// Horario nuevo de un pedido. Si se recorrió todo el horario (misma cantidad de
// horarios), cada pedido se recorre igual; si no, se queda en su hora o en la más cercana.
function horarioNuevo(slot, antes, despues) {
  const i = antes.indexOf(slot);
  if (antes.length === despues.length && i >= 0) return despues[i];
  if (despues.includes(slot)) return slot;
  const min = (s) => { const [h, m] = String(s).split(':').map(Number); return h * 60 + (m || 0); };
  return despues.reduce((best, s) => (Math.abs(min(s) - min(slot)) < Math.abs(min(best) - min(slot)) ? s : best));
}

function diaBonito(date) {
  const [y, m, d] = date.split('-').map(Number);
  return new Intl.DateTimeFormat('es-MX', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' })
    .format(new Date(Date.UTC(y, m - 1, d)));
}

function horarioBonito(slot, minutos) {
  const [h, m] = slot.split(':').map(Number);
  const ini = h * 60 + m;
  const fin = ini + (minutos || 60);
  const f = (x) => `${Math.floor(x / 60)}:${String(x % 60).padStart(2, '0')}`;
  return `${f(ini)} a ${f(fin)}`;
}

const PENDIENTES = ['recibido', 'confirmado', 'enCamino'];

exports.moverDia = onCall({ enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('moverDia', req);
  if (!(await esDueno(req.auth && req.auth.uid))) {
    throw new HttpsError('permission-denied', 'Solo el dueño puede mover días.');
  }
  const { from, to } = req.data || {};
  const slots = Array.isArray(req.data && req.data.slots) ? req.data.slots : [];
  const slotMinutes = Number((req.data && req.data.slotMinutes) || 60);
  if (![15, 30, 60].includes(slotMinutes)) {
    throw new HttpsError('invalid-argument', 'Cada horario dura 15, 30 o 60 minutos.');
  }
  if (!DIA_RE.test(String(from)) || !DIA_RE.test(String(to))) {
    throw new HttpsError('invalid-argument', 'Fecha no válida.');
  }
  // De 5:00 a 22:00 en cuartos de hora caben hasta 68 horarios.
  if (slots.length === 0 || slots.length > 96 || !slots.every((s) => HORA_RE.test(String(s)))) {
    throw new HttpsError('invalid-argument', 'Elige el horario del día.');
  }
  slots.sort();

  const db = getFirestore();
  const fromRef = db.collection('deliveryDays').doc(from);
  const toRef = db.collection('deliveryDays').doc(to);
  const avisos = [];

  await db.runTransaction(async (tx) => {
    avisos.length = 0;
    const dia = await tx.get(fromRef);
    if (!dia.exists) throw new HttpsError('not-found', 'Ese día ya no existe.');
    const pedidos = await tx.get(db.collection('orders').where('deliveryDate', '==', from));
    if (from !== to) {
      const ocupado = await tx.get(db.collection('orders').where('deliveryDate', '==', to));
      if (ocupado.docs.some((o) => PENDIENTES.includes(o.get('status')))) {
        throw new HttpsError('failed-precondition',
          `El ${diaBonito(to)} ya tiene pedidos. Elige otra fecha.`);
      }
    }

    const antes = dia.get('slots') || [];
    const minutosAntes = Number(dia.get('slotMinutes')) || 60;
    const nuevo = { ...dia.data(), slots, slotMinutes };
    if (from !== to) {
      tx.set(toRef, nuevo);
      tx.delete(fromRef);
    } else {
      tx.update(fromRef, { slots, slotMinutes });
    }

    for (const o of pedidos.docs) {
      const slot = horarioNuevo(o.get('slot'), antes, slots);
      if (from === to && slot === o.get('slot') && minutosAntes === slotMinutes) continue;
      if (from === to && slot === o.get('slot')) {
        // Mismo horario de inicio, solo cambió cuánto dura: no hace falta avisar.
        tx.update(o.ref, { slotMinutes });
        continue;
      }
      tx.update(o.ref, {
        deliveryDate: to,
        slot,
        slotMinutes,
        // Lo que ve el cliente en su pedido: "Tu entrega se movió".
        movedFrom: { date: from, slot: o.get('slot'), slotMinutes: minutosAntes },
        movedAt: FieldValue.serverTimestamp(),
      });
      if (PENDIENTES.includes(o.get('status'))) {
        avisos.push({ uid: o.get('customerId'), slot });
      }
    }
  });

  // El cupo del día viejo y del nuevo se recuentan solos al moverse los pedidos.
  for (const a of avisos) {
    try {
      await avisarCliente(a.uid, 'Cambiamos tu entrega 🗓️',
        `Tu pedido ahora llega el ${diaBonito(to)}, de ${horarioBonito(a.slot, slotMinutes)}. ¡Gracias por tu paciencia!`);
    } catch (e) {
      console.error('No se pudo avisar a', a.uid, e);
    }
  }
  return { moved: avisos.length };
});

// ---------------------------------------------------------------------------
// Correo bonito para recuperar la contraseña
// ---------------------------------------------------------------------------
// Se manda desde el Gmail de la panadería con el diseño de functions/correo.js.
// El Gmail y su "contraseña de aplicación" se guardan como secretos:
//   firebase functions:secrets:set CORREO_GMAIL
//   firebase functions:secrets:set CLAVE_GMAIL
// Si algo falla, la app manda el correo normal de Firebase (en español).
const { defineSecret } = require('firebase-functions/params');
const { getAuth } = require('firebase-admin/auth');
const nodemailer = require('nodemailer');
const crypto = require('node:crypto');
const path = require('node:path');
const { correoRecuperacion } = require('./correo');

const correoGmail = defineSecret('CORREO_GMAIL');
const claveGmail = defineSecret('CLAVE_GMAIL');

// Para que nadie use esto para llenar de correos a alguien (y Gmail no bloquee la cuenta).
const MAX_POR_CORREO_POR_HORA = 3;
const MAX_POR_DIA = 300; // Gmail gratis permite unos 500 al día.

exports.mandarRecuperacion = onCall({ secrets: [correoGmail, claveGmail], enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('mandarRecuperacion', req);
  const email = String((req.data && req.data.email) || '').trim().toLowerCase();
  if (email.length > 200 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError('invalid-argument', 'El correo no es válido.');
  }

  // Si no hay cuenta con ese correo no se manda nada, y no se dice, para no revelar quién tiene cuenta.
  let usuario;
  try {
    usuario = await getAuth().getUserByEmail(email);
  } catch (e) {
    if (e.code === 'auth/user-not-found') return { ok: true };
    console.error('No se pudo buscar la cuenta', e);
    throw new HttpsError('internal', 'No se pudo buscar la cuenta.');
  }

  const db = getFirestore();
  const refCorreo = db.collection('limitesCorreo')
    .doc(crypto.createHash('sha256').update(email).digest('hex'));
  const refDia = db.collection('limitesCorreo').doc(`dia-${new Date().toISOString().slice(0, 10)}`);
  const permiso = await db.runTransaction(async (tx) => {
    const [porCorreo, porDia] = await tx.getAll(refCorreo, refDia);
    const ahora = Date.now();
    const recientes = (porCorreo.get('envios') || []).filter((t) => ahora - t < 3600 * 1000);
    if (recientes.length >= MAX_POR_CORREO_POR_HORA) return 'ya-se-mando';
    if ((porDia.get('total') || 0) >= MAX_POR_DIA) return 'limite-del-dia';
    tx.set(refCorreo, { envios: [...recientes, ahora] });
    tx.set(refDia, { total: FieldValue.increment(1) }, { merge: true });
    return 'ok';
  });
  // Ya se le mandaron varios en la última hora: no se manda otro, pero tampoco se dice nada.
  if (permiso === 'ya-se-mando') return { ok: true };
  // Muchos en el día: que la app mande el correo normal de Firebase.
  if (permiso === 'limite-del-dia') throw new HttpsError('resource-exhausted', 'Muchos correos hoy.');

  let enlace;
  try {
    enlace = new URL(await getAuth().generatePasswordResetLink(email));
  } catch (e) {
    console.error('No se pudo crear el enlace', e);
    throw new HttpsError('internal', 'No se pudo crear el enlace.');
  }
  enlace.searchParams.set('lang', 'es'); // la página para poner la contraseña, en español

  // Saludo con su nombre, si lo tiene en su perfil.
  let nombre = '';
  try {
    const perfil = await db.collection('users').doc(usuario.uid).get();
    nombre = String(perfil.get('name') || '').trim().split(/\s+/)[0].slice(0, 40);
  } catch (_) { /* sin nombre */ }

  const { subject, html, text } = correoRecuperacion({ nombre, enlace: enlace.toString() });
  const prueba = process.env.FUNCTIONS_EMULATOR === 'true';
  const remitente = (correoGmail.value() || '').trim() || 'panaderoso@example.com';
  const transporte = prueba
    ? nodemailer.createTransport({ jsonTransport: true })
    : nodemailer.createTransport({
      service: 'gmail',
      auth: { user: remitente, pass: (claveGmail.value() || '').replace(/\s/g, '') },
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 20000,
    });
  try {
    const info = await transporte.sendMail({
      from: { name: 'Panaderoso', address: remitente },
      to: email,
      subject,
      html,
      text,
      attachments: [{ filename: 'oso.png', path: path.join(__dirname, 'imagenes', 'oso.png'), cid: 'oso' }],
    });
    if (prueba) console.log('CORREO_DE_PRUEBA', info.message);
  } catch (e) {
    console.error('No se pudo mandar el correo con Gmail', e);
    throw new HttpsError('unavailable', 'No se pudo mandar el correo.');
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Mensaje escrito por el dueño ("No te preocupes, ya voy en camino")
// ---------------------------------------------------------------------------
// El dueño escribe un mensaje en la app y le llega como notificación a:
//   - todos los clientes con pedido pendiente en un día ({ dia: '2026-11-23' }), o
//   - los clientes que él eligió ({ clientes: ['uid1', 'uid2'] }).
// Solo el dueño puede mandarlos. Regresa a cuántos les llegó y cuántos no tienen
// los avisos activados (para que les mande WhatsApp si hace falta).
const MAX_LETRAS_MENSAJE = 300;
const MAX_CLIENTES_MENSAJE = 200;

exports.mandarMensaje = onCall({ enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('mandarMensaje', req);
  if (!(await esDueno(req.auth && req.auth.uid))) {
    throw new HttpsError('permission-denied', 'Solo el dueño puede mandar mensajes.');
  }
  const datos = req.data || {};
  const texto = String(datos.mensaje || '').trim();
  if (!texto) throw new HttpsError('invalid-argument', 'Escribe el mensaje.');
  if (texto.length > MAX_LETRAS_MENSAJE) {
    throw new HttpsError('invalid-argument', `El mensaje es muy largo (máximo ${MAX_LETRAS_MENSAJE} letras).`);
  }

  const db = getFirestore();
  let clientes;
  if (datos.dia !== undefined && datos.dia !== null) {
    if (!DIA_RE.test(String(datos.dia))) throw new HttpsError('invalid-argument', 'Fecha no válida.');
    const pedidos = await db.collection('orders')
      .where('deliveryDate', '==', String(datos.dia))
      .where('status', 'in', PENDIENTES)
      .get();
    clientes = pedidos.docs.map((d) => d.get('customerId'));
  } else if (Array.isArray(datos.clientes)) {
    clientes = datos.clientes;
  } else {
    throw new HttpsError('invalid-argument', 'Elige a quién mandarle el mensaje.');
  }
  clientes = [...new Set(clientes.filter((u) => typeof u === 'string' && u && !u.includes('/')))];
  if (clientes.length === 0) throw new HttpsError('failed-precondition', 'No hay clientes a quién mandarle.');
  if (clientes.length > MAX_CLIENTES_MENSAJE) {
    throw new HttpsError('invalid-argument', `Son muchos clientes (máximo ${MAX_CLIENTES_MENSAJE}).`);
  }

  const resultados = await Promise.all(clientes.map((uid) =>
    avisarCliente(uid, 'Panaderoso 🥐', texto).catch((e) => {
      logger.warn('mensaje', uid, e);
      return false;
    })));
  const enviados = resultados.filter(Boolean).length;
  logger.info('mensaje del dueño', { clientes: clientes.length, enviados });
  return { enviados, sinAvisos: clientes.length - enviados };
});

// ---------------------------------------------------------------------------
// Borrar la cuenta (lo pide Google Play: el cliente la puede borrar desde la app).
// Se borra: la cuenta (correo y contraseña), sus datos (nombre, teléfono, direcciones,
// avisos), sus reseñas, sus ideas de pan, los días que sugirió y sus fotos (reseñas y capturas de pago).
// Se queda, sin nombre ni teléfono ni dirección: lo vendido en sus pedidos pasados
// (panes, montos y fecha) para las cuentas de la panadería, y la marca de "ya recibió
// el pan de bienvenida" de su domicilio para que la promoción no se repita.
// Con pedidos pendientes no se puede: primero se entregan o se cancelan.
// ---------------------------------------------------------------------------
exports.borrarCuenta = onCall({ enforceAppCheck: EXIGIR_APP_CHECK }, async (req) => {
  anotarPase('borrarCuenta', req);
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Inicia sesión para borrar tu cuenta.');
  if (await esDueno(uid)) {
    throw new HttpsError('failed-precondition', 'La cuenta del dueño no se borra desde la app.');
  }

  const db = getFirestore();
  const pedidos = await db.collection('orders').where('customerId', '==', uid).get();
  if (pedidos.docs.some((d) => PENDIENTES.includes(d.get('status')))) {
    throw new HttpsError('failed-precondition',
      'Tienes un pedido pendiente. Cuando te llegue (o si lo cancelas con nosotros) ya puedes borrar tu cuenta.');
  }

  // Pedidos pasados: quedan solo los panes, montos y fecha.
  const escritor = db.bulkWriter();
  for (const d of pedidos.docs) {
    escritor.update(d.ref, {
      customerName: 'Cuenta borrada',
      phone: '',
      address: '',
      addressNotes: '',
      notes: '',
      lat: null,
      lng: null,
      paymentProofPath: null,
      cuentaBorrada: true,
    });
  }
  for (const col of ['reviews', 'suggestions', 'dayRequests']) {
    const docs = await db.collection(col).where('customerId', '==', uid).get();
    docs.forEach((d) => escritor.delete(d.ref));
  }
  escritor.delete(db.collection('users').doc(uid));
  await escritor.close();

  // Que ya no reciba la ubicación del repartidor.
  await db.collection('tracking').doc('current')
    .update({ viewers: FieldValue.arrayRemove(uid) })
    .catch(() => {});

  const bucket = getStorage().bucket();
  for (const carpeta of ['payment-proofs', 'review-photos']) {
    await bucket.deleteFiles({ prefix: `${carpeta}/${uid}/` })
      .catch((e) => logger.warn('borrarCuenta fotos', carpeta, e));
  }

  await getAuth().deleteUser(uid);
  logger.info('cuenta borrada', { pedidos: pedidos.size });
  return { ok: true };
});
