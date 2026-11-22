# Página web (versión para iPhone)

Aquí vive la configuración de **Firebase Hosting** de la versión web: https://panaderoso.web.app

Está separada del `firebase.json` principal a propósito: así `firebase deploy` en Cloud Shell
(funciones y reglas) sigue igual que siempre y nunca toca la página.

La página la arma y la publica sola la acción **Web** de GitHub (`.github/workflows/web.yml`)
cada vez que algo de la app entra a `main`. La carpeta `public/` la llena esa acción; no se guarda en el repo.
