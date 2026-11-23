import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../logic/feedback.dart';
import '../models.dart';
import '../services/repo.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

// Reseñas de pedidos e ideas de pan nuevo, del lado del cliente.

/// Estrellas de solo ver (★★★★☆).
class StarsView extends StatelessWidget {
  final int rating;
  final double size;
  const StarsView({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i <= rating ? Pan.miel : const Color(0xFFD6C2A4),
            ),
        ],
      );
}

/// Cinco estrellas grandes para tocar. La que se toca da un brinquito.
class StarPicker extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  final double size;
  const StarPicker({super.key, required this.rating, required this.onChanged, this.size = 44});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Semantics(
              button: true,
              label: '$i ${i == 1 ? 'estrella' : 'estrellas'}',
              selected: i <= rating,
              child: Pressable(
                haptic: true,
                scale: 0.85,
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedScale(
                    scale: i <= rating ? 1 : 0.88,
                    duration: Motion.of(context, Motion.medio),
                    curve: Motion.rebote,
                    child: Icon(
                      i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: size,
                      color: i <= rating ? Pan.miel : const Color(0xFFD6C2A4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

/// Foto de una reseña (se baja de Storage). Al tocarla se ve grande.
class ReviewPhoto extends StatelessWidget {
  final String path;
  final double size;
  const ReviewPhoto({super.key, required this.path, this.size = 72});

  void _open(BuildContext context, String url) => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Repo.instance.reviewPhotoUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        final box = SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: url == null || url.isEmpty
                ? Container(
                    color: Pan.harina,
                    alignment: Alignment.center,
                    child: Icon(
                      snap.hasError ? Icons.broken_image_outlined : Icons.photo_outlined,
                      color: Pan.canela,
                    ),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    cacheWidth: (size * 3).round(),
                    errorBuilder: (_, _, _) => Container(
                      color: Pan.harina,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, color: Pan.canela),
                    ),
                  ),
          ),
        );
        if (url == null || url.isEmpty) return box;
        return Pressable(onTap: () => _open(context, url), child: box);
      },
    );
  }
}

/// Abre la hoja para calificar [order]. [existing] es su reseña si ya tenía.
Future<void> showReviewSheet(
  BuildContext context, {
  required BakeryOrder order,
  Review? existing,
  int initialRating = 0,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Pan.papel,
    builder: (_) => _ReviewSheet(order: order, existing: existing, initialRating: initialRating),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('¡Gracias por tu reseña! 🐻 Nos ayuda muchísimo.')));
  }
}

class _ReviewSheet extends StatefulWidget {
  final BakeryOrder order;
  final Review? existing;
  final int initialRating;
  const _ReviewSheet({required this.order, this.existing, this.initialRating = 0});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.existing?.rating ?? widget.initialRating;
  late final _comment = TextEditingController(text: widget.existing?.comment ?? '');

  /// Foto nueva elegida (aún sin subir).
  Uint8List? _photo;

