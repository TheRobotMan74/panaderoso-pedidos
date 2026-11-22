#!/usr/bin/env bash
# Prepara la versión web de Panaderoso (para iPhone) — se corre UNA sola vez en Cloud Shell.
#
#   bash scripts/preparar-web.sh
#
# Qué hace (se puede correr otra vez sin problema: lo que ya existe se deja igual):
#   1. Prende los servicios de Google que usa la página.
#   2. Da de alta la "app web" en Firebase y la liga a panaderoso.web.app.
#   3. Crea la llave del mapa para la página (solo funciona en panaderoso.web.app).
#   4. Crea la llave de reCAPTCHA (App Check en la web, modo monitoreo) y la registra.
#   5. Deja que la página muestre las fotos de los productos (CORS del almacenamiento).
#   6. Deja que GitHub publique la página sin contraseñas (solo desde main de este repo).
# Al final imprime dos llaves para pegárselas a Claude.
set -uo pipefail

P=panaderoso
NUM=1028279896674
REPO=TheRobotMan74/panaderoso-pedidos
SA=web-deploy@$P.iam.gserviceaccount.com

paso() { echo; echo "==> $*"; }
falla() { echo "!! $*" >&2; exit 1; }

gcloud config set project "$P" >/dev/null 2>&1 || falla "No se pudo elegir el proyecto $P en gcloud."
command -v firebase >/dev/null || falla "Falta la herramienta firebase (npm install -g firebase-tools)."

paso "1/6 Prendiendo servicios de Google (tarda un minuto)…"
gcloud services enable firebasehosting.googleapis.com maps-backend.googleapis.com \
  recaptchaenterprise.googleapis.com firebaseappcheck.googleapis.com apikeys.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com --project "$P" \
  || falla "No se pudieron prender los servicios."

paso "2/6 App web en Firebase…"
APP_ID=$(firebase apps:list WEB --project "$P" --json 2>/dev/null | jq -r '.result[0].appId // empty')
if [ -z "$APP_ID" ]; then
  firebase apps:create WEB "Panaderoso web" --project "$P" >/dev/null || falla "No se pudo crear la app web."
  APP_ID=$(firebase apps:list WEB --project "$P" --json | jq -r '.result[0].appId // empty')
fi
[ -n "$APP_ID" ] || falla "No encontré la app web."
echo "App web: $APP_ID"
if ! firebase hosting:sites:list --project "$P" --json 2>/dev/null | jq -e '.result.sites | length > 0' >/dev/null; then
  firebase hosting:sites:create "$P" --app "$APP_ID" --project "$P" >/dev/null || true
fi
TOKEN=$(gcloud auth print-access-token)
curl -sS -o /dev/null -X PATCH -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $P" \
  -H "Content-Type: application/json" \
  "https://firebasehosting.googleapis.com/v1beta1/projects/$P/sites/$P?updateMask=appId" \
  -d "{\"appId\":\"$APP_ID\"}" || true

paso "3/6 Llave del mapa para la página…"
MAPS_NAME=$(gcloud services api-keys list --project "$P" \
  --filter='displayName="Mapa web Panaderoso"' --format='value(name)' 2>/dev/null | head -1)
if [ -z "$MAPS_NAME" ]; then
  gcloud services api-keys create --project "$P" --display-name="Mapa web Panaderoso" \
    --api-target=service=maps-backend.googleapis.com \
    --allowed-referrers="https://panaderoso.web.app/*,https://panaderoso.firebaseapp.com/*" >/dev/null \
    || falla "No se pudo crear la llave del mapa."
  MAPS_NAME=$(gcloud services api-keys list --project "$P" \
    --filter='displayName="Mapa web Panaderoso"' --format='value(name)' | head -1)
fi
MAPS_KEY=$(gcloud services api-keys get-key-string "$MAPS_NAME" --format='value(keyString)')

paso "4/6 Llave de reCAPTCHA (App Check en la web)…"
RC_NAME=$(gcloud recaptcha keys list --project "$P" \
  --filter='displayName="Panaderoso web"' --format='value(name)' 2>/dev/null | head -1)
if [ -z "$RC_NAME" ]; then
  RC_NAME=$(gcloud recaptcha keys create --project "$P" --display-name="Panaderoso web" --web \
    --domains=panaderoso.web.app,panaderoso.firebaseapp.com --integration-type=score \
    --format='value(name)') || falla "No se pudo crear la llave de reCAPTCHA."
fi
RECAPTCHA=${RC_NAME##*/}
curl -sS -o /dev/null -w "App Check web: HTTP %{http_code}\n" -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $P" -H "Content-Type: application/json" \
  "https://firebaseappcheck.googleapis.com/v1/projects/$P/apps/$APP_ID/recaptchaEnterpriseConfig?updateMask=siteKey" \
  -d "{\"siteKey\":\"$RECAPTCHA\"}"

paso "5/6 Fotos de productos visibles en la página…"
CORS=$(mktemp)
echo '[{"origin":["https://panaderoso.web.app","https://panaderoso.firebaseapp.com"],"method":["GET"],"maxAgeSeconds":3600}]' > "$CORS"
gcloud storage buckets update "gs://$P.firebasestorage.app" --cors-file="$CORS" >/dev/null \
  || echo "(No se pudo; las fotos igual se ven, solo un poco más lento.)"
rm -f "$CORS"

paso "6/6 Permiso para que GitHub publique la página…"
gcloud iam workload-identity-pools describe github --location=global --project "$P" >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools create github --location=global --project "$P" --display-name="GitHub" \
  || falla "No se pudo crear el grupo de GitHub."
gcloud iam workload-identity-pools providers describe github --location=global \
  --workload-identity-pool=github --project "$P" >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools providers create-oidc github --location=global \
    --workload-identity-pool=github --project "$P" --display-name="GitHub" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'" \
  || falla "No se pudo conectar GitHub."
if ! gcloud iam service-accounts describe "$SA" --project "$P" >/dev/null 2>&1; then
  gcloud iam service-accounts create web-deploy --project "$P" \
    --display-name="Publica la página web desde GitHub" || falla "No se pudo crear la cuenta de servicio."
  sleep 15
fi
for R in roles/firebasehosting.admin roles/firebase.viewer roles/serviceusage.serviceUsageConsumer roles/serviceusage.apiKeysViewer; do
  gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role="$R" --condition=None >/dev/null \
    || falla "No se pudo dar el permiso $R."
done
gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$P" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$NUM/locations/global/workloadIdentityPools/github/attribute.repository/$REPO" \
  >/dev/null || falla "No se pudo dar permiso a GitHub."

echo
echo "================  LISTO  ================"
echo "Copia estas 2 líneas y pégaselas a Claude:"
echo
echo "MAPS_KEY=$MAPS_KEY"
echo "RECAPTCHA=$RECAPTCHA"
echo "========================================="
