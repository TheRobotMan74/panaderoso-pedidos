import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/updates.dart';
import 'theme.dart';

/// Revisa una vez al abrir la app si hay novedades, sin estorbar:
/// - APK nueva: ventana "Hay una versión nueva" con botón para descargarla.
/// - Mejora ya bajada: aviso abajo para cerrar y abrir la app y verla.
class UpdateWatcher extends StatefulWidget {
  final Widget child;
  const UpdateWatcher({super.key, required this.child});

  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> {
  /// Una sola vez cada que se abre la app, aunque la pantalla se vuelva a armar.
  static bool _checked = false;

  @override
  void initState() {
    super.initState();
    // En la web no hay APK ni mejoras: cada vez que se abre ya trae lo más nuevo.
    if (_checked || !kReleaseMode || kIsWeb) return;
    _checked = true;
    // Primero que cargue la pantalla; la revisión va después, en segundo plano.
    Future.delayed(const Duration(seconds: 3), _check);
  }

  Future<void> _check() async {
    final apk = await Updates.checkNewApk();
    if (!mounted) return;
    if (apk != null) {
      await showNewApkDialog(context, apk);
      return;
    }
    final ready = await Updates.downloadPatch();
    if (!mounted || !ready) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 8),
      content: Text('Hay una mejora lista ✨ Cierra la app y vuelve a abrirla para verla.'),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ventana para bajar e instalar la APK nueva.
Future<void> showNewApkDialog(BuildContext context, NewApk apk) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded, color: Pan.caramelo, size: 32),
      title: const Text('Hay una versión nueva'),
      content: Text(
        'Baja la versión ${apk.number} de Panaderoso para seguir usando todo.\n\n'
        '1. Toca «Descargar».\n'
        '2. Cuando termine, abre el archivo panaderoso.apk.\n'
        '3. Toca «Actualizar».\n\n'
        'Tu cuenta y tus pedidos se quedan igual.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Después')),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          label: const Text('Descargar'),
          onPressed: () async {
            Navigator.pop(ctx);
            final ok = await launchUrl(apk.download, mode: LaunchMode.externalApplication)
                .catchError((_) => false);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No se pudo abrir la descarga. Revisa tu internet e intenta otra vez.'),
              ));
            }
          },
        ),
      ],
    ),
  );
}

/// Texto chiquito con la versión instalada, como "Versión 25 · mejora 2".
class VersionLabel extends StatelessWidget {
  const VersionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Updates.versionLabel(),
      builder: (context, snap) => Text(
        snap.data ?? '',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Pan.canela),
      ),
    );
  }
}
