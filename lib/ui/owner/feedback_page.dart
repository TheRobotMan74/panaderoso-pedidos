import 'package:material_ui/material_ui.dart';

import '../../logic/feedback.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../feedback_widgets.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Lo que opinan los clientes: reseñas de sus pedidos e ideas de pan nuevo.
class FeedbackPage extends StatefulWidget {
  /// 0 = reseñas, 1 = ideas de pan.
  final int initialTab;
  const FeedbackPage({super.key, this.initialTab = 0});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  late final _reviews = Repo.instance.allReviews();
  late final _suggestions = Repo.instance.allSuggestions();
  late final _newReviewsCount = Repo.instance.allReviews().map((l) => l.where((r) => !r.seen).length);
  late final _newSuggestionsCount = Repo.instance.allSuggestions().map((l) => l.where((s) => !s.seen).length);

  /// Las que eran nuevas al abrir: siguen con su etiqueta "Nueva" mientras
  /// la pantalla esté abierta, aunque ya se marcaron como vistas.
  final _newIds = <String>{};

  void _markSeen({List<Review> reviews = const [], List<Suggestion> suggestions = const []}) {
    final r = [
      for (final x in reviews)
        if (!x.seen && !_newIds.contains(x.orderId)) x.orderId,
    ];
    final s = [
      for (final x in suggestions)
        if (!x.seen && !_newIds.contains(x.id)) x.id,
    ];
    if (r.isEmpty && s.isEmpty) return;
    _newIds.addAll([...r, ...s]);
    Repo.instance.markFeedbackSeen(reviews: r, suggestions: s).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Opiniones de clientes'),
          bottom: TabBar(
            tabs: [
              Tab(
                child: _TabLabel(stream: _newReviewsCount, text: 'Reseñas'),
              ),
              Tab(
                child: _TabLabel(stream: _newSuggestionsCount, text: 'Ideas de pan'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            StreamBuilder<List<Review>>(
              stream: _reviews,
              builder: (context, snap) {
                if (snap.hasError) {
                  return EmptyState(title: 'No cargaron las reseñas', message: '${snap.error}');
                }
                if (!snap.hasData) return const SkeletonList(count: 3);
                final list = snap.data!;
                WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen(reviews: list));
                return _ReviewsList(reviews: list, newIds: _newIds);
              },
            ),
            StreamBuilder<List<Suggestion>>(
              stream: _suggestions,
              builder: (context, snap) {
                if (snap.hasError) {
                  return EmptyState(title: 'No cargaron las ideas', message: '${snap.error}');
                }
                if (!snap.hasData) return const SkeletonList(count: 3);
                final list = snap.data!;
                WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen(suggestions: list));
                return _SuggestionsList(suggestions: list, newIds: _newIds);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final Stream<int> stream;
  final String text;
  const _TabLabel({required this.stream, required this.text});

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: stream,
        builder: (context, snap) {
          final n = snap.data ?? 0;
          return Badge(
              isLabelVisible: n > 0, label: Text('$n'), offset: const Offset(14, -6), child: Text(text));
        },
      );
}

class _ReviewsList extends StatelessWidget {
  final List<Review> reviews;
  final Set<String> newIds;
  const _ReviewsList({required this.reviews, required this.newIds});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const EmptyState(
        title: 'Aún no hay reseñas',
        message: 'Cuando un cliente califique su pedido, aquí lo verás.\n'
            'A los clientes se les pregunta en el inicio después de su entrega.',
      );
    }
    final children = <Widget>[
      _Summary(summary: RatingSummary.of(reviews)),
      for (final r in reviews) _ReviewCard(review: r, isNew: !r.seen || newIds.contains(r.orderId)),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: children.length,
      itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
    );
  }
}

/// Promedio grande y barritas por estrella.
class _Summary extends StatelessWidget {
  final RatingSummary summary;
  const _Summary({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final most = s.perStar.fold(1, (a, b) => a > b ? a : b);
    return PanCard(
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.average.toStringAsFixed(1),
                style: theme.textTheme.displaySmall!.copyWith(color: Pan.caramelo),
              ),
              StarsView(rating: s.average.round(), size: 16),
              const SizedBox(height: 4),
              Text('${s.count} ${s.count == 1 ? 'reseña' : 'reseñas'}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 14, child: Text('$star', style: theme.textTheme.bodySmall)),
                        const Icon(Icons.star_rounded, size: 14, color: Pan.miel),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: s.perStar[star - 1] / most,
                              minHeight: 8,
                              backgroundColor: Pan.harina,
                              color: Pan.miel,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${s.perStar[star - 1]}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall,
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
}

class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Pan.mielClara, borderRadius: BorderRadius.circular(10)),
        child: const Text(
          'Nueva',
          style: TextStyle(color: Pan.tostado, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      );
}

Future<bool> _confirmDelete(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar $what?'),
        content: const Text('Se borra para siempre.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    ) ??
    false;

void _failed(ScaffoldMessengerState m) => m.showSnackBar(
      const SnackBar(content: Text('No se pudo guardar. Revisa tu internet e intenta de nuevo.')),
    );

class _ReviewCard extends StatelessWidget {
  final Review review;
  final bool isNew;
  const _ReviewCard({required this.review, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = review;
    return PanCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.customerName.isEmpty ? 'Cliente' : r.customerName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isNew) const _NewTag(),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              StarsView(rating: r.rating, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.deliveryDate.isEmpty ? ratingLabel(r.rating) : 'Pedido del ${dayLabel(r.deliveryDate)}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (r.items.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.items.join(' · '), style: theme.textTheme.bodySmall),
          ],
          if (r.comment.isNotEmpty || r.photoPath != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.photoPath != null) ...[
                    ReviewPhoto(path: r.photoPath!, size: 88),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      r.comment.isEmpty ? '(Sin comentario, solo foto)' : '“${r.comment}”',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: r.featured,
                  title: const Text('Mostrar a los clientes'),
                  onChanged: (v) {
                    final m = ScaffoldMessenger.of(context);
                    Repo.instance.setReviewFeatured(r.orderId, v).catchError((_) => _failed(m));
                  },
                ),
              ),
              IconButton(
                tooltip: 'Borrar reseña',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await _confirmDelete(context, 'esta reseña')) {
                    await Repo.instance.deleteReview(r.orderId).catchError((_) {
                      if (context.mounted) _failed(ScaffoldMessenger.of(context));
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  final List<Suggestion> suggestions;
  final Set<String> newIds;
  const _SuggestionsList({required this.suggestions, required this.newIds});

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const EmptyState(
        title: 'Aún no hay ideas',
        message: 'Los clientes pueden sugerir un pan desde el final del menú.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: suggestions.length,
      itemBuilder: (context, i) {
        final s = suggestions[i];
        return FadeSlideIn(
          index: i,
          child: _SuggestionCard(suggestion: s, isNew: !s.seen || newIds.contains(s.id)),
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Suggestion suggestion;
  final bool isNew;
  const _SuggestionCard({required this.suggestion, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = suggestion;
    return PanCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('💡', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.text, style: theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${s.customerName.isEmpty ? 'Cliente' : s.customerName}'
                      '${s.createdAt == null ? '' : ' · ${dateTimeLabel(s.createdAt!)}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (isNew) const _NewTag(),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.liked ? 'Quitar "Me gusta la idea"' : 'Me gusta la idea (el cliente lo ve)',
            isSelected: s.liked,
            icon: const Icon(Icons.favorite_border_rounded),
            selectedIcon: const Icon(Icons.favorite_rounded, color: Pan.terracota),
            onPressed: () {
              final m = ScaffoldMessenger.of(context);
              Repo.instance.setSuggestionLiked(s.id, !s.liked).catchError((_) => _failed(m));
            },
          ),
          IconButton(
            tooltip: 'Borrar idea',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (await _confirmDelete(context, 'esta idea')) {
                await Repo.instance.deleteSuggestion(s.id).catchError((_) {
                  if (context.mounted) _failed(ScaffoldMessenger.of(context));
                });
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Numerito de opiniones nuevas para el ícono del panel.
Stream<int> unseenFeedbackCount() {
  final reviews = Repo.instance.allReviews();
  final suggestions = Repo.instance.allSuggestions();
  return Stream.multi((c) {
    var r = 0, s = 0;
    final a = reviews.listen((l) {
      r = l.where((x) => !x.seen).length;
      c.add(r + s);
    }, onError: (_) {});
    final b = suggestions.listen((l) {
      s = l.where((x) => !x.seen).length;
      c.add(r + s);
    }, onError: (_) {});
    c.onCancel = () {
      a.cancel();
      b.cancel();
    };
  });
}
