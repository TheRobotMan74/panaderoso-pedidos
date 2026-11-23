import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'fold_store.dart';
import 'theme.dart';

/// Recuerda qué tarjetas plegó o abrió el dueño (Demanda, Pedidos…), en este
/// celular. Solo se guarda lo que él tocó; si no tocó nada, cada pantalla
/// decide cómo empieza (por ejemplo, los días vacíos empiezan plegados).
///
/// Las llaves llevan la fecha del día ("demanda|2026-11-24"); las de días ya
/// pasados se tiran solas al guardar, para que el archivo no crezca.
class FoldMemory {
  FoldMemory._();

  static final Map<String, bool> _open = {};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Timer? _saveTimer;

  /// Avisa a las pantallas cuando termina de leer lo guardado.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// Lee lo guardado (una sola vez). Si algo falla, se queda en memoria y ya.
  static Future<void> load() => _loading ??= () async {
    try {
      final raw = await FoldStore.read();
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) {
          for (final e in data.entries) {
            if (e.value is bool && !_open.containsKey(e.key)) _open['${e.key}'] = e.value as bool;
          }
        }
      }
    } catch (_) {}
    _loaded = true;
    changes.value++;
  }();

  /// ¿Está abierta? Si el dueño nunca la tocó, regresa [byDefault].
  static bool isOpen(String key, {required bool byDefault}) {
    if (!_loaded) unawaited(load());
    return _open[key] ?? byDefault;
  }

  static void set(String key, bool open) {
    _open[key] = open;
    changes.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  static Future<void> _save() async {
    // Tira lo de días que ya pasaron: la fecha va después de la primera "|".
    final today = DateTime.now();
    final cut =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    _open.removeWhere((k, _) {
      final parts = k.split('|');
      return parts.length > 1 &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[1]) &&
          parts[1].compareTo(cut) < 0;
    });
    try {
      await FoldStore.write(jsonEncode(_open));
    } catch (_) {}
  }

  /// Solo para pruebas.
  @visibleForTesting
  static void resetForTest() {
    _open.clear();
    _loaded = true;
    _loading = Future.value();
  }
}

/// Encabezado que se toca para plegar o abrir: lo que va adentro, más una
/// flechita que gira.
class FoldHeader extends StatelessWidget {
  final bool open;

  /// Null = no se puede plegar ahorita (por ejemplo, mientras se selecciona).
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticsLabel;
  const FoldHeader({
    super.key,
    required this.open,
    required this.onTap,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    label: semanticsLabel,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 6),
            FoldChevron(open: open),
          ],
        ),
      ),
    ),
  );
}

/// Flechita en un circulito de harina: abajo = abierta, a la derecha = plegada.
class FoldChevron extends StatelessWidget {
  final bool open;
  const FoldChevron({super.key, required this.open});

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: const BoxDecoration(color: Pan.harina, shape: BoxShape.circle),
    child: AnimatedRotation(
      turns: open ? 0 : -0.25,
      duration: Motion.of(context, Motion.rapido),
      curve: Motion.curva,
      child: const Icon(Icons.expand_more_rounded, size: 22, color: Pan.tostado),
    ),
  );
}

/// Lo de adentro de una tarjeta plegable: se encoge o crece con suavidad.
class FoldBody extends StatelessWidget {
  final bool open;
  final Widget child;
  const FoldBody({super.key, required this.open, required this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSize(
      duration: Motion.of(context, Motion.medio),
      curve: Motion.curva,
      alignment: Alignment.topCenter,
      child: open ? child : const SizedBox(width: double.infinity),
    ),
  );
}
