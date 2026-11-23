import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../logic/schedule.dart';
import '../../logic/stock.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../../web/web_app_banner.dart';
import '../feedback_widgets.dart';
import '../format.dart';
import '../product_image.dart';
import '../promo_widgets.dart';
import '../profile_page.dart';
import '../push_reminder.dart';
import '../stock_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'checkout_page.dart';
import 'my_orders_page.dart';
import 'product_detail_page.dart';
import '../../services/push.dart';

class CustomerHome extends StatefulWidget {
  final AppUser user;
  const CustomerHome({super.key, required this.user});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final _cart = Cart();
  int _tab = 0;

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  void _openCheckout() async {
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(user: widget.user, cart: _cart)),
    );
    if (placed == true && mounted) setState(() => _tab = 1);
  }

  void _openMenu(String v) {
    if (v == 'perfil') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePage(uid: widget.user.uid, existing: widget.user, editing: true),
        ),
      );
    } else if (v == 'idea') {
      showSuggestSheet(context, widget.user);
    } else if (v == 'salir') {
      signOutAndForgetPush();
    }
  }

  /// En la versión web (iPhone) arriba va el aviso para instalarla o activar avisos.
  /// En Android, si tiene apagadas las notificaciones, el recordatorio para prenderlas.
  Widget _withWebBanner(Widget body) => Column(children: [
        kIsWeb ? WebAppBanner(user: widget.user) : const PushReminder(),
        Expanded(child: body),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: AnimatedCount(
          _tab == 0 ? 'Panaderoso' : 'Mis pedidos',
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menú',
            offset: const Offset(0, 52),
            onSelected: _openMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'idea',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lightbulb_rounded),
                  title: Text('Sugerir un pan'),
                ),
              ),
              PopupMenuItem(
                value: 'perfil',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.home_rounded),
                  title: Text('Mis datos y direcciones'),
                ),
              ),
              PopupMenuItem(
                value: 'salir',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.only(right: 16),
              child: BearLogo(size: 40),
            ),
          ),
        ],
      ),
      body: _withWebBanner(Stack(
        children: [
          Positioned.fill(
            child: FadeThroughSwitcher(
              child: _tab == 0
                  ? _Catalog(key: const ValueKey('pan'), cart: _cart, user: widget.user)
                  : MyOrdersPage(
                      key: const ValueKey('pedidos'),
                      uid: widget.user.uid,
                      homeLat: widget.user.lat,
                      homeLng: widget.user.lng,
                    ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: ListenableBuilder(
              listenable: _cart,
              builder: (context, _) => _CartBar(
                visible: _tab == 0 && !_cart.isEmpty,
                pieces: _cart.pieces,
                total: _cart.subtotal,
                onTap: _openCheckout,
              ),
            ),
          ),
        ],
      )),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bakery_dining_outlined),
            selectedIcon: Icon(Icons.bakery_dining),
            label: 'Pan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Mis pedidos',
          ),
        ],
      ),
    );
  }
}

/// Barra flotante del carrito: entra desde abajo y "brinca" cuando agregas algo.
class _CartBar extends StatefulWidget {
  final bool visible;
  final int pieces;
  final double total;
  final VoidCallback onTap;
  const _CartBar({required this.visible, required this.pieces, required this.total, required this.onTap});

  @override
  State<_CartBar> createState() => _CartBarState();
}

