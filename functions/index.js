// Avisos automáticos de pedidos.
// - Pedido nuevo → aviso al dueño (tema "dueno").
// - Cambio de estado → aviso al cliente que hizo el pedido.
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

  const userRef = getFirestore().collection('users').doc(after.customerId);
  const user = await userRef.get();
  const tokens = user.get('fcmTokens') || [];
  if (tokens.length === 0) return;

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: 'Panaderoso', body: text },
    android: { priority: 'high', notification: { sound: 'default' } },
  });

  // Quitar tokens de celulares que ya no existen.
  const dead = tokens.filter((_, i) => {
    const code = res.responses[i].error?.code;
    return code === 'messaging/registration-token-not-registered'
      || code === 'messaging/invalid-registration-token';
  });
  if (dead.length) await userRef.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
});
