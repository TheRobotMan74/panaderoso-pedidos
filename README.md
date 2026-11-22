# Panaderoso: pedidos de pan a domicilio

App de Android (APK) para pedir pan a domicilio. Es una sola app con dos roles:

- **Cliente:** ve el catálogo, arma su pedido, elige día y horario de entrega, paga por
  transferencia (sube la captura) o en efectivo al recibir, y recibe avisos del estado de su pedido.
- **Dueño:** ve los pedidos en vivo, publica los días y horarios de entrega, ve la demanda por día
  y horario para planear las charolas, revisa capturas de transferencia y administra productos.

Hecha con Flutter y Firebase (Authentication, Firestore, Storage, Cloud Messaging y Functions).

## Descargar la APK

La APK más nueva está en
[Releases](https://github.com/TheRobotMan74/panaderoso-pedidos/releases/latest) como `panaderoso.apk`.
En los pull requests la APK queda en la pestaña **Actions**, como "panaderoso-apk".

## Actualizaciones sin reinstalar (Shorebird)

Cuando un cambio entra a `main`, GitHub decide solo cómo llega a los celulares:

- **Mejora** (lo normal): si el cambio es de pantallas o lógica, se manda como parche de
  [Shorebird](https://shorebird.dev). La app lo baja sola al abrirse y se ve la siguiente vez que se abre.
  Nadie instala nada. La mejora queda anotada en las notas de la última versión en Releases.
- **APK nueva**: si cambió algo que un parche no puede llevar (plugins, permisos, cosas de Android, imágenes),
  se publica una APK nueva en Releases y la app muestra "Hay una versión nueva" con un botón para bajarla.
- **Nada**: si el cambio no toca la app (funciones, reglas, este README).

Para forzar una APK nueva: **Actions → APK → Run workflow**, marca "Armar APK nueva" y dale **Run workflow**.
En la app del dueño, abajo en **Ajustes**, se ve la versión y la mejora puestas (por ejemplo "Versión 25 · mejora 2").

Configuración (una sola vez): crear cuenta gratis en <https://console.shorebird.dev>, crear una API key
(menú de la cuenta → **API keys** → **Create API key**, permiso **Full access**, vence en 1 año) y guardarla
como secreto `SHOREBIRD_TOKEN` del repositorio. La primera vez GitHub crea la app en Shorebird y guarda
`shorebird.yaml` en `main`. Sin el secreto, todo funciona como antes (APK nueva en cada cambio).

Plan gratis de Shorebird: 5,000 instalaciones de mejoras al mes (cada celular que recibe una mejora cuenta una).
Si se pasa, las mejoras dejan de llegar hasta el mes siguiente; no cobran extra. La API key vence al año: hay que
crear otra y reemplazar el secreto.

## Configurar Firebase (una sola vez)

1. Entra a <https://console.firebase.google.com> con tu cuenta de Google y crea el proyecto `panaderoso`.
2. Cambia al plan **Blaze** (pago por uso). Lo piden Storage y las notificaciones automáticas.
   Con el uso de una panadería normalmente queda dentro de lo gratuito; pon una alerta de presupuesto de $1 USD.
3. **Authentication** → Comenzar → activa **Correo electrónico/contraseña**.
4. **Firestore Database** → Crear base de datos → modo producción.
5. **Storage** → Comenzar.
6. Configuración del proyecto → **Agregar app** → Android → nombre del paquete `mx.panaderoso.pedidos`.
   Descarga `google-services.json`: con sus datos se llena `lib/firebase_options.dart`.
   (Ya hecho: el archivo está en `android/app/` y `.firebaserc` apunta al proyecto `panaderoso`.)
7. Publicar reglas, índices y funciones desde esta carpeta:

   ```sh
   npm install -g firebase-tools
   firebase login
   (cd functions && npm install)
   firebase deploy
   ```

8. Hazte dueño: crea tu cuenta en la app, y en Firestore abre `users/<tu id>` y agrega el campo
   `role` con el valor `dueno`. Cierra y abre la app.

## Firma de la APK

Para que cada APK nueva se instale encima de la anterior, GitHub firma con una llave fija.
Se configura con tres secretos del repositorio (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` y `ANDROID_KEY_ALIAS`.
Sin ellos, la APK se firma con una llave de pruebas que cambia en cada armado.

## Diseño

Estilo cálido de panadería, con los colores del oso del ícono: miel y caramelo sobre papel crema.

- Colores, letras y transiciones: `lib/ui/theme.dart`. Letras Fraunces (títulos) y Nunito (texto),
  incluidas en `assets/fonts/` (licencia OFL) para que se vean igual sin internet.
- Piezas reutilizables y animaciones (tarjetas, botón de miel, esqueletos de carga, cascada al aparecer,
  oso flotando, puntito "en vivo"): `lib/ui/widgets.dart`.
- Las animaciones solo usan opacidad, movimiento y escala (baratas en celulares sencillos) y se apagan solas
  si el celular tiene activado "Quitar animaciones" en Accesibilidad.

## Datos

| Colección | Qué guarda | Quién escribe |
| --- | --- | --- |
| `users/{uid}` | nombre, teléfono, dirección, `lat`/`lng` de la casa, `role`, tokens de avisos | cada usuario (el `role` solo desde la consola) |
| `products/{id}` | nombre, precio, foto, disponible | dueño |
| `deliveryDays/{AAAA-MM-DD}` | abierto, horarios, hora límite para pedir | dueño |
| `orders/{id}` | productos, día, horario, pago, captura, estado, `lat`/`lng`, `nearNotified` | cliente crea; dueño actualiza |
| `config/app` | datos bancarios, reglas de envío, `nearAlertMeters` | dueño |
| `tracking/current` | reparto en vivo: ubicación del repartidor, día, `viewers` (clientes con pedido ese día) | dueño; solo lo leen los `viewers` |

Las reglas de seguridad están en `firestore.rules` y `storage.rules`.

## Mapa y reparto en vivo

- El cliente marca su casa en Google Maps al registrarse (las cuentas viejas lo hacen una vez al abrir la app).
  La búsqueda y la dirección escrita usan el buscador de Android (gratis).
- **Empezar a repartir** (pestaña Pedidos del dueño) comparte la ubicación con un servicio en primer
  plano (notificación fija; solo permiso "mientras se usa la app"). Escribe cada ~30 m y como mucho
  cada 10 s. Se apaga solo al entregar el último pedido del día.
- La función `avisoRepartidorCerca` avisa a cada cliente una vez cuando el repartidor está a
  `nearAlertMeters` (1000 m por omisión) de su casa.
- La llave de Google Maps va en `android/gradle.properties` como `MAPS_API_KEY`, restringida a
  `mx.panaderoso.pedidos` + la huella SHA-1 de la llave de firma y solo a "Maps SDK for Android".

## Costo de envío

`lib/logic/shipping.dart`: km de ida × precio por km ($2.80, gasolina del Aveo) × porcentaje
según piezas (1: 100%, 2 a 5: 25%, 6 o más: gratis), redondeado a $5.
En la fase 1 el envío es gratis; el cobro por distancia se conecta en la fase 2 con el mapa.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
