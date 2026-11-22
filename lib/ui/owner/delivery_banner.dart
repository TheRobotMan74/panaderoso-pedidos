import 'package:material_ui/material_ui.dart';

import '../../logic/geo.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../../services/tracker.dart';
import '../theme.dart';
import '../widgets.dart';

/// Arriba de los pedidos: "Empezar a repartir" / "Terminar reparto".
class DeliveryBanner extends StatefulWidget {
  const DeliveryBanner({super.key});

  @override
  State<DeliveryBanner> createState() => _DeliveryBannerState();
}

class _DeliveryBannerState extends State<DeliveryBanner> {
  final _tracker = DeliveryTracker.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tracker.onAutoStop = _toast;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start({bool resume = false}) async {
    setState(() => _busy = true);
    try {
      final problem = await DeliveryTracker.checkPermission();
      if (problem != null) return _toast(problem);

      final pending = await DeliveryTracker.pendingToday();
      if (pending.isEmpty) return _toast('No hay pedidos pendientes para hoy.');

      if (!resume) {
        final confirmed = pending.where((o) => o.status == OrderStatus.confirmado).length;
        final unconfirmed = pending.where((o) => o.status == OrderStatus.recibido).length;
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Empezar a repartir?'),
            content: Text(
              'Tus ${pending.length} clientes de hoy podrán ver en el mapa por dónde vas, '
              'y les llegará un aviso cuando estés cerca.\n\n'
              '${confirmed > 0 ? '$confirmed pedidos confirmados pasan a "En camino".\n' : ''}'
              '${unconfirmed > 0 ? '$unconfirmed pedidos siguen sin confirmar.\n' : ''}'
              '\nSe cierran los pedidos para hoy. '
              'Verás una notificación fija mientras compartes. '
              'Al entregar el último pedido se deja de compartir solo.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, salir')),
            ],
          ),
        );
        if (ok != true) return;
      }
      final cfg = await Repo.instance.config().first;
      await _tracker.start(alertMeters: cfg.nearAlertMeters, resume: resume);
    } catch (e) {
      _toast('No se pudo empezar el reparto ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _tracker.stop();
      _toast('Listo, ya no se comparte tu ubicación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _tracker,
      builder: (context, _) => StreamBuilder<TrackingInfo>(
        stream: Repo.instance.tracking(),
        builder: (context, snap) {
          final info = snap.data ?? const TrackingInfo();
          final Widget child;
          if (_tracker.running) {
            child = _box(
              key: const ValueKey('repartiendo'),
              gradient: const LinearGradient(colors: [Color(0xFF6E9A5C), Color(0xFF4F7A40)]),
              leading: const PulseDot(color: Colors.white, size: 12),
              title: 'Repartiendo',
              subtitle: '${info.viewers.length} clientes ven por dónde vas'
                  '${info.updatedAt != null ? ' · ubicación ${agoLabel(info.updatedAt, DateTime.now())}' : ''}',
              light: true,
              action: _GhostButton(
                label: 'Terminar',
                onPressed: _busy ? null : _stop,
              ),
            );
          } else if (info.active && !_busy) {
            // La app se cerró a media ruta: el reparto quedó abierto.
            // (Mientras arranca el reparto no se muestra, para no parpadear.)
            child = _box(
              key: const ValueKey('abierto'),
              color: const Color(0xFFFFF1CF),
              leading: const Icon(Icons.pause_circle_rounded, size: 34, color: Pan.caramelo),
              title: 'El reparto quedó abierto',
              subtitle: 'Tus clientes no ven tu ubicación ahorita.',
              // IntrinsicWidth: dentro de un Row el ancho no tiene límite y
              // "stretch" sin él aplastaba el texto a una letra por renglón.
              action: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _start(resume: true),
                      child: const Text('Seguir'),
                    ),
                    TextButton(onPressed: _busy ? null : _stop, child: const Text('Terminar')),
                  ],
                ),
              ),
            );
          } else {
            child = Padding(
              key: const ValueKey('empezar'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Pressable(
                onTap: _busy ? null : _start,
                haptic: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: BoxDecoration(
                    gradient: Pan.gradienteCaramelo,
                    borderRadius: BorderRadius.circular(Pan.radio),
                    boxShadow: const [
                      BoxShadow(color: Color(0x40A85F06), blurRadius: 16, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(13),
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Empezar a repartir',
                                style: TextStyle(
                                    fontFamily: 'Fraunces',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 19,
                                    color: Colors.white)),
                            Text('Tus clientes verán por dónde vas',
                                style: TextStyle(color: Color(0xFFFBE3BE), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            );
          }
          return AnimatedSwitcher(
            duration: Motion.of(context, Motion.medio),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: c),
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget _box({
    required Key key,
    Color? color,
    Gradient? gradient,
    required Widget leading,
    required String title,
    required String subtitle,
    required Widget action,
    bool light = false,
  }) {
    final theme = Theme.of(context);
    final fg = light ? Colors.white : Pan.cacao;
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: PanCard(
        margin: EdgeInsets.zero,
        color: color,
        gradient: gradient,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge!.copyWith(color: fg, fontSize: 19)),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: light ? const Color(0xFFE5F0DD) : Pan.canela)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            action,
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _GhostButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xAAFFFFFF), width: 1.4),
        ),
        child: Text(label),
      );
}
