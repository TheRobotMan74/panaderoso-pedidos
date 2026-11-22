import 'package:material_ui/material_ui.dart';

import '../../logic/geo.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../../services/tracker.dart';

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
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _tracker,
      builder: (context, _) => StreamBuilder<TrackingInfo>(
        stream: Repo.instance.tracking(),
        builder: (context, snap) {
          final info = snap.data ?? const TrackingInfo();
          if (_tracker.running) {
            return _box(
              color: theme.colorScheme.primaryContainer,
              icon: Icons.delivery_dining,
              title: 'Repartiendo',
              subtitle: '${info.viewers.length} clientes ven por dónde vas'
                  '${info.updatedAt != null ? ' · ubicación ${agoLabel(info.updatedAt, DateTime.now())}' : ''}',
              action: OutlinedButton(
                onPressed: _busy ? null : _stop,
                child: const Text('Terminar reparto'),
              ),
            );
          }
          if (info.active) {
            // La app se cerró a media ruta: el reparto quedó abierto.
            return _box(
              color: theme.colorScheme.tertiaryContainer,
              icon: Icons.pause_circle,
              title: 'El reparto quedó abierto',
              subtitle: 'Tus clientes no ven tu ubicación ahorita.',
              action: Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _start(resume: true),
                    child: const Text('Seguir'),
                  ),
                  OutlinedButton(onPressed: _busy ? null : _stop, child: const Text('Terminar')),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.delivery_dining),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Empezar a repartir'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _box({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            action,
          ],
        ),
      ),
    );
  }
}
