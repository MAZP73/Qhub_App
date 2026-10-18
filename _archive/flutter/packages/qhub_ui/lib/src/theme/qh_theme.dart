import 'package:flutter/material.dart';

import '../tokens/qh_tokens.g.dart';

/// Acceso corto a los tokens: `context.qh.layer01`.
extension QhContext on BuildContext {
  QhColors get qh => Theme.of(this).extension<QhColors>()!;
}

/// Tema Material construido solo con tokens (sin hex sueltos).
abstract final class QhTheme {
  static ThemeData light() => _build(QhColors.light, Brightness.light);
  static ThemeData dark() => _build(QhColors.dark, Brightness.dark);

  static ThemeData _build(QhColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.interactive,
      onPrimary: c.textOnColor,
      secondary: c.brandMint,
      onSecondary: c.textOnAccent,
      error: c.supportError,
      onError: b == Brightness.light ? c.textOnColor : c.textOnAccent,
      surface: c.layer01,
      onSurface: c.textPrimary,
    );
    final text = TextTheme(
      displayLarge: QhText.display,
      headlineLarge: QhText.h1,
      headlineMedium: QhText.h2,
      titleLarge: QhText.h3,
      titleMedium: QhText.h4,
      bodyLarge: QhText.bodyLong,
      bodyMedium: QhText.body,
      labelLarge: QhText.label,
      bodySmall: QhText.caption,
    ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      fontFamily: 'IBMPlexSans',
      package: 'qhub_ui',
      dividerColor: c.borderSubtle,
      focusColor: c.focus,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.borderSubtle, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.sidebarBg,
        foregroundColor: c.sidebarTextActive,
        elevation: 0,
        toolbarHeight: QhSize.headerHeight,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.brandInk,
        contentTextStyle: QhText.body.copyWith(color: c.sidebarTextActive),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(QhRadius.sm))),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.layer01,
        shape: const RoundedRectangleBorder(),
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.brandInk),
        textStyle: QhText.caption.copyWith(color: c.sidebarTextActive),
      ),
    );
  }
}

/// Sombra de elementos flotantes (único uso permitido).
List<BoxShadow> qhOverlayShadow(Brightness b) => [
      BoxShadow(
        color: b == Brightness.light ? const Color(0x4D0E1330) : const Color(0x99000000),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
