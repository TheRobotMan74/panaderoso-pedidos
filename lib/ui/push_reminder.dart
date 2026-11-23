import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../services/push.dart';
import 'fold_store.dart';
import 'theme.dart';

/// Recordatorio para prender las notificaciones (Android), si están apagadas.
/// Se quita solo en cuanto las prenden (se revisa al volver a la app).
///
/// En el inicio sale solo una de cada 3 veces que se abre la app (la 1.ª, 4.ª,
/// 7.ª…), para animar sin fastidiar. En el mapa del pedido sale siempre que
/// estén apagadas, porque ahí es justo cuando sirven.
///
/// [compact]: versión sin ✕ para el mapa de "¿Dónde va mi pedido?".
class PushReminder extends StatefulWidget {
  final bool compact;
  const PushReminder({super.key, this.compact = false});

  @override
  State<PushReminder> createState() => _PushReminderState();
}

/// ¿Toca recordar en esta apertura de la app? [openNumber] empieza en 1.
bool remindOnOpen(int openNumber) => openNumber % 3 == 1;

/// Cuenta las veces que se abre la app (una por arranque) en un archivito del celular.
Future<bool> _countOpen() async {
  var n = 0;
  try {
    n = int.tryParse((await FoldStore.read(name: 'panaderoso_aperturas'))?.trim() ?? '') ?? 0;
  } catch (_) {}
  n++;
  try {
    await FoldStore.write('$n', name: 'panaderoso_aperturas');
  } catch (_) {}
  return remindOnOpen(n);
}

class _PushReminderState extends State<PushReminder> {
  /// Se cerró con la ✕: no vuelve a salir hasta que se abra otra vez la app.
  static bool _dismissed = false;

  /// Si en esta apertura de la app toca recordar (se calcula una sola vez).
  static final Future<bool> _thisOpen = _countOpen();
  static bool _turn = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.compact && !kIsWeb) {
      _thisOpen.then((v) {
        if (v != _turn && mounted) setState(() => _turn = v);
      });
    }
  }

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
        final show = enabled == false && (widget.compact || (_turn && !_dismissed));
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
                                        : 'Préndelos y te avisamos cuando confirmemos tu pedido, cuando salga en camino y cuando ya esté cerca de tu casa 🐻',
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
