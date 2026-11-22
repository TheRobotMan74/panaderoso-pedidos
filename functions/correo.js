// Correo bonito para recuperar la contraseña, con el oso y los colores de la app.
// Va en tablas y con estilos dentro de cada etiqueta porque así lo entienden
// Gmail, Outlook y las apps de correo del celular.

const C = {
  crema: '#FBF4E6',
  papel: '#FFFCF6',
  miel: '#F4B41A',
  mielClara: '#FFE3A3',
  caramelo: '#A85F06',
  tostado: '#7A4A12',
  cacao: '#3B2A1E',
  canela: '#7A6352',
  borde: '#F0E0C2',
};

const SERIF = "Georgia, 'Times New Roman', serif";
const SANS = "'Nunito', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

function escapar(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Arma el correo de "olvidé mi contraseña".
 * @param {{nombre?: string, enlace: string, logo?: string}} datos
 *   nombre: primer nombre del cliente (puede ir vacío).
 *   enlace: enlace de Firebase para poner la contraseña nueva.
 *   logo: de dónde sale la imagen del oso (en el correo real va adjunta como "cid:oso").
 */
function correoRecuperacion({ nombre = '', enlace, logo = 'cid:oso' }) {
  const saludo = nombre ? `¡Hola, ${escapar(nombre)}!` : '¡Hola!';
  const url = escapar(enlace);
  const subject = 'Cambia tu contraseña de Panaderoso 🥐';
  const previa = 'Toca el botón para crear una contraseña nueva. El enlace sirve por 1 hora.';

  const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${escapar(subject)}</title>
</head>
<body style="margin:0; padding:0; background:${C.crema};">
<div style="display:none; max-height:0; overflow:hidden; opacity:0; color:transparent;">${previa}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.crema}" style="background:${C.crema};">
  <tr>
    <td align="center" style="padding:28px 14px 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">

        <!-- Encabezado de miel con el oso -->
        <tr>
          <td align="center" bgcolor="${C.miel}" style="background:${C.miel}; background-image:linear-gradient(135deg,#F7C547,#E8960F); border-radius:28px 28px 0 0; padding:30px 24px 26px;">
            <img src="${escapar(logo)}" width="104" height="104" alt="Panaderoso" style="display:block; width:104px; height:104px; border-radius:50%; border:5px solid ${C.papel}; background:${C.papel};">
            <div style="font-family:${SERIF}; font-size:22px; font-weight:bold; color:${C.cacao}; padding-top:12px; letter-spacing:0.3px;">Panaderoso</div>
            <div style="font-family:${SANS}; font-size:13px; font-weight:bold; color:#5A3A12; padding-top:2px;">Pan recién horneado a tu puerta</div>
          </td>
        </tr>

        <!-- Tarjeta -->
        <tr>
          <td bgcolor="${C.papel}" style="background:${C.papel}; border:1px solid ${C.borde}; border-top:0; border-radius:0 0 28px 28px; padding:30px 28px 26px;">
            <div style="font-family:${SANS}; font-size:16px; font-weight:bold; color:${C.canela};">${saludo} 👋</div>
            <h1 style="margin:6px 0 0; font-family:${SERIF}; font-size:28px; line-height:1.2; color:${C.cacao}; font-weight:bold;">¿Olvidaste tu contraseña?</h1>
            <p style="margin:12px 0 0; font-family:${SANS}; font-size:16px; line-height:1.55; color:${C.canela};">
              No pasa nada. Toca el botón para crear una contraseña nueva y seguir pidiendo tu pan calientito.
            </p>

            <!-- Botón -->
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:26px auto 10px;">
              <tr>
                <td align="center" bgcolor="${C.caramelo}" style="border-radius:18px; background:${C.caramelo}; background-image:linear-gradient(135deg,#C27512,#8E4E05);">
                  <a href="${url}" target="_blank" style="display:inline-block; padding:17px 34px; font-family:${SANS}; font-size:17px; font-weight:bold; color:#FFFFFF; text-decoration:none; border-radius:18px;">🔑&nbsp; Crear contraseña nueva</a>
                </td>
              </tr>
            </table>
            <div style="text-align:center; font-family:${SANS}; font-size:13px; color:${C.canela};">El enlace sirve durante 1 hora.</div>

            <!-- Línea punteada, como en el ticket de la app -->
            <div style="border-top:2px dashed #E2CFAF; margin:26px 0 18px; height:0; line-height:0; font-size:0;">&nbsp;</div>

            <p style="margin:0; font-family:${SANS}; font-size:14px; line-height:1.5; color:${C.canela};">
              <strong style="color:${C.cacao};">¿No lo pediste tú?</strong> Ignora este correo: tu contraseña sigue igual.
            </p>
            <p style="margin:14px 0 0; font-family:${SANS}; font-size:12.5px; line-height:1.5; color:${C.canela};">
              ¿El botón no abre? Copia y pega este enlace en tu navegador:<br>
              <a href="${url}" target="_blank" style="color:${C.caramelo}; word-break:break-all;">${url}</a>
            </p>
          </td>
        </tr>

        <tr>
          <td align="center" style="padding:20px 10px 0; font-family:${SANS}; font-size:12.5px; line-height:1.5; color:${C.canela};">
            🥐 Con cariño, el equipo de Panaderoso
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;

  const text = [
    nombre ? `¡Hola, ${nombre}!` : '¡Hola!',
    '',
    '¿Olvidaste tu contraseña? No pasa nada.',
    'Abre este enlace para crear una contraseña nueva (sirve durante 1 hora):',
    enlace,
    '',
    'Si tú no lo pediste, ignora este correo: tu contraseña sigue igual.',
    '',
    'Con cariño, el equipo de Panaderoso 🥐',
  ].join('\n');

  return { subject, html, text };
}

module.exports = { correoRecuperacion };
