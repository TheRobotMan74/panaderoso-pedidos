import 'package:material_ui/material_ui.dart';

import '../../logic/market.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'market_owner_page.dart';

/// Arriba de los pedidos, mientras el mercadito está abierto:
/// "Mercadito abierto · $1,240 · quedan 22". Al tocarlo se abre el Mercadito.
class MarketBanner extends StatefulWidget {
  const MarketBanner({super.key});

  @override
  State<MarketBanner> createState() => _MarketBannerState();
}

class _MarketBannerState extends State<MarketBanner> {
  late final Stream<Market?> _open = Repo.instance.openMarket();
  String? _salesOf;
  Stream<({List<MarketSale> sales, bool offline})>? _sales;

  Stream<({List<MarketSale> sales, bool offline})> _salesFor(String id) {
    if (_salesOf != id || _sales == null) {
      _salesOf = id;
      _sales = Repo.instance.marketSales(id);
    }
    return _sales!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Market?>(
      stream: _open,
      builder: (context, snap) {
        final m = snap.data;
        return AnimatedSize(
          duration: Motion.of(context, Motion.medio),
          curve: Motion.curva,
          alignment: Alignment.topCenter,
          child: m == null
              ? const SizedBox(width: double.infinity)
              : StreamBuilder<({List<MarketSale> sales, bool offline})>(
                  stream: _salesFor(m.id),
                  builder: (context, s) {
                    final sum = MarketSummary.of(s.data?.sales ?? const [], markets: [m]);
                    return MaxWidth(
                      maxWidth: Ancho.lectura + 32,
                      child: PanCard(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        gradient: Pan.gradienteMiel,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const MarketOwnerPage())),
                        child: Row(
                          children: [
                            const Text('🧺', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${m.title} abierto',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w900, color: Pan.cacao)),
                                  AnimatedCount(
                                    '${money(sum.total)} vendido · quedan ${sum.left} de ${sum.brought}',
                                    alignment: Alignment.centerLeft,
                                    maxLines: 1,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Pan.tostado),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Pan.cacao),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