class _CartBarState extends State<_CartBar> with SingleTickerProviderStateMixin {
  late final _bump = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void didUpdateWidget(_CartBar old) {
    super.didUpdateWidget(old);
    if (widget.pieces > old.pieces && old.pieces > 0 && !Motion.off(context)) {
      _bump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.medio);
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedSlide(
        offset: widget.visible ? Offset.zero : const Offset(0, 1.6),
        duration: d,
        curve: widget.visible ? Motion.rebote : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1 : 0,
          duration: d,
          child: AnimatedBuilder(
            animation: _bump,
            builder: (context, child) {
              // Sube a 1.05 y regresa, como un latido.
              final t = _bump.value;
              final s = 1 + 0.05 * (t < 0.4 ? t / 0.4 : (1 - t) / 0.6);
              return Transform.scale(scale: s, child: child);
            },
            child: Pressable(
              onTap: widget.onTap,
              haptic: true,
              child: Container(
                height: 64,
                padding: const EdgeInsets.fromLTRB(10, 8, 20, 8),
                decoration: BoxDecoration(
                  color: Pan.cacao,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x553B2A1E), blurRadius: 22, offset: Offset(0, 10)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(gradient: Pan.gradienteMiel, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: AnimatedCount(
                        '${widget.pieces}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18, color: Pan.cacao),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ver mi pedido',
                              style: TextStyle(
                                  color: Pan.crema, fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('Elige día y horario',
                              style: TextStyle(color: Color(0xFFCDB89C), fontSize: 12.5)),
                        ],
                      ),
                    ),
                    AnimatedCount(
                      money(widget.total),
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Pan.miel,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, color: Pan.miel),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  final Cart cart;
  final AppUser user;
  const _Catalog({super.key, required this.cart, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: Repo.instance.products(),
      builder: (context, snap) {
        if (!snap.hasData) return const SkeletonList(withImage: true, count: 5);
        final products = snap.data!;
        if (products.isEmpty) {
          return const EmptyState(
            title: 'El horno se está calentando',
            message: 'Todavía no hay productos. Vuelve prontito.',
          );
        }
        final first = user.name.trim().split(' ').first;
        return ListenableBuilder(
          listenable: cart,
          builder: (context, _) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            itemCount: products.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) return FadeSlideIn(child: _Welcome(name: first, user: user));
              if (i == products.length + 1) {
                // Al final del menú: reseñas escogidas por el dueño y "Sugiere un pan".
                return FadeSlideIn(
                  index: i,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [const FeaturedReviews(), SuggestBreadCard(user: user)],
                  ),
                );
              }
              final p = products[i - 1];
              return FadeSlideIn(
                index: i,
                child: _ProductCard(product: p, cart: cart),
              );
            },
          ),
        );
      },
    );
  }
}

/// Saludo y banner de miel arriba del catálogo.
class _Welcome extends StatelessWidget {
  final String name;
  final AppUser user;
  const _Welcome({required this.name, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? '${greeting(DateTime.now())} 👋' : '${greeting(DateTime.now())}, $name 👋',
            style: theme.textTheme.bodyLarge!.copyWith(color: Pan.canela, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text('¿Qué se te antoja hoy?', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            decoration: BoxDecoration(
              gradient: Pan.gradienteMiel,
              borderRadius: BorderRadius.circular(Pan.radio),
              boxShadow: const [
                BoxShadow(color: Color(0x40E8960F), blurRadius: 18, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recién horneado',
                          style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w700,
                              fontSize: 21,
                              color: Pan.cacao)),
                      SizedBox(height: 4),
                      Text('Arma tu pedido y te lo llevamos calientito a tu puerta.',
                          style: TextStyle(color: Color(0xFF5A3A12), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('🥐', style: TextStyle(fontSize: 34, height: 1)),
                ),
              ],
            ),
          ),
          ReviewPrompt(user: user),
          LoyaltyCardView(uid: user.uid),
          const _NextDayStock(),
          const SizedBox(height: 6),
          const SectionTitle('Nuestro pan'),
        ],
      ),
    );
  }
}

