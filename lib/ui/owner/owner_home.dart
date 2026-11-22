import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../widgets.dart';
import 'calendar_page.dart';
import 'delivery_banner.dart';
import 'demand_page.dart';
import 'orders_page.dart';
import 'products_page.dart';
import 'settings_page.dart';

/// Pantallas del dueño: pedidos en vivo, demanda, calendario, productos y ajustes.
class OwnerHome extends StatefulWidget {
  final AppUser user;
  const OwnerHome({super.key, required this.user});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int _tab = 0;

  static const _titles = ['Pedidos', 'Demanda', 'Días de entrega', 'Productos', 'Ajustes'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            const BearLogo(size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedCount(
                _titles[_tab],
                style: Theme.of(context).appBarTheme.titleTextStyle,
                alignment: Alignment.centerLeft,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FadeThroughSwitcher(
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: switch (_tab) {
            0 => const Column(
                children: [DeliveryBanner(), Expanded(child: OrdersPage())],
              ),
            1 => const DemandPage(),
            2 => const CalendarPage(),
            3 => const ProductsPage(),
            _ => const SettingsPage(),
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Demanda'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Días'),
          NavigationDestination(
              icon: Icon(Icons.bakery_dining_outlined), selectedIcon: Icon(Icons.bakery_dining), label: 'Productos'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
