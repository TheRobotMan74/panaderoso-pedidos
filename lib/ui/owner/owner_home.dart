import 'package:material_ui/material_ui.dart';

import '../../logic/day_requests.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../widgets.dart';
import 'calendar_page.dart';
import 'delivery_banner.dart';
import 'demand_page.dart';
import 'feedback_page.dart';
import 'customers_page.dart';
import 'orders_page.dart';
import 'products_page.dart';
import 'send_message_page.dart';
import 'settings_page.dart';
import '../../services/push.dart';

/// Pantallas del dueño: pedidos en vivo, demanda, calendario, productos y ajustes.
class OwnerHome extends StatefulWidget {
  final AppUser user;
  const OwnerHome({super.key, required this.user});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int _tab = 0;
  late final _newFeedback = unseenFeedbackCount();
  late final _newDayRequests = Repo.instance
      .allDayRequests()
      .map((l) => unseenRequests(l, DateTime.now()))
      .handleError((_) {})
      .asBroadcastStream();

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
              // Con tantos íconos arriba, un título largo se achica en vez de cortarse.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedCount(
                  _titles[_tab],
                  style: Theme.of(context).appBarTheme.titleTextStyle,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<int>(
            stream: _newFeedback,
            builder: (context, snap) {
              final n = snap.data ?? 0;
              return IconButton(
                tooltip: 'Reseñas e ideas de clientes',
                icon: Badge(
                  isLabelVisible: n > 0,
                  label: Text('$n'),
                  child: const Icon(Icons.reviews_rounded),
                ),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FeedbackPage())),
              );
            },
          ),
          IconButton(
            tooltip: 'Clientes',
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomersPage())),
          ),
          IconButton(
            tooltip: 'Mandar mensaje a clientes',
            icon: const Icon(Icons.chat_rounded),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SendMessagePage())),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => signOutAndForgetPush(),
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
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Pedidos'),
          const NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Demanda'),
          // Numerito cuando hay clientes nuevos sugiriendo días.
          NavigationDestination(
            icon: _DaysIcon(stream: _newDayRequests, selected: false),
            selectedIcon: _DaysIcon(stream: _newDayRequests, selected: true),
            label: 'Días',
          ),
          const NavigationDestination(
              icon: Icon(Icons.bakery_dining_outlined),
              selectedIcon: Icon(Icons.bakery_dining),
              label: 'Productos'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}

class _DaysIcon extends StatelessWidget {
  final Stream<int> stream;
  final bool selected;
  const _DaysIcon({required this.stream, required this.selected});

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: stream,
        builder: (context, snap) {
          final n = snap.data ?? 0;
          return Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: Icon(selected ? Icons.calendar_month : Icons.calendar_month_outlined),
          );
        },
      );
}
