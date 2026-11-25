import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../logic/archive.dart';
import '../../logic/demand.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../fold_memory.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

/// Cuántos pedidos y piezas hay por día y por horario, para planear las charolas.
/// Cada día se pliega tocando su encabezado (se recuerda en el celular); los
/// días sin pedidos empiezan plegados. Los días ya repartidos no salen aquí:
/// van al Historial, igual que en Pedidos (ver logic/archive.dart).
class DemandPage extends StatelessWidget {
  const DemandPage({super.key});

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return StreamBuilder<List<DeliveryDay>>(
      stream: Repo.instance.deliveryDays(fromDate: today),
      builder: (context, daysSnap) => StreamBuilder<List<BakeryOrder>>(
        stream: Repo.instance.ordersFrom(today),
        builder: (context, ordersSnap) {
          if (!daysSnap.hasData || !ordersSnap.hasData) {
            return const SkeletonList(count: 2);
          }
          final days = daysSnap.data!;
          final orders = ordersSnap.data!;
          // Días publicados y también días con pedidos (por si se cerró uno con pedidos).
          final finished = finishedDates(
            orders,
            today: today,
            days: {for (final d in days) d.date: d},
          );
          final byId = {for (final d in days) d.date: d};
          final dates = {...days.map((d) => d.date), ...orders.map((o) => o.deliveryDate)}
              .where((d) => !finished.contains(d))
              .toList()
            ..sort((a, b) => compareDayIds(a, b, byId));
          if (dates.isEmpty) {
            return const EmptyState(
              title: 'Sin días próximos',
              message: 'Abre días de entrega en la pestaña "Días" para empezar a recibir pedidos.',
            );
          }
          return ValueListenableBuilder<int>(
            valueListenable: FoldMemory.changes,
            builder: (context, _, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final (i, date) in dates.indexed)
                FadeSlideIn(
                  index: i,
                  child: _DayCard(
                    title: dayTitle(date, days),
                    demand: demandForDay(
                      date,
                      orders,
                      slotOrder: days.where((d) => d.date == date).firstOrNull?.slots ?? const [],
                      slotMinutes: days.where((d) => d.date == date).firstOrNull?.slotMinutes ?? 60,
                    ),
                  ),
                ),
            ],
          ),
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DayDemand demand;
  final String title;
  const _DayCard({required this.demand, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = demand.totalByProduct.keys.toList()..sort();
    final maxQty = products.isEmpty
        ? 1
        : demand.totalByProduct.values.reduce((a, b) => a > b ? a : b);
    final key = 'demanda|${demand.date}';
    final open = FoldMemory.isOpen(key, byDefault: demand.orders > 0);
    final summary = demand.orders == 0
        ? 'Sin pedidos todavía'
        : '${demand.orders} ${demand.orders == 1 ? 'pedido' : 'pedidos'} · '
            '${demand.pieces} ${demand.pieces == 1 ? 'pieza' : 'piezas'}';
    return PanCard(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoldHeader(
            open: open,
            onTap: () => FoldMemory.set(key, !open),
            semanticsLabel: open ? 'Plegar día' : 'Abrir día',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                // Plegada: el resumen en un renglón.
                AnimatedSize(
                  duration: Motion.of(context, Motion.rapido),
                  curve: Motion.curva,
                  alignment: Alignment.topLeft,
                  child: open
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(summary,
                              style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
                        ),
                ),
              ],
            ),
          ),
          FoldBody(
            open: open,
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Stat(value: demand.orders, label: 'pedidos', emoji: '🧾')),
              const SizedBox(width: 10),
              Expanded(child: _Stat(value: demand.pieces, label: 'piezas', emoji: '🥐')),
            ],
          ),
          const SizedBox(height: 14),
          if (products.isEmpty)
            Text('Sin pedidos todavía.', style: theme.textTheme.bodySmall)
          else ...[
            Text('Para hornear', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final p in products)
              _Bar(
                label: p,
                qty: demand.totalByProduct[p]!,
                fraction: demand.totalByProduct[p]! / maxQty,
              ),
            const SizedBox(height: 10),
            Text('Por horario', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SlotDemandTable(demand: demand, products: products),
          ],
        ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final String emoji;
  const _Stat({required this.value, required this.label, required this.emoji});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(color: Pan.crema, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: Motion.of(context, const Duration(milliseconds: 800)),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}',
                  style: const TextStyle(
                      fontFamily: 'Fraunces', fontWeight: FontWeight.w700, fontSize: 26, color: Pan.cacao)),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Barra de miel que crece hasta la cantidad a hornear.
class _Bar extends StatelessWidget {
  final String label;
  final int qty;
  final double fraction;
  const _Bar({required this.label, required this.qty, required this.fraction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(productArt(label).$1, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                      Text('$qty',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Pan.tostado)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF3E7D2), borderRadius: BorderRadius.circular(6)),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fraction),
                          duration: Motion.of(context, const Duration(milliseconds: 900)),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Container(
                            width: c.maxWidth * v,
                            height: 8,
                            decoration: BoxDecoration(
                                gradient: Pan.gradienteMiel, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Tabla "Por horario" compacta: el horario queda fijo a la izquierda, los
/// nombres largos se parten en renglones y los números van centrados bajo su
/// encabezado. Las columnas se reparten el ancho; solo si son muchos productos
/// se desliza de lado la parte de los números.
class SlotDemandTable extends StatelessWidget {
  final DayDemand demand;
  final List<String> products;
  const SlotDemandTable({super.key, required this.demand, required this.products});

  static const _rowH = 40.0;
  static const _headStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: 1.15,
    color: Pan.canela,
  );
  static const _slotStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
    color: Pan.cacao,
    height: 1.1,
  );
  static const _emojiStyle = TextStyle(fontSize: 17);
  static const _numStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pan.cacao);
  static const _totalStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Pan.cacao);

  @override
  Widget build(BuildContext context) {
    final headers = ['Pedidos', for (final p in products) wrapShort(p)];
    final emojis = ['🧾', for (final p in products) productArt(p).$1];
    final slotRows = [
      for (final s in demand.slots) [s.orders, for (final p in products) s.piecesByProduct[p] ?? 0],
    ];
    final totals = [demand.orders, for (final p in products) demand.totalByProduct[p] ?? 0];

    return LayoutBuilder(
      builder: (context, c) {
        // Medimos con la letra y el tamaño de texto del celular.
        final scaler = MediaQuery.textScalerOf(context);
        final base = DefaultTextStyle.of(context).style;
        Size measure(String text, TextStyle style, [double maxW = double.infinity]) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: base.merge(style)),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: maxW);
          final size = tp.size;
          tp.dispose();
          return size;
        }

        // Columna del horario: lo justo para "10:00", "Horario" y "Total".
        final labelW =
            10 +
            [
              for (final s in demand.slots) measure(_start(s.slot), _slotStyle).width,
              measure('Horario', _headStyle).width,
              measure('Total', _totalStyle).width,
            ].reduce(math.max);

        // Cada columna pide lo de su palabra más larga o su número más grande;
        // lo que sobra se reparte parejo para que todo quede centrado.
        final need = [
          for (final (i, h) in headers.indexed)
            5 +
                [
                  for (final w in h.split(RegExp(r'\s+'))) measure(w, _headStyle).width,
                  for (final r in [...slotRows, totals]) measure('${r[i]}', _totalStyle).width,
                ].reduce(math.max),
        ];
        final avail = c.maxWidth - labelW;
        final needSum = need.fold(0.0, (a, b) => a + b);
        final extra = needSum < avail ? (avail - needSum) / need.length : 0.0;
        final widths = [for (final n in need) n + extra];
        final fits = needSum <= avail + 0.5;

        final emojiH = measure('🥐', _emojiStyle).height;
        final headH =
            emojiH +
            2 +
            [for (final (i, h) in headers.indexed) measure(h, _headStyle, widths[i] - 4).height]
                .reduce(math.max) +
            10;

        Widget cell(int i, Widget child, {double? h}) => SizedBox(
          width: widths[i],
          height: h ?? _rowH,
          child: Center(child: child),
        );
        Widget numText(int v, TextStyle style) =>
            Text('$v', style: v == 0 ? style.copyWith(color: Pan.canela.withValues(alpha: 0.45)) : style);

        final numbers = Column(
          children: [
            Row(
              children: [
                for (final (i, h) in headers.indexed)
                  cell(
                    i,
                    h: headH,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        // Dibujitos parejos arriba; nombres pegados a la línea de abajo.
                        children: [
                          Text(emojis[i], style: _emojiStyle),
                          const SizedBox(height: 2),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Text(h, textAlign: TextAlign.center, style: _headStyle),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            for (final r in slotRows)
              _line(Row(children: [for (final (i, v) in r.indexed) cell(i, numText(v, _numStyle))])),
            _line(
              Row(children: [for (final (i, v) in totals.indexed) cell(i, numText(v, _totalStyle))]),
              total: true,
            ),
          ],
        );

        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: headH,
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Horario', style: _headStyle),
                  ),
                ),
              ),
            ),
            for (final s in demand.slots) _line(_slotLabel(s.slot), width: labelW),
            _line(
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Total', style: _totalStyle),
                ),
              ),
              width: labelW,
              total: true,
            ),
          ],
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            Expanded(
              child: fits ? numbers : SingleChildScrollView(scrollDirection: Axis.horizontal, child: numbers),
            ),
          ],
        );
      },
    );
  }

  /// "10:00" de "10:00 a 11:00".
  String _start(String slot) {
    final full = slotLabel(slot, minutes: demand.slotMinutes);
    final cut = full.indexOf(' a ');
    return cut < 0 ? full : full.substring(0, cut);
  }

  /// "10:00" grande y "a 11:00" chiquito abajo, para que quepa en poco ancho.
  Widget _slotLabel(String slot) {
    final start = _start(slot);
    final rest = slotLabel(slot, minutes: demand.slotMinutes).substring(start.length).trim();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(start, style: _slotStyle),
            if (rest.isNotEmpty)
              Text(rest, style: const TextStyle(fontSize: 10.5, color: Pan.canela, height: 1.1)),
          ],
        ),
      ),
    );
  }

  /// Renglón con su línea arriba; el de total va resaltado en miel.
  Widget _line(Widget child, {double? width, bool total = false}) => Container(
    width: width,
    height: _rowH,
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: total ? const Color(0xFFFFF4D6) : null,
      border: const Border(top: BorderSide(color: Pan.harina)),
    ),
    child: child,
  );
}
