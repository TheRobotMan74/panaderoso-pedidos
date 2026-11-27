import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// El oso de Panaderoso en círculo.
class BearLogo extends StatelessWidget {
  final double size;
  const BearLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Pan.papel,
          border: Border.all(color: Colors.white, width: size * 0.04),
          boxShadow: const [
            BoxShadow(color: Color(0x33E8960F), blurRadius: 28, offset: Offset(0, 10)),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/oso.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth: (size * 3).round(),
          ),
        ),
      );
}

/// El oso flotando suavecito (sube y baja, y se mece un poco).
class FloatingBear extends StatefulWidget {
  final double size;
  const FloatingBear({super.key, this.size = 120});

  @override
  State<FloatingBear> createState() => _FloatingBearState();
}

class _FloatingBearState extends State<FloatingBear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.off(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = RepaintBoundary(child: BearLogo(size: widget.size));
    return AnimatedBuilder(
      animation: _c,
      child: logo,
      builder: (context, child) {
        final t = _c.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * 6),
          child: Transform.rotate(angle: math.sin(t + 0.6) * 0.035, child: child),
        );
      },
    );
  }
}

/// Aparece subiendo un poquito, con un retraso según su lugar en la lista
/// (efecto "cascada"). Solo anima la primera vez que se construye.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration step;
  final double offset;

  /// Si la lista ya se movió (el usuario está bajando), aparece de inmediato:
  /// así nunca hay huecos esperando a que algo aparezca.
  final bool skipWhenScrolled;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 55),
    this.offset = 18,
    this.skipWhenScrolled = true,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.lento);
  late final _a = CurvedAnimation(parent: _c, curve: Motion.curva);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final pos = widget.skipWhenScrolled ? Scrollable.maybeOf(context)?.position : null;
    final scrolled = pos != null && pos.hasPixels && pos.pixels > 0;
    if (Motion.off(context) || scrolled) {
      _c.value = 1;
      return;
    }
    // Máximo ~0.5 s de espera aunque la lista sea larga.
    final delay = widget.step * math.min(widget.index, 9);
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: AnimatedBuilder(
          animation: _a,
          child: widget.child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - _a.value) * widget.offset),
            child: child,
          ),
        ),
      );
}

/// Se encoge tantito al tocarlo, como un botón de verdad.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97, this.haptic = false});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.of(context, const Duration(milliseconds: 120)),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Tarjeta crema con sombra cálida.
class PanCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  const PanCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.color,
    this.gradient,
    this.onTap,
    this.radius = Pan.radio,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Pan.papel) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Pan.sombra,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, child: card);
  }
}

/// Título de sección con un puntito de miel.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 4, 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Pan.miel, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
            ?trailing,
          ],
        ),
      );
}

/// Botón grande de miel (para la acción principal de la pantalla).
class HoneyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const HoneyButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Pressable(
      onTap: enabled ? onPressed : null,
      haptic: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medio),
        curve: Motion.curva,
        height: 58,
        decoration: BoxDecoration(
          gradient: enabled ? Pan.gradienteCaramelo : null,
          color: enabled ? null : const Color(0xFFE6D9C4),
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? const [BoxShadow(color: Color(0x40A85F06), blurRadius: 16, offset: Offset(0, 8))]
              : const [],
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: Motion.of(context, Motion.rapido),
          child: busy
              ? const SizedBox(
                  key: ValueKey('busy'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                )
              : Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: enabled ? Colors.white : const Color(0xFFA6927C)),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: enabled ? Colors.white : const Color(0xFFA6927C),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Números que cambian deslizándose (cantidades, totales).
class AnimatedCount extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  final int? maxLines;
  const AnimatedCount(this.text,
      {super.key, this.style, this.alignment = Alignment.center, this.maxLines});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(context, const Duration(milliseconds: 260)),
        switchInCurve: Motion.curva,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, a) {
          final incoming = child.key == ValueKey(text);
          return FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: Offset(0, incoming ? 0.6 : -0.6),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: alignment,
          children: [...previous, ?current],
        ),
        child: Text(
          text,
          key: ValueKey(text),
          style: style,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
      );
}

/// Brillo que pasa encima de los "esqueletos" mientras carga.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.off(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final x = -1.5 + _c.value * 3;
              return LinearGradient(
                begin: Alignment(x - 0.6, -0.3),
                end: Alignment(x + 0.6, 0.3),
                colors: const [Color(0xFFF1E4CD), Color(0xFFFBF3E3), Color(0xFFF1E4CD)],
              ).createShader(rect);
            },
            child: child,
          ),
        ),
      );
}

