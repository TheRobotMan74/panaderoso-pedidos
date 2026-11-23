import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../services/push.dart';
import 'theme.dart';

/// Recordatorio para prender las notificaciones (Android), si están apagadas.
/// Se quita solo en cuanto las prenden (se revisa al volver a la app).
///
/// [compact]: versión sin ✕ para el mapa de "¿Dónde va mi pedido?".
class PushReminder extends StatefulWidget {
  final bool compact;
  const PushReminder({super.key, this.compact = false});

  @override
  State<PushReminder> createState() => _PushReminderState();
}

class _PushReminderState extends State<PushReminder> {
  /// Se cerró con la ✕: no vuelve a salir hasta que se abra otra vez la app.
  static bool _dismissed = false;
  bool _busy = false;

  /// Ya se le pidió el permiso y Android no lo mostró: el botón lleva a Ajustes.
  bool _goToSettings = false;

  Future<void> _activate() async {
    if (_goToSettings) {
      await Push.openSettings().catchError((_) => false);
      return;
    }
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await Push.ask();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _goToSettings = !ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '¡Listo! Te avisaremos cuando tu pan vaya en camino 🐻'
              : 'Tu celular no dejó prenderlas desde aquí. Toca «Abrir ajustes» → Notificaciones → Permitir.',
        ),
        action: ok ? null : SnackBarAction(label: 'Abrir ajustes', onPressed: Push.openSettings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return ValueListenableBuilder<bool?>(
      valueListenable: Push.enabled,
      builder: (context, enabled, _) {
        final show = enabled == false && (widget.compact || !_dismissed);
        return AnimatedSize(
          duration: Motion.of(context, Motion.medio),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: widget.compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Material(
                    color: Pan.mielClara,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(14, 10, widget.compact ? 8 : 4, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: Pan.caramelo),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Tienes apagados los avisos. ',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  TextSpan(
                                    text: widget.compact
                                        ? 'Préndelos y te avisamos cuando tu pan esté cerca.'
                                        : 'Préndelos para saber cuando tu pan va en camino y cuando ya está cerca.',
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13.5, color: Pan.cacao),
                            ),
                          ),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _activate,
                              child: Text(_goToSettings ? 'Abrir ajustes' : 'Activar'),
                            ),
                          if (!widget.compact)
                            IconButton(
                              tooltip: 'Cerrar',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 20, color: Pan.canela),
                              onPressed: () => setState(() => _dismissed = true),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
