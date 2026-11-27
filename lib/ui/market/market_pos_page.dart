import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/flavors.dart';
import '../../logic/market.dart';
import '../../models.dart';
import '../../services/push.dart';
import '../../services/repo.dart';
import '../customer/customer_home.dart' show QtyStepper;
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

/// La caja del mercadito. Es la pantalla de inicio de la tablet del puesto
/// (cuenta "caja") y el dueño también la puede abrir en su celular.
///
/// El cliente toca su pan (cada toque = una pieza), ve el total y se cobra con
/// un toque. Cada venta se guarda directo en Firestore: si no hay señal, se
/// queda en la tablet y se sube sola cuando vuelve (no hay que esperar a nada).
class MarketPosPage extends StatefulWidget {
  /// true en la tablet del puesto: es su pantalla de inicio (salir = cerrar sesión).
  final bool asCaja;
  const MarketPosPage({super.key, this.asCaja = false});

  @override
  State<MarketPosPage> createState() => _MarketPosPageState();
}

class _MarketPosPageState extends State<MarketPosPage> {
  late final Stream<Market?> _market = Repo.instance.openMarket();
  late final Stream<AppConfig> _config = Repo.instance.config();
  final _ticket = MarketTicket();

  String? _salesOf;
  Stream<({List<MarketSale> sales, bool offline})>? _sales;
  String? _lastMarket;

  @override
  void initState() {
    super.initState();
    // En la tablet la caja usa toda la pantalla (sin marco ni barras de Android).
    WideFrame.useFullWidth(true);
    if (widget.asCaja) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).catchError((_) {});
    }
  }

  @override
  void dispose() {
    WideFrame.useFullWidth(false);
    if (widget.asCaja) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).catchError((_) {});
    }
    _ticket.dispose();
    super.dispose();
  }

  Stream<({List<MarketSale> sales, bool offline})> _salesFor(String marketId) {
    if (_salesOf != marketId || _sales == null) {
      _salesOf = marketId;
      _sales = Repo.instance.marketSales(marketId);
    }
    return _sales!;
  }

  String _sell(Market m, List<OrderItem> items, double total, MarketPay pay, double? received) {
    final repo = Repo.instance;
    final id = repo.newMarketSaleId();
    // Sin await: sin señal, la venta se queda en la tablet y se sube sola después.
    unawaited(repo
        .saveMarketSale(id: id, market: m, items: items, total: total, pay: pay, received: received)
        .catchError((Object e) => _toast('Una venta no se pudo guardar: $e')));
    return id;
  }

  void _undo(String saleId) {
    unawaited(Repo.instance.setMarketSaleCancelled(saleId, true).catchError((Object e) {
      _toast('No se pudo cancelar la venta: $e');
    }));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exit() async {
    if (!widget.asCaja) {
      Navigator.of(context).maybePop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión de la tablet?'),
        content: const Text('Para volver a vender, hay que entrar otra vez con la cuenta del mercadito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cerrar')),
        ],
      ),
    );
    if (ok == true) await signOutAndForgetPush();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Market?>(
      stream: _market,
      builder: (context, snap) {
        final Widget page;
        if (snap.hasError) {
          page = _NoMarket(
            key: const ValueKey('error'),
            asCaja: widget.asCaja,
            onExit: _exit,
            title: 'Esta cuenta no puede abrir la caja',
            message: 'Pídele al dueño que la ponga como cuenta de la tablet (Mercadito → Tablet del puesto).',
          );
        } else if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          page = const Scaffold(
            key: ValueKey('cargando'),
            backgroundColor: Pan.crema,
            body: Center(child: FloatingBear(size: 112)),
          );
        } else if (snap.data == null) {
          page = _NoMarket(key: const ValueKey('cerrado'), asCaja: widget.asCaja, onExit: _exit);
        } else {
          final m = snap.data!;
          // Mercadito nuevo: la cuenta empieza vacía.
          if (_lastMarket != null && _lastMarket != m.id) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _ticket.clear());
          }
          _lastMarket = m.id;
          page = StreamBuilder<({List<MarketSale> sales, bool offline})>(
            key: ValueKey(m.id),
            stream: _salesFor(m.id),
            builder: (context, sales) => StreamBuilder<AppConfig>(
              stream: _config,
              builder: (context, cfg) => MarketPosView(
                market: m,
                sales: sales.data?.sales ?? const [],
                offline: sales.data?.offline ?? false,
                config: cfg.data,
                ticket: _ticket,
                asCaja: widget.asCaja,
                onSell: (items, total, pay, received) => _sell(m, items, total, pay, received),
                onUndo: _undo,
                onExit: _exit,
              ),
            ),
          );
        }
        return FadeThroughSwitcher(child: page);
      },
    );
  }
}