/// Un bloque gris-harina del esqueleto.
class Bone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const Bone({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1E4CD),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Lista de tarjetas-esqueleto mientras llegan los datos.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool withImage;
  final EdgeInsetsGeometry padding;
  const SkeletonList({
    super.key,
    this.count = 4,
    this.withImage = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  Widget build(BuildContext context) => Shimmer(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: count,
          itemBuilder: (_, i) => Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Pan.papel,
              borderRadius: BorderRadius.circular(Pan.radio),
            ),
            child: Row(
              children: [
                if (withImage) ...[
                  const Bone(width: 92, height: 92, radius: 18),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: 120 + (i % 3) * 30.0, height: 18),
                      const SizedBox(height: 10),
                      const Bone(height: 12),
                      const SizedBox(height: 6),
                      const Bone(width: 140, height: 12),
                      const SizedBox(height: 12),
                      const Bone(width: 60, height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Pantalla vacía amable, con el oso.
class EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.title, this.message = '', this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(opacity: 0.9, child: const FloatingBear(size: 104)),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cambia de pestaña con un fundido suave (sin saltos).
class FadeThroughSwitcher extends StatelessWidget {
  final Widget child;
  const FadeThroughSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(context, const Duration(milliseconds: 300)),
        switchInCurve: Motion.curva,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.0).animate(a),
            child: child,
          ),
        ),
        child: child,
      );
}

/// Puntito que late (para "en vivo" / "en camino").
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, this.color = Pan.salvia, this.size = 10});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.off(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s * 2.4,
        height: s * 2.4,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s * (1 + _c.value * 1.4),
                height: s * (1 + _c.value * 1.4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saludo según la hora del día.
String greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Buenas noches';
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

/// En pantallas anchas (la compu) deja la app centrada con un ancho cómodo,
/// en vez de estirar las tarjetas de lado a lado. En el celular no hace nada.
///
/// El árbol de widgets es siempre el mismo (angosto o ancho): así, al girar la
/// tablet o desdoblar el celular, no se pierde la pantalla en la que ibas.
class WideFrame extends StatelessWidget {
  final Widget child;
  const WideFrame({super.key, required this.child});

  static const maxWidth = 1100.0;

  /// Cuántas pantallas abiertas piden usar todo el ancho (la caja del mercadito
  /// en la tablet). Mientras sea más de 0 no se pone el marco.
  static final fullWidth = ValueNotifier<int>(0);

  /// Para una pantalla que quiere todo el ancho: llamar en initState con true
  /// y en dispose con false. El cambio se hace después del cuadro actual.
  static void useFullWidth(bool on) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fullWidth.value = (fullWidth.value + (on ? 1 : -1)).clamp(0, 99);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: fullWidth,
        builder: (context, full, _) {
          final mq = MediaQuery.of(context);
          final framed = full == 0 && mq.size.width > maxWidth + 40;
          final width = framed ? maxWidth : mq.size.width;
          return ColoredBox(
            color: Pan.harina,
            child: Center(
              child: Container(
                width: width,
                decoration: BoxDecoration(
                  boxShadow: framed ? const [BoxShadow(color: Color(0x1A3B2A1E), blurRadius: 30)] : null,
                ),
                // Las pantallas de adentro "creen" que la ventana mide lo mismo que el marco.
                child: MediaQuery(
                  data: mq.copyWith(size: Size(width, mq.size.height)),
                  child: ClipRect(child: child),
                ),
              ),
            ),
          );
        },
      );
}

/// Medidas para pantallas grandes: tablets, plegables abiertos y la compu.
abstract final class Ancho {
  /// Desde aquí la navegación va en una barra a la izquierda (como el panel del dueño).
  static const barraLateral = 840.0;

  /// Desde aquí los panes del menú van de dos en dos.
  static const dosColumnas = 700.0;

  /// Ancho cómodo para leer una columna de tarjetas o un formulario.
  static const lectura = 680.0;

  /// Ancho del menú en dos columnas.
  static const menu = 960.0;

  static bool barra(BuildContext context) => MediaQuery.sizeOf(context).width >= barraLateral;
}

/// Una lista que en el celular se ve igual que siempre, y en pantalla ancha deja
/// las tarjetas en una columna centrada de [maxWidth]. El relleno va *dentro* de la
/// lista, así se puede deslizar tocando en cualquier lado de la pantalla.
class ReadableList extends StatelessWidget {
  final EdgeInsets padding;
  final double maxWidth;
  final Widget Function(BuildContext context, EdgeInsets padding) builder;
  const ReadableList({
    super.key,
    required this.padding,
    required this.builder,
    this.maxWidth = Ancho.lectura,
  });

  /// [base] más lo que haga falta a los lados para que el contenido no pase de [maxWidth].
  static EdgeInsets pad(double width, EdgeInsets base, {double maxWidth = Ancho.lectura}) {
    final inner = width - base.horizontal;
    if (inner <= maxWidth) return base;
    final extra = (inner - maxWidth) / 2;
    return base.copyWith(left: base.left + extra, right: base.right + extra);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => builder(context, pad(c.maxWidth, padding, maxWidth: maxWidth)),
      );
}

/// Centra [child] con un ancho máximo (para barras y paneles que flotan sobre un mapa).
class MaxWidth extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  final AlignmentGeometry alignment;
  const MaxWidth({super.key, required this.maxWidth, required this.child, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        widthFactor: 1,
        heightFactor: 1,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
