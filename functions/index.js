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

// App Check en las funciones que llama la app (hacerPedido, moverDia, mandarRecuperacion).
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
  const yaAvisado = await db.runTransaction(async (tx) => {
    const d = await tx.get(dia);
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
  await Promise.all(clientes.map((uid) => avisarCliente(uid, '¡Ya salimos a repartir! 🥐',
    'Tu pan va en camino. Toca para ver en el mapa por dónde va.').catch((e) => logger.warn('aviso salida', uid, e))));
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

async function avisarCliente(uid, title, body) {
  const userRef = getFirestore().collection('users').doc(uid);
  const user = await userRef.get();
  const tokens = user.get('fcmTokens') || [];
  if (tokens.length === 0) return;

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

  // Quitar tokens de celulares que ya no existen.
  const dead = tokens.filter((_, i) => {
    const code = res.responses[i].error?.code;
    return code === 'messaging/registration-token-not-registered'
      || code === 'messaging/invalid-registration-token';
  });
  if (dead.length) await userRef.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
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

    const prods = await tx.getAll(...ids.map((id) => db.collection('products').doc(id)));
    const stock = await tx.get(stockRef);

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

    const pieces = items.reduce((s, i) => s + i.qty, 0);
    const subtotal = items.reduce((s, i) => s + i.price * i.qty, 0);
    const shippingFee = costoEnvio(config, numeroONull(d.lat), numeroONull(d.lng), pieces);

    tx.set(stockRef, { used, updatedAt: FieldValue.serverTimestamp() });
    tx.create(orderRef, {
      customerId: uid,
      customerName: texto(d.customerName, 120),
      phone: texto(d.phone, 40),
      address: texto(d.address, 300),
      addressNotes: texto(d.addressNotes, 300),
      items,
      pieces,
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
      lat: numeroONull(d.lat),
      lng: numeroONull(d.lng),
      nearNotified: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { id: orderRef.id };
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