/// Contador en vivo del próximo día de entrega: "Para el lunes 23 quedan 40 panes".
/// Solo aparece si el dueño le puso cupo a ese día.
class _NextDayStock extends StatelessWidget {
  const _NextDayStock();

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return StreamBuilder<List<DeliveryDay>>(
      stream: Repo.instance.deliveryDays(fromDate: today),
      builder: (context, daysSnap) => StreamBuilder<Map<String, DayStock>>(
        stream: Repo.instance.dayStocks(fromDate: today),
        builder: (context, stockSnap) => StreamBuilder<List<Product>>(
          stream: Repo.instance.products(),
          builder: (context, prodSnap) {
            final next = orderableDays(daysSnap.data ?? const [], DateTime.now()).firstOrNull;
            final total = next == null ? null : totalRemaining(next, stockSnap.data?[next.date]);
            final child = next == null || total == null
                ? const SizedBox(width: double.infinity)
                : _card(context, next, stockSnap.data?[next.date], prodSnap.data ?? const [], total);
            return AnimatedSize(
              duration: Motion.of(context, Motion.medio),
              curve: Motion.curva,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
        ),
      ),
    );
  }

  Widget _card(BuildContext context, DeliveryDay day, DayStock? stock, List<Product> products, int total) {
    final groups = [for (final g in stockGroups(products)) if (day.stock.containsKey(g.key)) g];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PanCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para el ${dayLabel(day.date)}',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            StockTotal(left: total),
            if (groups.length > 1) ...[
              const SizedBox(height: 4),
              for (final g in groups)
                StockMeter(
                  label: g.label,
                  detail: g.shared ? g.productNames : null,
                  left: remainingFor(day, stock, g.key) ?? 0,
                  limit: day.stock[g.key]!,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final Cart cart;
  const _ProductCard({required this.product, required this.cart});

  void _openDetail(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailPage(product: product, cart: cart)),
      );

  @override
  Widget build(BuildContext context) {
    final qty = cart.qtyOf(product.id);
    final theme = Theme.of(context);
    final soldOut = !product.available;
    return PanCard(
      padding: const EdgeInsets.all(10),
      onTap: () => _openDetail(context),
      child: Opacity(
        opacity: soldOut ? 0.6 : 1,
        child: Row(
          children: [
            ProductHero(product: product, size: 96),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleMedium),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(product.description,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(money(product.price),
                          style: theme.textTheme.titleLarge!.copyWith(color: Pan.caramelo, fontSize: 19)),
                      const Spacer(),
                      if (soldOut)
                        const _Tag('Agotado')
                      else
                        QtyStepper(
                          qty: qty,
                          onAdd: () => cart.add(product),
                          onRemove: () => cart.remove(product),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFEDE6DC), borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7D7064), fontSize: 12.5)),
      );
}

/// Botón de cantidad: un "+" de miel que se abre en [− 2 +] al agregar.
class QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final double size;
  const QtyStepper({super.key, required this.qty, required this.onAdd, required this.onRemove, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.medio);
    Widget round(IconData icon, VoidCallback onTap, {required bool filled, required String tip}) =>
        Tooltip(
          message: tip,
          child: Pressable(
            onTap: onTap,
            haptic: true,
            scale: 0.88,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: filled ? Pan.gradienteMiel : null,
                color: filled ? null : Pan.papel,
                boxShadow: filled
                    ? const [BoxShadow(color: Color(0x40E8960F), blurRadius: 8, offset: Offset(0, 3))]
                    : null,
              ),
              child: Icon(icon, size: size * 0.55, color: Pan.cacao),
            ),
          ),
        );
    return AnimatedContainer(
      duration: d,
      curve: Motion.curva,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: qty > 0 ? Pan.mielClara : Colors.transparent,
        borderRadius: BorderRadius.circular(size),
      ),
      // El "+" se queda fijo a la derecha mientras se abre: se puede tocar rápido varias veces.
      child: AnimatedSize(
        duration: d,
        curve: Motion.curva,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (qty > 0) ...[
              round(Icons.remove_rounded, onRemove, filled: false, tip: 'Quitar uno'),
              SizedBox(
                width: 30,
                child: AnimatedCount(
                  '$qty',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Pan.tostado),
                ),
              ),
            ],
            round(Icons.add_rounded, onAdd, filled: true, tip: 'Agregar uno'),
          ],
        ),
      ),
    );
  }
}
