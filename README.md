# Panaderoso: pedidos de pan a domicilio

App de Android (APK) para pedir pan a domicilio. Es una sola app con dos roles:

- **Cliente:** ve el catálogo, arma su pedido, elige día y horario de entrega, paga por
  transferencia (sube la captura) o en efectivo al recibir, y recibe avisos del estado de su pedido.
- **Dueño:** ve los pedidos en vivo, publica los días y horarios de entrega, ve la demanda por día
  y horario para planear las charolas, revisa capturas de transferencia y administra productos.

Hecha con Flutter y Firebase (Authentication, Firestore, Storage, Cloud Messaging y Functions).

## Descargar la APK

Cada cambio que entra a `main` publica la APK en
[Releases](https://github.com/TheRobotMan74/panaderoso-pedidos/releases/latest) como `panaderoso.apk`.
En los pull requests la APK queda en la pestaña **Actions**, como "panaderoso-apk".

## Configurar Firebase (una sola vez)

1. Entra a <https://console.firebase.google.com> con tu cuenta de Google y crea el proyecto `panaderoso`.
2. Cambia al plan **Blaze** (pago por uso). Lo piden Storage y las notificaciones automáticas.
   Con el uso de una panadería normalmente queda dentro de lo gratuito; pon una alerta de presupuesto de $1 USD.
3. **Authentication** → Comenzar → activa **Correo electrónico/contraseña**.
4. **Firestore Database** → Crear base de datos → modo producción.
5. **Storage** → Comenzar.
6. Configuración del proyecto → **Agregar app** → Android → nombre del paquete `mx.panaderoso.pedidos`.
   Descarga `google-services.json`: con sus datos se llena `lib/firebase_options.dart`.
7. Publicar reglas, índices y funciones desde esta carpeta:

   ```sh
   npm install -g firebase-tools
   firebase login
   firebase use --add            # elegir el proyecto panaderoso
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

## Datos

| Colección | Qué guarda | Quién escribe |
| --- | --- | --- |
| `users/{uid}` | nombre, teléfono, dirección, `role`, tokens de avisos | cada usuario (el `role` solo desde la consola) |
| `products/{id}` | nombre, precio, foto, disponible | dueño |
| `deliveryDays/{AAAA-MM-DD}` | abierto, horarios, hora límite para pedir | dueño |
| `orders/{id}` | productos, día, horario, pago, captura, estado | cliente crea; dueño actualiza |
| `config/app` | datos bancarios y reglas de envío | dueño |

Las reglas de seguridad están en `firestore.rules` y `storage.rules`.

## Costo de envío

`lib/logic/shipping.dart`: km de ida × precio por km ($2.80, gasolina del Aveo) × porcentaje
según piezas (1 a 2: 100%, 3 a 5: 50%, 6 o más: gratis), redondeado a $5.
En la fase 1 el envío es gratis; el cobro por distancia se conecta en la fase 2 con el mapa.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
