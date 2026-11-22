// Avisos automáticos de pedidos.
// - Pedido nuevo → aviso al dueño (tema "dueno").
// - Cambio de estado → aviso al cliente que hizo el pedido.
// - Repartidor cerca → aviso al cliente (una sola vez por pedido).
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const STATUS_TEXT = {
  confirmado: 'Tu pedido está confirmado.',
  enCamino: 'Tu pedido va en camino.',
  entregado: 'Tu pedido fue entregado. ¡Buen provecho!',
  cancelado: 'Tu pedido fue cancelado. Escríbenos si tienes dudas.',
};

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

  await avisarCliente(after.customerId, 'Panaderoso', text);
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
function distanciaMetros(lat1, lng1, lat2, lng2) {
  const rad = (d) => d * Math.PI / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(a));
}