typedef SellFn = String Function(List<OrderItem> items, double total, MarketPay pay, double? received);

/// La pantalla de venta, sin Firebase (se puede probar sola).
class MarketPosView extends StatefulWidget {
  final Market market;
  final List<MarketSale> sales;
  final bool offline;
  final AppConfig? config;
  final MarketTicket ticket;
  final bool asCaja;

  /// Guarda la venta y regresa su id (para poder deshacerla).
  final SellFn onSell;
  final void Function(String saleId) onUndo;
  final VoidCallback onExit;

  const MarketPosView({
    super.key,
    required this.market,
    required this.sales,
    required this.ticket,
    required this.onSell,
    required this.onUndo,
    required this.onExit,
    this.offline = false,
    this.config,
    this.asCaja = false,
  });

  /// Desde este ancho la cuenta va a la derecha (tablet acostada).
  static const wideFrom = 900.0;

  @override
  State<MarketPosView> createState() => _MarketPosViewState();
}

class _MarketPosViewState extends State<MarketPosView> {
  ({String id, double total, double? change})? _thanks;
  Timer? _thanksTimer;
  bool _fitting = false;

  @override
  void dispose() {
    _thanksTimer?.cancel();
    super.dispose();
  }

  List<MarketUnit> get _units => marketUnits(widget.market);

