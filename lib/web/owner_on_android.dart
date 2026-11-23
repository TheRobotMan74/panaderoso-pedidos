import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../services/push.dart';

/// Lo que ve el dueño si entra desde la versión web: su panel está en Android.
class OwnerOnAndroidPage extends StatelessWidget {
  const OwnerOnAndroidPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Pan.crema,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FloatingBear(size: 96),
              const SizedBox(height: 18),
              Text(
                'El panel del dueño está en la app de Android',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta versión web es para que los clientes con iPhone hagan sus pedidos. '
                'Para ver pedidos, cupos y repartir, usa Panaderoso en tu Android.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => signOutAndForgetPush(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
