// Avisos de Panaderoso en la versión web (iPhone con la app en la pantalla de inicio).
// Este archivo corre aparte de la app: recibe el aviso aunque la app esté cerrada y lo muestra.
// Firebase Hosting da los datos del proyecto en /__/firebase/init.js (no hay que copiarlos).
importScripts('https://www.gstatic.com/firebasejs/13.3.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.3.0/firebase-messaging-compat.js');
importScripts('/__/firebase/init.js');

// Con esto basta: los avisos que manda functions/index.js traen título y texto,
// y Firebase los muestra solo.
firebase.messaging();

// Al tocar el aviso: abrir (o traer al frente) la app.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const c of list) {
        if ('focus' in c) return c.focus();
      }
      return clients.openWindow('/');
    })
  );
});
