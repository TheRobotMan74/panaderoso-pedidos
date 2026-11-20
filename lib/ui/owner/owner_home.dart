import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import 'calendar_page.dart';
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
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: switch (_tab) {
        0 => const OrdersPage(),
        1 => const DemandPage(),
        2 => const CalendarPage(),
        3 => const ProductsPage(),
        _ => const SettingsPage(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Demanda'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Días'),
          NavigationDestination(icon: Icon(Icons.bakery_dining), label: 'Productos'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
