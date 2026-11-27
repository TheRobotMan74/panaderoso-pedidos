import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/flavors.dart';
import '../../logic/market.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

/// "¿Qué llevas hoy?": cuántas piezas de cada pan (y de cada sabor) llevas al
/// mercadito, y a qué precio. Sirve para abrirlo y para cambiarlo ya abierto
/// (por ejemplo, si te traen más panes).
class MarketStockPage extends StatefulWidget {
  /// El mercadito abierto que se va a cambiar (null = abrir uno nuevo).
  final Market? editing;

  /// Lo ya vendido por botón (ver logic/market.dart): no se puede bajar de ahí.
  final Map<String, int> sold;
  const MarketStockPage({super.key, this.editing, this.sold = const {}});

  @override
  State<MarketStockPage> createState() => _MarketStockPageState();
}

/// Un renglón: un pan del catálogo (o uno que ya iba en el mercadito).
class _Row {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final List<String> flavors;
  final bool inMenu;
  const _Row(this.id, this.name, this.price, this.imageUrl, this.flavors, {this.inMenu = true});
}

class _MarketStockPageState extends State<MarketStockPage> {
  final _qty = <String, int>{};
  final _flavorQty = <String, Map<String, int>>{};
  final _price = <String, double>{};
  late final _place = TextEditingController(text: widget.editing?.place ?? '');
  List<_Row>? _rows;
  Market? _last;
  StreamSubscription<List<Product>>? _sub;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    for (final it in widget.editing?.items ?? const <MarketItem>[]) {
      _load(it);
    }
    _sub = Repo.instance.products().listen((list) {
      if (!mounted) return;
      setState(() => _rows = _buildRows(list));
    }, onError: (_) => setState(() => _rows = _buildRows(const [])));
    if (!_editing) {
      // El lugar y lo que llevaste la vez pasada, para no escribirlo cada vez.
      Repo.instance.recentMarkets(limit: 1).first.then((l) {
        if (!mounted || l.isEmpty) return;
        setState(() {
          _last = l.first;
          if (_place.text.isEmpty) _place.text = l.first.place;
        });
      }).catchError((_) {});
    }
  }

  void _load(MarketItem it) {
    _price[it.productId] = it.price;
    if (it.hasFlavors) {
      _flavorQty[it.productId] = {...it.flavors!};
    } else {
      _qty[it.productId] = it.qty;
    }
  }

  List<_Row> _buildRows(List<Product> products) {
    final sorted = [...products]..sort((a, b) {
        if (a.available != b.available) return a.available ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final rows = <_Row>[];
    final seen = <String>{};
    for (final p in sorted) {
      seen.add(p.id);
      // Sabores del pan, más los que ya iban en el mercadito (aunque ya no estén).
      final extra = _flavorQty[p.id]?.keys.where((f) => matchFlavor(p.flavors, f) == null) ?? const [];
      rows.add(_Row(p.id, p.name, p.price, p.imageUrl, [...p.flavors, ...extra], inMenu: p.available));
    }
    // Panes que iban en el mercadito pero ya no están en el catálogo.
    for (final it in widget.editing?.items ?? const <MarketItem>[]) {
      if (seen.contains(it.productId)) continue;
      rows.add(_Row(it.productId, it.name, it.price, it.imageUrl, it.flavors?.keys.toList() ?? const [],
          inMenu: false));
    }
    return rows;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _place.dispose();
    super.dispose();
  }

  int _min(String id, String flavor) => widget.sold[unitKey(id, flavor)] ?? 0;

  int _of(String id, String flavor) => flavor.isEmpty ? (_qty[id] ?? 0) : (_flavorQty[id]?[flavor] ?? 0);

  void _set(String id, String flavor, int v) {
    final n = v < _min(id, flavor) ? _min(id, flavor) : v;
    setState(() {
      if (flavor.isEmpty) {
        _qty[id] = n;
      } else {
        (_flavorQty[id] ??= {})[flavor] = n;
      }
    });
  }

  int get _pieces {
    final rows = _rows ?? const <_Row>[];
    var n = 0;
    for (final r in rows) {
      if (r.flavors.isEmpty) {
        n += _qty[r.id] ?? 0;
      } else {
        for (final f in r.flavors) {
          n += _flavorQty[r.id]?[f] ?? 0;
        }
      }
    }
    return n;
  }

  List<MarketItem> _items() => cleanMarketItems([
        for (final r in _rows ?? const <_Row>[])
          MarketItem(
            productId: r.id,
            name: r.name,
            price: _price[r.id] ?? r.price,
            imageUrl: r.imageUrl,
            qty: r.flavors.isEmpty ? (_qty[r.id] ?? 0) : 0,
            flavors: r.flavors.isEmpty ? null : {for (final f in r.flavors) f: _flavorQty[r.id]?[f] ?? 0},
          ),
      ]);

  void _copyLast() {
    final last = _last;
    if (last == null) return;
    setState(() {
      _qty.clear();
      _flavorQty.clear();
      for (final it in last.items) {
        _load(it);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _save() {
    final items = _items();
    if (items.isEmpty) return;
    final repo = Repo.instance;
    if (_editing) {
      // Sin await: con mala señal se guarda en el celular y se sube después.
      unawaited(repo
          .updateMarket(widget.editing!.id, items: items, place: _place.text)
          .catchError((Object e) => debugPrint('Mercadito: $e')));
    } else {
      repo.openNewMarket(date: dateKey(DateTime.now()), place: _place.text, items: items);
    }
    Navigator.pop(context, true);
  }

  Future<void> _editPrice(_Row r) async {
    final c = TextEditingController(text: (_price[r.id] ?? r.price).toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Precio de ${r.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solo para este mercadito. En la app sigue a ${money(r.price)}.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: r'$ '),
              onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('Listo')),
        ],
      ),
    );
    if (v == null || v < 0 || !mounted) return;
    setState(() => _price[r.id] = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final pieces = _pieces;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Cambiar lo que llevo' : '¿Qué llevas hoy?')),
      body: rows == null
          ? const SkeletonList(count: 4, withImage: true)
          : ReadableList(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              builder: (context, pad) => ListView(
                padding: pad,
                children: [
                  Text(
                    _editing
                        ? 'Súmale si te trajeron más panes. No puedes bajar de lo que ya vendiste.'
                        : 'Pon cuántas piezas llevas de cada pan. La caja no deja vender más de eso '
                            'y te va diciendo cuánto queda.',
                    style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _place,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: '¿Dónde? (opcional)',
                      hintText: 'Mercadito Cumbres',
                      prefixIcon: Icon(Icons.shopping_bag_rounded),
                    ),
                  ),
                  if (!_editing && _last != null && _last!.items.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 18),
                        label: Text('Igual que la vez pasada (${_last!.pieces} piezas)'),
                        onPressed: _copyLast,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (final (i, r) in rows.indexed)
                    FadeSlideIn(
                      index: i,
                      child: _StockCard(
                        row: r,
                        price: _price[r.id] ?? r.price,
                        valueOf: (f) => _of(r.id, f),
                        minOf: (f) => _min(r.id, f),
                        onChanged: (f, v) => _set(r.id, f, v),
                        onPrice: () => _editPrice(r),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: MaxWidth(
            maxWidth: Ancho.lectura,
            child: HoneyButton(
              icon: _editing ? Icons.check_rounded : Icons.shopping_bag_rounded,
              label: pieces == 0
                  ? 'Pon cuántas piezas llevas'
                  : '${_editing ? 'Guardar' : 'Abrir mercadito'} · $pieces ${pieces == 1 ? 'pieza' : 'piezas'}',
              onPressed: pieces == 0 ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final _Row row;
  final double price;
  final int Function(String flavor) valueOf;
  final int Function(String flavor) minOf;
  final void Function(String flavor, int value) onChanged;
  final VoidCallback onPrice;
  const _StockCard({
    required this.row,
    required this.price,
    required this.valueOf,
    required this.minOf,
    required this.onChanged,
    required this.onPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flavored = row.flavors.isNotEmpty;
    final total = flavored ? row.flavors.fold(0, (s, f) => s + valueOf(f)) : valueOf('');
    return PanCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProductImage(url: row.imageUrl, name: row.name, size: 54, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, style: theme.textTheme.titleMedium),
                    if (!row.inMenu) Text('No está en el menú de pedidos', style: theme.textTheme.bodySmall),
                    InkWell(
                      onTap: onPrice,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(money(price),
                                style: theme.textTheme.titleMedium!.copyWith(color: Pan.caramelo)),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_note_rounded, size: 15, color: Pan.canela),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (flavored)
                AnimatedCount(
                  '$total',
                  style: theme.textTheme.headlineSmall!.copyWith(color: total > 0 ? Pan.tostado : Pan.canela),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!flavored)
            CountStepper(value: valueOf(''), min: minOf(''), onChanged: (v) => onChanged('', v))
          else
            for (final f in row.flavors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Text(flavorEmoji(f), style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: theme.textTheme.titleSmall)),
                    CountStepper(
                      value: valueOf(f),
                      min: minOf(f),
                      compact: true,
                      onChanged: (v) => onChanged(f, v),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// [−] 24 [+] con atajos de media docena y docena. Tocar el número deja escribirlo.
class CountStepper extends StatelessWidget {
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  /// Sin atajos (para los sabores, que van en renglones más chicos).
  final bool compact;
  const CountStepper(
      {super.key, required this.value, required this.onChanged, this.min = 0, this.compact = false});

  Future<void> _type(BuildContext context) async {
    final c = TextEditingController(text: value == 0 ? '' : '$value');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cuántas piezas?'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0), child: const Text('Listo')),
        ],
      ),
    );
    if (v != null) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    Widget round(IconData icon, VoidCallback? onTap, {required bool filled, required String tip}) => Tooltip(
          message: tip,
          child: Pressable(
            onTap: onTap,
            haptic: true,
            scale: 0.88,
            child: AnimatedOpacity(
              opacity: onTap == null ? 0.35 : 1,
              duration: Motion.of(context, Motion.rapido),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: filled ? Pan.gradienteMiel : null,
                  color: filled ? null : Pan.harina,
                ),
                child: Icon(icon, size: 22, color: Pan.cacao),
              ),
            ),
          ),
        );
    Widget shortcut(int n) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text('+$n'),
            onPressed: () => onChanged(value + n),
          ),
        );
    final stepper = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(Icons.remove_rounded, value > min ? () => onChanged(value - 1) : null,
            filled: false, tip: 'Una menos'),
        InkWell(
          onTap: () => _type(context),
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 58,
            height: 40,
            child: Center(
              child: AnimatedCount(
                '$value',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: value > 0 ? Pan.tostado : Pan.canela,
                ),
              ),
            ),
          ),
        ),
        round(Icons.add_rounded, () => onChanged(value + 1), filled: true, tip: 'Una más'),
      ],
    );
    if (compact) return stepper;
    return Row(
      children: [
        shortcut(6),
        shortcut(12),
        if (min > 0)
          Flexible(
            child: Text('vendidas $min',
                overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ),
        const Spacer(),
        stepper,
      ],
    );
  }
}