  Future<void> _charge(List<MarketUnit> units) async {
    final t = widget.ticket;
    if (t.isEmpty) return;
    final total = t.total(units);
    final r = await showMarketPayDialog(context, total: total, pieces: t.pieces, config: widget.config);
    if (r == null || !mounted) return;
    final items = t.toItems(units);
    if (items.isEmpty) return;
    final id = widget.onSell(items, total, r.pay, r.received);
    t.clear();
    HapticFeedback.mediumImpact();
    setState(() => _thanks = (id: id, total: total, change: r.received == null ? null : r.received! - total));
    _thanksTimer?.cancel();
    _thanksTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _thanks = null);
    });
  }

  void _undoLast() {
    final th = _thanks;
    if (th == null) return;
    widget.onUndo(th.id);
    _thanksTimer?.cancel();
    setState(() => _thanks = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Venta cancelada. Los panes regresan a la lista.')));
  }

  void _openSales() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MarketSalesSheet(
          sales: widget.sales,
          canRestore: false,
          onCancel: widget.onUndo,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final units = _units;
    final remaining = remainingByUnit(units, widget.sales);
    // Si ya no alcanza lo que hay en la cuenta (alguien más vendió, o el dueño
    // cambió lo que lleva), se ajusta después de dibujar.
    final over = widget.ticket.keys.any((k) => widget.ticket.qtyOf(k) > (remaining[k] ?? 0));
    if (over && !_fitting) {
      _fitting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitting = false;
        if (mounted) widget.ticket.fitTo(remaining);
      });
    }
    final pending = widget.sales.where((s) => s.pending).length;

    return Scaffold(
      backgroundColor: Pan.crema,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= MarketPosView.wideFrom;
          final header = _PosHeader(
            market: widget.market,
            offline: widget.offline,
            pending: pending,
            asCaja: widget.asCaja,
            onSales: _openSales,
            onExit: widget.onExit,
          );
          final grid = ListenableBuilder(
            listenable: widget.ticket,
            builder: (context, _) => _UnitGrid(
              units: units,
              remaining: remaining,
              ticket: widget.ticket,
              maxTile: wide ? 236 : (c.maxWidth >= 600 ? 250 : 210),
            ),
          );
          final Widget body;
          if (wide) {
            body = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SafeArea(
                    right: false,
                    child: Column(children: [header, Expanded(child: grid)]),
                  ),
                ),
                SizedBox(
                  width: c.maxWidth >= 1200 ? 400 : 360,
                  child: _TicketPanel(units: units, ticket: widget.ticket, onCharge: () => _charge(units)),
                ),
              ],
            );
          } else {
            body = SafeArea(
              bottom: false,
              child: Column(
                children: [
                  header,
                  Expanded(child: grid),
                  _TicketBar(units: units, ticket: widget.ticket, onCharge: () => _charge(units)),
                ],
              ),
            );
          }
          return Stack(
            children: [
              Positioned.fill(child: body),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _thanks == null,
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.medio),
                    switchInCurve: Motion.rebote,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
                    ),
                    child: _thanks == null
                        ? const SizedBox.shrink()
                        : _ThanksOverlay(
                            key: ValueKey(_thanks!.id),
                            total: _thanks!.total,
                            change: _thanks!.change,
                            onClose: () => setState(() => _thanks = null),
                            onUndo: _undoLast,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arriba: el oso, el lugar y si hay señal
// ---------------------------------------------------------------------------

class _PosHeader extends StatelessWidget {
  final Market market;
  final bool offline;
  final int pending;
  final bool asCaja;
  final VoidCallback onSales;
  final VoidCallback onExit;
  const _PosHeader({
    required this.market,
    required this.offline,
    required this.pending,
    required this.asCaja,
    required this.onSales,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 28, phone ? 10 : 18, phone ? 8 : 16, 4),
      child: Row(
        children: [
          BearLogo(size: phone ? 42 : 56),
          SizedBox(width: phone ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¿Qué se te antoja?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (phone ? theme.textTheme.headlineSmall : theme.textTheme.headlineMedium)!
                      .copyWith(height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  'Toca tu pan para agregarlo · ${market.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SyncPill(offline: offline, pending: pending, compact: phone),
          PopupMenuButton<String>(
            tooltip: 'Más',
            icon: const Icon(Icons.more_vert_rounded, color: Pan.canela),
            onSelected: (v) => v == 'ventas' ? onSales() : onExit(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'ventas',
                child: ListTile(leading: Icon(Icons.receipt_long_rounded), title: Text('Ventas de hoy')),
              ),
              PopupMenuItem(
                value: 'salir',
                child: ListTile(
                  leading: Icon(asCaja ? Icons.logout_rounded : Icons.arrow_back_rounded),
                  title: Text(asCaja ? 'Cerrar sesión' : 'Volver al panel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "En línea" / "Sin señal" / "3 por subir": las ventas nunca se pierden,
/// pero así sabes si ya llegaron.
class SyncPill extends StatelessWidget {
  final bool offline;
  final int pending;
  final bool compact;
  const SyncPill({super.key, required this.offline, required this.pending, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text, Color bg, Color fg, String tip) = pending > 0
        ? (
            const Icon(Icons.upload_rounded, size: 17, color: Pan.tostado),
            compact ? '$pending' : '$pending por subir',
            Pan.mielClara,
            Pan.tostado,
            'Ventas guardadas en este aparato que se suben solas en cuanto haya señal.',
          )
        : offline
            ? (
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Pan.canela, shape: BoxShape.circle),
                ),
                compact ? '' : 'Sin señal',
                Pan.harina,
                Pan.tostado,
                'Sin internet: puedes seguir vendiendo, todo se guarda y se sube después.',
              )
            : (
                const PulseDot(size: 7),
                compact ? '' : 'En línea',
                Pan.salviaClara,
                const Color(0xFF2E4B24),
                'Conectado: las ventas ya están guardadas.',
              );
    return Tooltip(
      message: tip,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medio),
        padding: EdgeInsets.fromLTRB(text.isEmpty ? 6 : 8, 4, text.isEmpty ? 6 : 12, 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 22, child: Center(child: icon)),
            if (text.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Los panes
// ---------------------------------------------------------------------------

class _UnitGrid extends StatelessWidget {
  final List<MarketUnit> units;
  final Map<String, int> remaining;
  final MarketTicket ticket;
  final double maxTile;
  const _UnitGrid(
      {required this.units, required this.remaining, required this.ticket, required this.maxTile});

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    if (units.isEmpty) {
      return const EmptyState(
        title: 'No hay panes en el mercadito',
        message: 'Agrégalos en tu panel: Mercadito → Cambiar panes.',
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(phone ? 12 : 24, 12, phone ? 12 : 24, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxTile,
        mainAxisSpacing: phone ? 12 : 18,
        crossAxisSpacing: phone ? 12 : 18,
        childAspectRatio: 0.8,
      ),
      itemCount: units.length,
      itemBuilder: (context, i) {
        final u = units[i];
        final inTicket = ticket.qtyOf(u.key);
        final left = (remaining[u.key] ?? 0) - inTicket;
        return FadeSlideIn(
          index: i,
          child: UnitTile(
            unit: u,
            inTicket: inTicket,
            left: left,
            onAdd: left > 0 ? () => ticket.add(u.key, left: remaining[u.key] ?? 0) : null,
            onRemove: inTicket > 0 ? () => ticket.remove(u.key) : null,
          ),
        );
      },
    );
  }
}

/// Un pan (o un sabor) en la caja. Tocarlo = una pieza más.
class UnitTile extends StatelessWidget {
  final MarketUnit unit;

  /// Cuántas lleva en la cuenta.
  final int inTicket;

  /// Cuántas quedan sin contar las de la cuenta.
  final int left;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  const UnitTile({
    super.key,
    required this.unit,
    required this.inTicket,
    required this.left,
    this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soldOut = left <= 0 && inTicket == 0;
    final selected = inTicket > 0;
    final (String leftText, Color leftColor) = left <= 0
        ? (inTicket > 0 ? 'Ya no hay más' : 'Agotado', Pan.terracota)
        : left <= 3
            ? (left == 1 ? '¡Queda 1!' : '¡Últimas $left!', Pan.terracota)
            : ('Quedan $left', Pan.canela);
    final card = AnimatedContainer(
      duration: Motion.of(context, Motion.rapido),
      curve: Motion.curva,
      decoration: BoxDecoration(
        color: Pan.papel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: selected ? Pan.miel : const Color(0x00FFFFFF), width: 3),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x40E8960F), blurRadius: 18, offset: Offset(0, 8))]
            : Pan.sombra,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(19), child: UnitArt(unit: unit)),
                  if (unit.flavor.isNotEmpty)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(7, 3, 10, 3),
                        decoration: BoxDecoration(
                          color: Pan.papel.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(flavorEmoji(unit.flavor), style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 4),
                            Text(unit.flavor,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 13, color: Pan.tostado)),
                          ],
                        ),
                      ),
                    ),
                  if (selected) Positioned(top: 6, right: 6, child: _QtyBadge(qty: inTicket)),
                  if (selected && onRemove != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Tooltip(
                        message: 'Quitar uno',
                        child: Pressable(
                          onTap: onRemove,
                          haptic: true,
                          scale: 0.85,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Pan.papel,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Color(0x267A4A12), blurRadius: 8, offset: Offset(0, 3))
                              ],
                            ),
                            child: const Icon(Icons.remove_rounded, color: Pan.cacao),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Siempre el alto de dos renglones, para que los precios queden parejos.
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(16.5) * 1.15 * 2 + 1,
                  child: Text(
                    unit.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium!.copyWith(fontSize: 16.5, height: 1.15),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      money(unit.price),
                      style: theme.textTheme.titleLarge!
                          .copyWith(color: Pan.caramelo, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedCount(
                        leftText,
                        alignment: Alignment.centerRight,
                        maxLines: 1,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: leftColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${unit.label}, ${money(unit.price)}. $leftText',
      child: Pressable(
        onTap: onAdd == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onAdd!();
              },
        scale: 0.95,
        child: soldOut
            ? Stack(
                fit: StackFit.passthrough,
                children: [
                  Opacity(opacity: 0.45, child: card),
                  Positioned.fill(
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Pan.terracota,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Agotado',
                              style:
                                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : card,
      ),
    );
  }
}

/// La foto del pan, o su dibujito con los colores del sabor.
class UnitArt extends StatelessWidget {
  final MarketUnit unit;
  const UnitArt({super.key, required this.unit});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final side = c.biggest.longestSide.isFinite ? c.biggest.longestSide : 160.0;
          final url = unit.item.imageUrl;
          if (url != null && url.isNotEmpty) {
            return FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: ProductImage(url: url, name: unit.item.name, size: side),
            );
          }
          final (emoji, colors) = productArt(unit.item.name);
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 1.1,
                colors: unit.flavor.isEmpty ? colors : flavorColors(unit.flavor, colors),
              ),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: TextStyle(fontSize: c.biggest.shortestSide * 0.5, height: 1)),
          );
        },
      );
}

/// Colores del fondo según el sabor (chocolate café, caramelo miel, glaseado rosa…).
List<Color> flavorColors(String flavor, List<Color> fallback) {
  final n = flavor.toLowerCase();
  if (n.contains('chocol') ||
      n.contains('cacao') ||
      n.contains('nutella') ||
      n.contains('café') ||
      n.contains('cafe')) {
    return const [Color(0xFFF6E2D0), Color(0xFFD9A77F)];
  }
  if (n.contains('caramel') || n.contains('cajeta') || n.contains('miel') || n.contains('dulce')) {
    return const [Color(0xFFFFF1CF), Color(0xFFF9D27A)];
  }
  if (n.contains('glase') || n.contains('fresa') || n.contains('rosa')) {
    return const [Color(0xFFFFE6E1), Color(0xFFF5B3A6)];
  }
  if (n.contains('vainilla') || n.contains('crema') || n.contains('coco')) {
    return const [Color(0xFFFFF8E7), Color(0xFFF3DDA8)];
  }
  if (n.contains('limón') || n.contains('limon')) return const [Color(0xFFF6F7D8), Color(0xFFE2E58F)];
  return fallback;
}

/// El numerito de miel de cuántas lleva; brinca cada que cambia.
class _QtyBadge extends StatelessWidget {
  final int qty;
  const _QtyBadge({required this.qty});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(qty),
        tween: Tween(begin: Motion.off(context) ? 1 : 1.35, end: 1),
        duration: Motion.of(context, const Duration(milliseconds: 380)),
        curve: Motion.rebote,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 42),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: Pan.gradienteMiel,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x40E8960F), blurRadius: 10, offset: Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: Text('$qty',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Pan.cacao)),
        ),
      );
}

