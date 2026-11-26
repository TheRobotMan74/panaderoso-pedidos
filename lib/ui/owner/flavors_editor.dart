import 'package:material_ui/material_ui.dart';

import '../../logic/flavors.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../product_image.dart';
import '../theme.dart';

/// Ajustes → Sabores: cada pan con sus sabores. Tocar uno abre el editor y se
/// guarda en el pan al momento (no hace falta el botón Guardar de abajo).
class FlavorsSettings extends StatelessWidget {
  const FlavorsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Product>>(
      stream: Repo.instance.products(),
      builder: (context, snap) {
        final products = snap.data ?? const <Product>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Si un pan tiene sabores, el cliente elige cuántas de cada uno '
              '(por ejemplo 3 donas: 2 de chocolate y 1 de caramelo). Todos los sabores '
              'comparten el cupo de ese pan. En Demanda ves cuántas hacer de cada sabor.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            for (final p in products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(productArt(p.name).$1, style: const TextStyle(fontSize: 22)),
                title: Text(p.name, style: theme.textTheme.titleSmall),
                subtitle: Text(
                  p.hasFlavors ? p.flavors.join(' · ') : 'Sin sabores',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: p.hasFlavors ? Pan.tostado : Pan.canela,
                    fontWeight: p.hasFlavors ? FontWeight.w700 : null,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Pan.canela),
                onTap: () async {
                  final next = await showFlavorEditor(context, name: p.name, flavors: p.flavors);
                  if (next == null) return;
                  await Repo.instance.saveProduct(p.copyWith(flavors: next));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(next.isEmpty ? '${p.name}: sin sabores' : 'Sabores de ${p.name} guardados ✓'),
                  ));
                },
              ),
          ],
        );
      },
    );
  }
}

/// Editor de los sabores de un pan. Regresa la lista nueva (vacía = sin sabores)
/// o null si se canceló.
Future<List<String>?> showFlavorEditor(
  BuildContext context, {
  required String name,
  required List<String> flavors,
}) =>
    showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FlavorEditor(name: name, initial: flavors),
    );

class _FlavorEditor extends StatefulWidget {
  final String name;
  final List<String> initial;
  const _FlavorEditor({required this.name, required this.initial});

  @override
  State<_FlavorEditor> createState() => _FlavorEditorState();
}

class _FlavorEditorState extends State<_FlavorEditor> {
  late final List<String> _flavors = [...widget.initial];
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _add() {
    final next = cleanFlavors([..._flavors, _new.text]);
    setState(() {
      _flavors
        ..clear()
        ..addAll(next);
      _new.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = _flavors.length >= maxFlavors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sabores de ${widget.name}', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Si quitas todos, el cliente solo elige cuántas. Los pedidos que ya están '
                'hechos se quedan con su sabor.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_flavors.isEmpty)
                Text('Sin sabores', style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in _flavors)
                      InputChip(
                        avatar: Text(flavorEmoji(f)),
                        label: Text(f),
                        onDeleted: () => setState(() => _flavors.remove(f)),
                        deleteButtonTooltipMessage: 'Quitar $f',
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _new,
                      enabled: !full,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: full ? 'Ya son $maxFlavors sabores' : 'Agregar sabor',
                        hintText: 'Fresa, Nutella…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Agregar',
                    onPressed: full ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              if (looksLikeDonut(widget.name) && !_sameAsDefault)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _flavors
                        ..clear()
                        ..addAll(defaultDonutFlavors);
                    }),
                    child: Text('Volver a ${defaultDonutFlavors.join(', ')}'),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  // Lo que quedó escrito sin picarle "+" también se agrega.
                  final out = cleanFlavors([..._flavors, _new.text]);
                  Navigator.pop(context, out);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Guardar sabores'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _sameAsDefault =>
      _flavors.length == defaultDonutFlavors.length &&
      [for (var i = 0; i < _flavors.length; i++) _flavors[i] == defaultDonutFlavors[i]].every((x) => x);
}

/// En el formulario del pan: "Sabores: Glaseado · Chocolate · Caramelo  >".
class FlavorsField extends StatelessWidget {
  final String name;
  final List<String> flavors;
  final ValueChanged<List<String>> onChanged;
  const FlavorsField({super.key, required this.name, required this.flavors, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Sabores'),
      subtitle: Text(
        flavors.isEmpty ? 'Sin sabores (el cliente solo elige cuántas)' : flavors.join(' · '),
        style: theme.textTheme.bodySmall!.copyWith(
          color: flavors.isEmpty ? Pan.canela : Pan.tostado,
          fontWeight: flavors.isEmpty ? null : FontWeight.w700,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Pan.canela),
      onTap: () async {
        final next = await showFlavorEditor(context,
            name: name.trim().isEmpty ? 'este pan' : name.trim(), flavors: flavors);
        if (next != null) onChanged(next);
      },
    );
  }
}
