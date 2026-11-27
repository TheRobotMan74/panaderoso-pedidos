import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_orders_page.dart' show whatsAppUrl;

/// Lo que sale si en Ajustes no hay nombre o WhatsApp.
const defaultContactName = 'Alfonso Núñez';
const defaultContactPhone = '8129332077';

/// Mensaje con el que se abre WhatsApp desde el contacto.
const contactHello = '¡Hola! Te escribo desde la app de Panaderoso 🐻';

String contactNameOf(AppConfig? c) {
  final n = c?.contactName.trim() ?? '';
  return n.isEmpty ? defaultContactName : n;
}

String contactPhoneOf(AppConfig? c) {
  final p = c?.whatsapp.replaceAll(RegExp(r'\D'), '') ?? '';
  return p.isEmpty ? defaultContactPhone : p;
}

/// "Alfonso Núñez" → "AN".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Al final del menú de los clientes: con quién hablar, con su número y los botones
/// de WhatsApp y Llamar. El nombre y el número salen de Ajustes → Contacto.
class ContactCard extends StatelessWidget {
  const ContactCard({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AppConfig>(
        stream: Repo.instance.config(),
        builder: (context, snap) => ContactCardView(
          name: contactNameOf(snap.data),
          phone: contactPhoneOf(snap.data),
        ),
      );
}

class ContactCardView extends StatelessWidget {
  final String name;
  final String phone;
  const ContactCardView({super.key, required this.name, required this.phone});

  /// En pantallas anchas (tablet, plegable abierto, compu) los botones van a un lado.
  static const anchoEnUnRenglon = 560.0;

  /// Menos que esto (celulares muy angostos) y los botones van uno abajo del otro.
  static const anchoBotonesJuntos = 290.0;

  String get _digits => phone.replaceAll(RegExp(r'\D'), '');

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _whatsApp(BuildContext context) async {
    final ok = await launchUrl(whatsAppUrl(phone, contactHello), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok && context.mounted) _snack(context, 'No se pudo abrir WhatsApp. ¿Lo tienes instalado?');
  }

  Future<void> _call(BuildContext context) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: _digits)).catchError((_) => false);
    if (!ok && context.mounted) {
      _snack(context, 'No se pudo abrir el teléfono. El número es ${prettyPhone(phone)}.');
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _digits));
    if (context.mounted) _snack(context, 'Número copiado');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            gradient: Pan.gradienteMiel,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x40E8960F), blurRadius: 12, offset: Offset(0, 5))],
          ),
          alignment: Alignment.center,
          child: Text(
            initialsOf(name),
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              fontSize: 21,
              color: Pan.cacao,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleMedium),
              Text('Dudas o pedidos especiales', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Tooltip(
                message: 'Copiar número',
                child: InkWell(
                  onTap: () => _copy(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            prettyPhone(phone),
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: Pan.caramelo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.copy_rounded, size: 16, color: Pan.canela),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    const pad = EdgeInsets.symmetric(horizontal: 14, vertical: 14);
    final whatsApp = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: Pan.salvia, padding: pad),
      onPressed: () => _whatsApp(context),
      icon: const Icon(Icons.chat_rounded, size: 20),
      label: const Text('WhatsApp', maxLines: 1, softWrap: false),
    );
    final call = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(padding: pad),
      onPressed: () => _call(context),
      icon: const Icon(Icons.call_rounded, size: 20),
      label: const Text('Llamar', maxLines: 1, softWrap: false),
    );

    return PanCard(
      margin: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(builder: (context, c) {
        // Pantalla ancha (tablet, plegable abierto, compu): todo en un renglón y
        // cada botón mide lo que su texto.
        if (c.maxWidth >= anchoEnUnRenglon) {
          return Row(
            children: [
              Expanded(child: who),
              const SizedBox(width: 16),
              whatsApp,
              const SizedBox(width: 10),
              call,
            ],
          );
        }
        // Celular: los dos botones se reparten el ancho; en uno muy angosto van
        // uno abajo del otro para que "WhatsApp" no se corte.
        final narrow = c.maxWidth < anchoBotonesJuntos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            who,
            const SizedBox(height: 14),
            if (narrow) ...[
              whatsApp,
              const SizedBox(height: 8),
              call,
            ] else
              Row(
                children: [
                  Expanded(child: whatsApp),
                  const SizedBox(width: 10),
                  Expanded(child: call),
                ],
              ),
          ],
        );
      }),
    );
  }
}