// ---------------------------------------------------------------------------
// La cuenta
// ---------------------------------------------------------------------------

/// A la derecha en la tablet acostada: lo que lleva, el total y "Cobrar".
class _TicketPanel extends StatelessWidget {
  final List<MarketUnit> units;
  final MarketTicket ticket;
  final VoidCallback onCharge;
  const _TicketPanel({required this.units, required this.ticket, required this.onCharge});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Pan.papel,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Color(0x1F7A4A12), blurRadius: 30, offset: Offset(-4, 0))],
      ),
      child: SafeArea(
        left: false,
        child: ListenableBuilder(
          listenable: ticket,
          builder: (context, _) => _TicketBody(units: units, ticket: ticket, onCharge: onCharge),
        ),
      ),
    );
  }
}

class _TicketBody extends StatelessWidget {
  final List<MarketUnit> units;
  final MarketTicket ticket;
  final VoidCallback onCharge;

  /// En la hoja de abajo (celular): sin el área que se estira.
  final bool inSheet;
  const _TicketBody(
      {required this.units, required this.ticket, required this.onCharge, this.inSheet = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = ticket.lines(units);
    final total = ticket.total(units);
    final pieces = ticket.pieces;
    final list = lines.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Opacity(opacity: 0.85, child: FloatingBear(size: 84)),
                  const SizedBox(height: 14),
                  Text('Toca un pan para empezar', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Cada toque es una pieza.', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          )
        : ListView.separated(
            shrinkWrap: inSheet,
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: lines.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
            itemBuilder: (context, i) => _TicketLine(
              unit: lines[i].$1,
              qty: lines[i].$2,
              onAdd: () => ticket.add(lines[i].$1.key, left: 1 << 30),
              onRemove: () => ticket.remove(lines[i].$1.key),
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        mainAxisSize: inSheet ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Tu cuenta', style: theme.textTheme.headlineSmall)),
              AnimatedOpacity(
                opacity: lines.isEmpty ? 0 : 1,
                duration: Motion.of(context, Motion.rapido),
                child: TextButton.icon(
                  onPressed: lines.isEmpty ? null : ticket.clear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Borrar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (inSheet) Flexible(child: list) else Expanded(child: list),
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: theme.textTheme.titleMedium!.copyWith(color: Pan.canela)),
                    AnimatedCount(
                      pieces == 0 ? 'Sin panes' : '$pieces ${pieces == 1 ? 'pieza' : 'piezas'}',
                      alignment: Alignment.centerLeft,
                      style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              AnimatedCount(
                money(total),
                alignment: Alignment.centerRight,
                style: theme.textTheme.displaySmall!.copyWith(color: Pan.caramelo, fontSize: 44),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HoneyButton(
            label: lines.isEmpty ? 'Cobrar' : 'Cobrar ${money(total)}',
            icon: Icons.payments_rounded,
            onPressed: lines.isEmpty ? null : onCharge,
          ),
        ],
      ),
    );
  }
}

class _TicketLine extends StatelessWidget {
  final MarketUnit unit;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _TicketLine({required this.unit, required this.qty, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = unit.flavor.isEmpty ? productArt(unit.item.name).$1 : flavorEmoji(unit.flavor);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Pan.crema, borderRadius: BorderRadius.circular(14)),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(unit.item.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                Text(
                  [if (unit.flavor.isNotEmpty) unit.flavor, money(unit.price * qty)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          QtyStepper(qty: qty, size: 36, onAdd: onAdd, onRemove: onRemove),
        ],
      ),
    );
  }
}

/// Abajo en el celular o la tablet parada: total y "Cobrar". Se toca para ver la cuenta.
class _TicketBar extends StatelessWidget {
  final List<MarketUnit> units;
  final MarketTicket ticket;
  final VoidCallback onCharge;
  const _TicketBar({required this.units, required this.ticket, required this.onCharge});

  void _open(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListenableBuilder(
              listenable: ticket,
              builder: (context, _) => _TicketBody(
                units: units,
                ticket: ticket,
                inSheet: true,
                onCharge: () {
                  Navigator.pop(ctx);
                  onCharge();
                },
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Pan.papel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x1F7A4A12), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
          child: ListenableBuilder(
            listenable: ticket,
            builder: (context, _) {
              final pieces = ticket.pieces;
              final total = ticket.total(units);
              return Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: pieces == 0 ? null : () => _open(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: AnimatedCount(
                                  pieces == 0
                                      ? 'Toca un pan para empezar'
                                      : 'Tu cuenta · $pieces ${pieces == 1 ? 'pieza' : 'piezas'}',
                                  alignment: Alignment.centerLeft,
                                  maxLines: 1,
                                  style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (pieces > 0)
                                const RotatedBox(
                                  quarterTurns: 2,
                                  child: Icon(Icons.expand_more_rounded, size: 18, color: Pan.canela),
                                ),
                            ],
                          ),
                          AnimatedCount(
                            money(total),
                            alignment: Alignment.centerLeft,
                            style: theme.textTheme.headlineMedium!.copyWith(color: Pan.caramelo),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: HoneyButton(
                      label: 'Cobrar',
                      icon: Icons.payments_rounded,
                      onPressed: pieces == 0 ? null : onCharge,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cobrar
// ---------------------------------------------------------------------------

/// Cómo pagó y con cuánto (efectivo). Null = se regresó sin cobrar.
Future<({MarketPay pay, double? received})?> showMarketPayDialog(
  BuildContext context, {
  required double total,
  required int pieces,
  AppConfig? config,
}) =>
    showDialog<({MarketPay pay, double? received})>(
      context: context,
      builder: (_) => _PayDialog(total: total, pieces: pieces, config: config),
    );

class _PayDialog extends StatefulWidget {
  final double total;
  final int pieces;
  final AppConfig? config;
  const _PayDialog({required this.total, required this.pieces, this.config});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  MarketPay _pay = MarketPay.efectivo;

  /// Con cuánto pagó (null = exacto).
  int? _received;

  double? get _change => _received == null ? null : _received! - widget.total;

  Future<void> _other() async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Con cuánto paga?'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: const InputDecoration(prefixText: r'$ '),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('Listo')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _received = v < widget.total ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = cashOptions(widget.total);
    final cfg = widget.config;
    final change = _change;
    final short = MediaQuery.sizeOf(context).height < 640;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, short ? 18 : 26, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Total · ${widget.pieces} ${widget.pieces == 1 ? 'pieza' : 'piezas'}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium!.copyWith(color: Pan.canela),
              ),
              Text(
                money(widget.total),
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium!.copyWith(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w700,
                  color: Pan.caramelo,
                ),
              ),
              SizedBox(height: short ? 10 : 18),
              Row(
                children: [
                  Expanded(
                    child: _PayChoice(
                      emoji: '💵',
                      label: 'Efectivo',
                      selected: _pay == MarketPay.efectivo,
                      onTap: () => setState(() => _pay = MarketPay.efectivo),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PayChoice(
                      emoji: '📲',
                      label: 'Transferencia',
                      selected: _pay == MarketPay.transferencia,
                      onTap: () => setState(() => _pay = MarketPay.transferencia),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedSize(
                duration: Motion.of(context, Motion.medio),
                curve: Motion.curva,
                alignment: Alignment.topCenter,
                child: _pay == MarketPay.efectivo
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('¿Con cuánto paga?', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final o in options)
                                _CashChip(
                                  label: o == options.first ? 'Exacto' : money(o),
                                  selected: o == options.first ? _received == null : _received == o,
                                  onTap: () => setState(() => _received = o == options.first ? null : o),
                                ),
                              _CashChip(label: 'Otro', selected: false, onTap: _other),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: Motion.of(context, Motion.rapido),
                            child: change == null || change <= 0
                                ? const SizedBox(key: ValueKey('sin-cambio'), height: 0)
                                : Container(
                                    key: ValueKey(change),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Pan.salviaClara,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.payments_rounded, color: Pan.salvia),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text('Su cambio',
                                              style: theme.textTheme.titleMedium!
                                                  .copyWith(color: const Color(0xFF2E4B24))),
                                        ),
                                        Text(
                                          money(change),
                                          style: theme.textTheme.headlineMedium!
                                              .copyWith(color: const Color(0xFF2E4B24)),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      )
                    : _BankBox(config: cfg),
              ),
              const SizedBox(height: 18),
              HoneyButton(
                label: _pay == MarketPay.efectivo ? 'Listo, cobrado' : 'Ya transfirió',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.pop(
                  context,
                  (pay: _pay, received: _pay == MarketPay.efectivo ? _received?.toDouble() : null),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver a la cuenta')),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayChoice extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PayChoice({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.rapido),
          height: 64,
          decoration: BoxDecoration(
            color: selected ? Pan.mielClara : Pan.crema,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: selected ? Pan.miel : const Color(0xFFE6D6BC), width: selected ? 2.5 : 1.4),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: selected ? Pan.tostado : Pan.cacao,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CashChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CashChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        scale: 0.93,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.rapido),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Pan.caramelo : Pan.papel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? Pan.caramelo : const Color(0xFFDCC7A6), width: 1.4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: selected ? Colors.white : Pan.tostado,
            ),
          ),
        ),
      );
}

/// Datos para transferir (los de Ajustes), grandes para que el cliente los copie.
class _BankBox extends StatelessWidget {
  final AppConfig? config;
  const _BankBox({this.config});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = config;
    if (c == null || c.clabe.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Pan.harina, borderRadius: BorderRadius.circular(18)),
        child: Text('Cuando veas la transferencia en tu banco, toca "Ya transfirió".',
            style: theme.textTheme.bodyMedium),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(color: Pan.harina, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transfiere a', style: theme.textTheme.bodySmall),
          if (c.bankName.isNotEmpty) Text(c.bankName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(
            _groups(c.clabe.trim()),
            style: theme.textTheme.headlineSmall!.copyWith(letterSpacing: 1.2, color: Pan.tostado),
          ),
          if (c.accountHolder.isNotEmpty)
            Text('A nombre de ${c.accountHolder}', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  /// La CLABE de 4 en 4 para leerla fácil: "0121 8000 1234 5678 90".
  static String _groups(String s) {
    final digits = s.replaceAll(' ', '');
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(digits[i]);
    }
    return b.toString();
  }
}

/// "¡Gracias!" después de cobrar, con el cambio grande. Se va solo.
class _ThanksOverlay extends StatelessWidget {
  final double total;
  final double? change;
  final VoidCallback onClose;
  final VoidCallback onUndo;
  const _ThanksOverlay(
      {super.key, required this.total, required this.change, required this.onClose, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ch = change;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: Pan.crema.withValues(alpha: 0.96),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FloatingBear(size: 132),
                const SizedBox(height: 18),
                Text('¡Gracias!',
                    style: theme.textTheme.displayMedium!
                        .copyWith(fontFamily: 'Fraunces', fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Que disfrutes tu pan 🥐',
                    style: theme.textTheme.titleLarge!.copyWith(color: Pan.canela)),
                const SizedBox(height: 18),
                if (ch != null && ch > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                    decoration:
                        BoxDecoration(color: Pan.salviaClara, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      children: [
                        Text('Su cambio',
                            style: theme.textTheme.titleMedium!.copyWith(color: const Color(0xFF2E4B24))),
                        Text(money(ch),
                            style: theme.textTheme.displaySmall!.copyWith(color: const Color(0xFF2E4B24))),
                      ],
                    ),
                  )
                else
                  Text('Cobrado ${money(total)} ✓', style: theme.textTheme.titleMedium),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Deshacer venta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sin mercadito abierto
// ---------------------------------------------------------------------------

class _NoMarket extends StatelessWidget {
  final bool asCaja;
  final VoidCallback onExit;
  final String? title;
  final String? message;
  const _NoMarket({super.key, required this.asCaja, required this.onExit, this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Pan.crema,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: FadeSlideIn(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FloatingBear(size: 140),
                    const SizedBox(height: 22),
                    Text(
                      title ?? 'El mercadito está cerrado',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message ??
                          (asCaja
                              ? 'Cuando lo abras en tu celular (Panel → Mercadito → Abrir mercadito), '
                                  'aquí aparece la caja solita.'
                              : 'Ábrelo desde Mercadito en tu panel.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge!.copyWith(color: Pan.canela),
                    ),
                    const SizedBox(height: 26),
                    TextButton.icon(
                      onPressed: onExit,
                      icon: Icon(asCaja ? Icons.logout_rounded : Icons.arrow_back_rounded),
                      label: Text(asCaja ? 'Cerrar sesión' : 'Volver'),
                    ),
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

// ---------------------------------------------------------------------------
// Ventas de hoy (también lo usa el panel del dueño)
// ---------------------------------------------------------------------------

/// Lista de ventas con su hora; se puede cancelar una (y el dueño, volver a ponerla).
class MarketSalesSheet extends StatelessWidget {
  final List<MarketSale> sales;
  final void Function(String id) onCancel;

  /// Solo el dueño: volver a poner una venta cancelada.
  final bool canRestore;
  final void Function(String id)? onRestore;
  const MarketSalesSheet({
    super.key,
    required this.sales,
    required this.onCancel,
    this.canRestore = false,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = MarketSummary.of(sales);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ventas', style: theme.textTheme.headlineSmall),
                  Text(
                    '${s.sales} ${s.sales == 1 ? 'venta' : 'ventas'} · ${s.pieces} '
                    '${s.pieces == 1 ? 'pieza' : 'piezas'} · ${money(s.total)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (sales.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('Todavía no hay ventas.', textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => MarketSaleTile(
                    sale: sales[i],
                    onCancel: () => _confirmCancel(context, sales[i]),
                    onRestore: canRestore && onRestore != null ? () => onRestore!(sales[i].id) : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, MarketSale s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta venta?'),
        content: Text('${itemsLabel(s.items)} · ${money(s.total)}\n\nSus panes vuelven a estar disponibles.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok == true) onCancel(s.id);
  }
}

/// Una venta: hora, panes, total y cómo pagó.
class MarketSaleTile extends StatelessWidget {
  final MarketSale sale;
  final VoidCallback? onCancel;
  final VoidCallback? onRestore;
  const MarketSaleTile({super.key, required this.sale, this.onCancel, this.onRestore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = sale;
    final time = s.at == null ? '' : DateFormat('h:mm a', 'es_MX').format(s.at!);
    final strike = s.cancelled ? TextDecoration.lineThrough : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.cancelled ? Pan.harina : (s.pay == MarketPay.efectivo ? Pan.salviaClara : Pan.cieloClaro),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(s.pay == MarketPay.efectivo ? '💵' : '📲', style: const TextStyle(fontSize: 20)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              money(s.total),
              style: theme.textTheme.titleMedium!.copyWith(decoration: strike),
            ),
          ),
          if (s.pending)
            const Tooltip(
              message: 'Guardada en la tablet; se sube cuando haya señal',
              child: Icon(Icons.upload_rounded, size: 18, color: Pan.caramelo),
            ),
          const SizedBox(width: 6),
          Text(time, style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Text(
        '${itemsLabel(s.items)}${s.cancelled ? ' · Cancelada' : ''}'
        '${!s.cancelled && s.change != null && s.change! > 0 ? ' · pagó con ${money(s.received!)}' : ''}',
        style: theme.textTheme.bodySmall!.copyWith(decoration: strike),
      ),
      trailing: s.cancelled
          ? (onRestore == null
              ? null
              : IconButton(
                  tooltip: 'Volver a ponerla', onPressed: onRestore, icon: const Icon(Icons.history_rounded)))
          : (onCancel == null
              ? null
              : IconButton(
                  tooltip: 'Cancelar venta',
                  onPressed: onCancel,
                  icon: const Icon(Icons.block_rounded, color: Pan.terracota),
                )),
    );
  }
}
