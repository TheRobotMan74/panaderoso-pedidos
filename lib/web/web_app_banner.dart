import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/push.dart';
import '../ui/theme.dart';
import 'platform.dart';

/// Aviso de arriba en la versión web (iPhone):
/// - En Safari normal: cómo instalarla en la pantalla de inicio (así llegan los avisos).
/// - Ya instalada: botón para activar los avisos de "tu pan va en camino".
/// Desaparece solo cuando ya no hace falta, o con la ✕.
class WebAppBanner extends StatefulWidget {
  final AppUser user;
  const WebAppBanner({super.key, required this.user});

  @override
  State<WebAppBanner> createState() => _WebAppBannerState();
}

enum _Kind { none, install, enablePush }

class _WebAppBannerState extends State<WebAppBanner> {
  bool _closed = false;
  bool _busy = false;

  _Kind get _kind {
    if (_closed) return _Kind.none;
    final perm = WebPlatform.notificationPermission;
    // En iPhone los avisos solo existen con la app agregada a la pantalla de inicio.
    if (WebPlatform.isIos && !WebPlatform.isStandalone) return _Kind.install;
    if (perm == 'default') return _Kind.enablePush;
    return _Kind.none;
  }

  Future<void> _enable() async {
    // Sin await antes: Safari solo deja pedir permiso en el mismo toque.
    final future = Push.enableWeb(widget.user);
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await future;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '¡Listo! Te avisaremos cuando tu pan vaya en camino 🐻'
              : 'No se activaron los avisos. Puedes activarlos en Ajustes → Notificaciones → Panaderoso.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return AnimatedSize(
      duration: Motion.of(context, Motion.medio),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: kind == _Kind.none
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Material(
                color: Pan.mielClara,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(
                    children: [
                      Icon(
                        kind == _Kind.install ? Icons.add_to_home_screen_rounded : Icons.notifications_active_rounded,
                        color: Pan.caramelo,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: kind == _Kind.install
                            ? const Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Instala Panaderoso: ',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    TextSpan(
                                      text:
                                          'toca Compartir ⬆️ abajo y luego '
                                          '«Agregar a pantalla de inicio». Así te llegan los avisos.',
                                    ),
                                  ],
                                ),
                                style: TextStyle(fontSize: 13.5, color: Pan.cacao),
                              )
                            : const Text(
                                'Activa los avisos para saber cuando tu pan va en camino.',
                                style: TextStyle(fontSize: 13.5, color: Pan.cacao),
                              ),
                      ),
                      if (kind == _Kind.enablePush)
                        _busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : TextButton(onPressed: _enable, child: const Text('Activar')),
                      IconButton(
                        tooltip: 'Cerrar',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 20, color: Pan.canela),
                        onPressed: () => setState(() => _closed = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
