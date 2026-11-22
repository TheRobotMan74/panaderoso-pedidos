import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Colores de Panaderoso: miel y caramelo sobre papel crema, como el oso del ícono.
abstract final class Pan {
  static const crema = Color(0xFFFBF4E6);
  static const papel = Color(0xFFFFFCF6);
  static const harina = Color(0xFFF3E7D2);
  static const miel = Color(0xFFF4B41A);
  static const mielClara = Color(0xFFFFE3A3);
  static const caramelo = Color(0xFFA85F06);
  static const tostado = Color(0xFF7A4A12);
  static const cacao = Color(0xFF3B2A1E);
  static const canela = Color(0xFF7A6352);
  static const salvia = Color(0xFF5E8A4E);
  static const salviaClara = Color(0xFFE3EEDB);
  static const cielo = Color(0xFF3F7CA8);
  static const cieloClaro = Color(0xFFDDEBF5);
  static const ciruela = Color(0xFF8A4FA0);
  static const ciruelaClara = Color(0xFFF0E2F4);
  static const terracota = Color(0xFFB8432F);

  /// Degradado de miel para botones y encabezados.
  static const gradienteMiel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7C547), Color(0xFFE8960F)],
  );

  static const gradienteCaramelo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC27512), Color(0xFF8E4E05)],
  );

  /// Sombra suave y cálida para tarjetas (barata de dibujar: una sola sombra).
  static const sombra = [
    BoxShadow(color: Color(0x1A7A4A12), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static const radio = 22.0;
}

/// Duraciones de las animaciones. Si el celular pide "quitar animaciones", se apagan.
abstract final class Motion {
  static const rapido = Duration(milliseconds: 180);
  static const medio = Duration(milliseconds: 320);
  static const lento = Duration(milliseconds: 560);
  static const curva = Curves.easeOutCubic;
  static const rebote = Curves.easeOutBack;

  static bool off(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) => off(context) ? Duration.zero : d;
}

ThemeData buildPanTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Pan.caramelo,
    onPrimary: Colors.white,
    primaryContainer: Pan.mielClara,
    onPrimaryContainer: Pan.tostado,
    secondary: Pan.miel,
    onSecondary: Pan.cacao,
    secondaryContainer: Color(0xFFFFEFC7),
    onSecondaryContainer: Pan.tostado,
    tertiary: Pan.salvia,
    onTertiary: Colors.white,
    tertiaryContainer: Pan.salviaClara,
    onTertiaryContainer: Color(0xFF2E4B24),
    error: Pan.terracota,
    onError: Colors.white,
    surface: Pan.crema,
    onSurface: Pan.cacao,
    onSurfaceVariant: Pan.canela,
    surfaceContainerLowest: Pan.papel,
    surfaceContainerLow: Color(0xFFFDF8EE),
    surfaceContainer: Color(0xFFF8EEDC),
    surfaceContainerHigh: Pan.harina,
    surfaceContainerHighest: Color(0xFFEDDDC2),
    outline: Color(0xFFD6C2A4),
    outlineVariant: Color(0xFFE9DCC6),
    shadow: Color(0xFF3B2A1E),
    inverseSurface: Pan.cacao,
    onInverseSurface: Pan.crema,
    surfaceTint: Colors.transparent,
  );

  const body = 'Nunito';
  const display = 'Fraunces';
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: body);
  final t = base.textTheme;
  TextStyle d(TextStyle? s, {FontWeight w = FontWeight.w600, double? ls}) =>
      s!.copyWith(fontFamily: display, fontWeight: w, color: Pan.cacao, letterSpacing: ls);
  final text = t.copyWith(
    displaySmall: d(t.displaySmall, w: FontWeight.w700, ls: -0.5),
    headlineLarge: d(t.headlineLarge, w: FontWeight.w700, ls: -0.5),
    headlineMedium: d(t.headlineMedium, w: FontWeight.w700, ls: -0.4),
    headlineSmall: d(t.headlineSmall, ls: -0.3),
    titleLarge: d(t.titleLarge, ls: -0.2),
    titleMedium: t.titleMedium!.copyWith(fontWeight: FontWeight.w800, color: Pan.cacao),
    titleSmall: t.titleSmall!.copyWith(fontWeight: FontWeight.w700, color: Pan.cacao),
    bodyLarge: t.bodyLarge!.copyWith(color: Pan.cacao),
    bodyMedium: t.bodyMedium!.copyWith(color: Pan.cacao),
    bodySmall: t.bodySmall!.copyWith(color: Pan.canela, fontSize: 12.5),
    labelLarge: t.labelLarge!.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
  );

  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: Pan.crema,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _SoftRiseTransition(),
        TargetPlatform.iOS: _SoftRiseTransition(),
        TargetPlatform.linux: _SoftRiseTransition(),
        TargetPlatform.macOS: _SoftRiseTransition(),
        TargetPlatform.windows: _SoftRiseTransition(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Pan.crema,
      foregroundColor: Pan.cacao,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge!.copyWith(fontSize: 24),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Pan.papel,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: Pan.papel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Pan.radio),
        side: const BorderSide(color: Color(0xFFF0E4CF)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pan.caramelo,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE6D9C4),
        disabledForegroundColor: const Color(0xFFA6927C),
        padding: buttonPadding,
        shape: pill,
        textStyle: text.labelLarge!.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pan.tostado,
        side: const BorderSide(color: Color(0xFFDCC7A6), width: 1.4),
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pan.caramelo,
        shape: pill,
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Pan.miel,
      foregroundColor: Pan.cacao,
      elevation: 4,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      extendedTextStyle: text.labelLarge!.copyWith(fontSize: 15),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Pan.papel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: Pan.canela),
      floatingLabelStyle: const TextStyle(color: Pan.caramelo, fontWeight: FontWeight.w700),
      prefixIconColor: Pan.canela,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE6D6BC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE6D6BC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Pan.miel, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Pan.terracota),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Pan.terracota, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Pan.papel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Pan.mielClara,
      elevation: 0,
      height: 70,
      shadowColor: Colors.transparent,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: body,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? Pan.tostado : Pan.canela,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Pan.tostado : Pan.canela),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Pan.papel,
      selectedColor: Pan.mielClara,
      side: const BorderSide(color: Color(0xFFE6D6BC)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(fontFamily: body, fontWeight: FontWeight.w700, color: Pan.cacao),
      checkmarkColor: Pan.tostado,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: Pan.mielClara,
        selectedForegroundColor: Pan.tostado,
        side: const BorderSide(color: Color(0xFFE6D6BC)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFB9A58C)),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Pan.salvia : const Color(0xFFF1E6D3)),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Pan.salvia : const Color(0xFFD9C6A8)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Pan.caramelo : Pan.canela),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pan.cacao,
      contentTextStyle: const TextStyle(fontFamily: body, color: Pan.crema, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Pan.papel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.headlineSmall,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pan.papel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFFDCC7A6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Pan.papel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: const TextStyle(fontFamily: body, fontWeight: FontWeight.w700, color: Pan.cacao),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFEADCC4), thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Pan.miel),
    listTileTheme: const ListTileThemeData(iconColor: Pan.tostado),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
          fontFamily: body, fontWeight: FontWeight.w800, color: Pan.canela, fontSize: 12.5),
      dataTextStyle: const TextStyle(fontFamily: body, color: Pan.cacao, fontWeight: FontWeight.w600),
      dividerThickness: 0.6,
    ),
  );
}

/// Transición entre pantallas: la nueva sube un poquito mientras aparece.
/// Solo usa opacidad y traslación (barato en celulares de gama media).
class _SoftRiseTransition extends PageTransitionsBuilder {
  const _SoftRiseTransition();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(enter),
        child: child,
      ),
    );
  }
}