  /// Foto que ya tenía la reseña. Null si la quitó o no tenía.
  late String? _oldPhoto = widget.existing?.photoPath;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1400, imageQuality: 80);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _oldPhoto = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la cámara o las fotos. Revisa los permisos.')),
      );
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final o = widget.order;
    try {
      var photoPath = _oldPhoto;
      if (_photo != null) photoPath = await Repo.instance.uploadReviewPhoto(o.customerId, _photo!);
      await Repo.instance.saveReview(
        Review(
          orderId: o.id,
          customerId: o.customerId,
          customerName: o.customerName,
          rating: _rating,
          comment: _comment.text.trim(),
          photoPath: photoPath,
          items: reviewItems(o),
          deliveryDate: o.deliveryDate,
        ),
        isNew: widget.existing == null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo mandar. Revisa tu internet e intenta de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.order;
    final hasPhoto = _photo != null || _oldPhoto != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? '¿Qué tal estuvo tu pan?' : 'Cambiar mi reseña',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Pedido del ${dayLabel(o.deliveryDate)}\n${reviewItems(o).join(' · ')}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Center(
                child: StarPicker(rating: _rating, onChanged: (r) => setState(() => _rating = r)),
              ),
              const SizedBox(height: 6),
              AnimatedCount(
                _rating == 0 ? 'Toca las estrellas' : ratingLabel(_rating),
                style: theme.textTheme.titleMedium!.copyWith(color: _rating == 0 ? Pan.canela : Pan.caramelo),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _comment,
                maxLines: 4,
                minLines: 2,
                maxLength: reviewMaxChars,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Cuéntanos más (opcional)',
                  hintText: '¿Qué te gustó? ¿Qué le cambiarías?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              if (hasPhoto)
                Row(
                  children: [
                    if (_photo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          _photo!,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                          cacheWidth: 250,
                        ),
                      )
                    else
                      ReviewPhoto(path: _oldPhoto!, size: 84),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Tu foto', style: theme.textTheme.bodyMedium)),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _photo = null;
                        _oldPhoto = null;
                      }),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Quitar'),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: const Text('Tomar foto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text('De mis fotos'),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'La foto es opcional. Panaderoso puede mostrar tu reseña a otros clientes, solo con tu primer nombre.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              HoneyButton(
                icon: Icons.send_rounded,
                label: widget.existing == null ? 'Mandar reseña' : 'Guardar cambios',
                busy: _busy,
                onPressed: _rating == 0 ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta en el inicio: "¿Qué tal estuvo tu pan del lunes?" con estrellas para tocar.
/// Solo sale para el último pedido, si es reciente y no lo ha calificado.
class ReviewPrompt extends StatefulWidget {
  final AppUser user;
  const ReviewPrompt({super.key, required this.user});

  @override
  State<ReviewPrompt> createState() => _ReviewPromptState();
}

class _ReviewPromptState extends State<ReviewPrompt> {
  late final _orders = Repo.instance.myOrders(widget.user.uid);
  late final _reviews = Repo.instance.myReviews(widget.user.uid);

  /// Se esconde al instante al decir "Ahora no", sin esperar al servidor.
  String? _hidden;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BakeryOrder>>(
      stream: _orders,
      builder: (context, ordersSnap) => StreamBuilder<List<Review>>(
        stream: _reviews,
        builder: (context, reviewsSnap) {
          final order = ordersSnap.hasData && reviewsSnap.hasData
              ? orderToReview(
                  ordersSnap.data!,
                  reviewed: {for (final r in reviewsSnap.data!) r.orderId},
                  skipped: widget.user.reviewSkipped,
                  now: DateTime.now(),
                )
              : null;
          final show = order != null && order.id != _hidden;
          return AnimatedSize(
            duration: Motion.of(context, Motion.medio),
            curve: Motion.curva,
            alignment: Alignment.topCenter,
            child: show ? _card(context, order) : const SizedBox(width: double.infinity),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, BakeryOrder o) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PanCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 26, height: 1.1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Qué tal estuvo tu pan del ${dayLabel(o.deliveryDate).split(' de ').first}?',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tu opinión nos ayuda a hornearlo cada vez mejor.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: StarPicker(
                      rating: 0,
                      size: 38,
                      onChanged: (r) => showReviewSheet(context, order: o, initialRating: r),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _hidden = o.id);
                    Repo.instance.skipReview(widget.user.uid, o.id).catchError((_) {});
                  },
                  child: const Text('Ahora no'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reseñas que el dueño escogió, en tarjetitas que se deslizan de lado.
class FeaturedReviews extends StatefulWidget {
  const FeaturedReviews({super.key});

  @override
  State<FeaturedReviews> createState() => _FeaturedReviewsState();
}

class _FeaturedReviewsState extends State<FeaturedReviews> {
  late final _stream = Repo.instance.featuredReviews();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Review>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <Review>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Lo que dicen nuestros clientes'),
            SizedBox(
              height: 166,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _FeaturedCard(review: list[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final Review review;
  const _FeaturedCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = review;
    final first = r.customerName.trim().split(' ').first;
    return SizedBox(
      width: r.photoPath == null ? 240 : 300,
      child: PanCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (r.photoPath != null) ...[
              ReviewPhoto(path: r.photoPath!, size: 104),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarsView(rating: r.rating, size: 18),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      r.comment.isEmpty ? ratingLabel(r.rating) : '“${r.comment}”',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    first.isEmpty ? 'Cliente' : first,
                    style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w800),
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

/// Tarjeta al final del menú: "¿Se te antoja otro pan?".
class SuggestBreadCard extends StatelessWidget {
  final AppUser user;
  const SuggestBreadCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanCard(
      margin: const EdgeInsets.only(top: 14, bottom: 6),
      color: Pan.harina,
      onTap: () => showSuggestSheet(context, user),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Pan.papel, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('💡', style: TextStyle(fontSize: 26, height: 1)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Se te antoja otro pan?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('Sugiérenos uno y lo tomamos en cuenta para el menú.', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Pan.caramelo),
        ],
      ),
    );
  }
}

/// Ideas rápidas para tocar en vez de escribir.
const breadIdeas = [
  'Conchas',
  'Rol de canela',
  'Orejas',
  'Mantecadas',
  'Cheesecake',
  'Pan de elote',
  'Cuernitos',
];

Future<void> showSuggestSheet(BuildContext context, AppUser user) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Pan.papel,
    builder: (_) => _SuggestSheet(user: user),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('¡Gracias por tu idea! 🐻 Ya le llegó a Panaderoso.')));
  }
}

class _SuggestSheet extends StatefulWidget {
  final AppUser user;
  const _SuggestSheet({required this.user});

  @override
  State<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends State<_SuggestSheet> {
  final _text = TextEditingController();
  late final _mine = Repo.instance.mySuggestions(widget.user.uid);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _addIdea(String idea) {
    final t = _text.text.trim();
    _text.text = t.isEmpty ? idea : '$t, $idea';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    HapticFeedback.selectionClick();
  }

  Future<void> _send() async {
    final text = cleanSuggestion(_text.text);
    if (text == null) return;
    setState(() => _busy = true);
    try {
      await Repo.instance.sendSuggestion(uid: widget.user.uid, name: widget.user.name, text: text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo mandar. Revisa tu internet e intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sugiere un pan', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '¿Qué te gustaría que horneáramos? Leemos todas las ideas.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                maxLines: 3,
                minLines: 2,
                maxLength: suggestionMaxChars,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tu idea',
                  hintText: 'Ej. Conchas de vainilla los domingos',
                  alignLabelWithHint: true,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final idea in breadIdeas)
                    ActionChip(
                      label: Text(idea),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      onPressed: () => _addIdea(idea),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              HoneyButton(
                icon: Icons.send_rounded,
                label: 'Mandar idea',
                busy: _busy,
                onPressed: cleanSuggestion(_text.text) == null ? null : _send,
              ),
              StreamBuilder<List<Suggestion>>(
                stream: _mine,
                builder: (context, snap) {
                  final mine = snap.data ?? const <Suggestion>[];
                  if (mine.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('Tus ideas'),
                      for (final s in mine.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.liked ? '💛' : '💭', style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.text, style: theme.textTheme.bodyMedium),
                                    if (s.liked)
                                      Text(
                                        '¡A Panaderoso le gustó tu idea!',
                                        style: theme.textTheme.bodySmall!.copyWith(
                                          color: Pan.caramelo,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
