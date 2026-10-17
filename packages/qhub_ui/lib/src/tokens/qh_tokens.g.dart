// GENERADO por tool/gen_tokens.dart desde tokens/tokens.json. No editar a mano.
// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/material.dart';

/// Colores del design system (ThemeExtension). Acceso: `context.qh`.
@immutable
class QhColors extends ThemeExtension<QhColors> {
  const QhColors({
    required this.brandIndigo,
    required this.brandInk,
    required this.brandMint,
    required this.neutral10,
    required this.neutral20,
    required this.neutral50,
    required this.neutral70,
    required this.neutral90,
    required this.background,
    required this.layer01,
    required this.layer02,
    required this.layerHover,
    required this.layerSelected,
    required this.field,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.textDisabled,
    required this.textOnColor,
    required this.textOnAccent,
    required this.interactive,
    required this.interactiveHover,
    required this.interactiveActive,
    required this.link,
    required this.linkOnInk,
    required this.errorOnInk,
    required this.focus,
    required this.focusInset,
    required this.sidebarBg,
    required this.sidebarHover,
    required this.sidebarActive,
    required this.sidebarText,
    required this.sidebarTextActive,
    required this.stateWaiting,
    required this.stateWaitingText,
    required this.stateServing,
    required this.stateServingText,
    required this.stateDone,
    required this.stateDoneText,
    required this.stateCancelled,
    required this.stateCancelledText,
    required this.stateNoshow,
    required this.stateNoshowText,
    required this.supportError,
    required this.supportSuccess,
    required this.supportWarning,
    required this.supportInfo,
    required this.overlay,
    required this.skeletonBg,
    required this.skeletonShine,
  });
  /// Qhub Indigo, primario de marca. Relleno de la acción principal, logo y selección. Como texto solo sobre layer-01/background en claro (5.6:1); en oscuro usa link.
  final Color brandIndigo;
  /// Ink de marca. Sidebar, cabeceras oscuras, texto sobre turn-mint y sobre fills de estado.
  final Color brandInk;
  /// Turn Mint, acento. Solo como relleno o marca (indicador activo, "en vivo", cola del logo); nunca texto sobre claro (1.9:1). Texto encima: brand-ink.
  final Color brandMint;
  /// Neutro base de la paleta. Fondo claro.
  final Color neutral10;
  /// Neutro de bordes sutiles y divisores.
  final Color neutral20;
  /// Neutro medio. Estado Cancelado, íconos inactivos en oscuro.
  final Color neutral50;
  /// Neutro de texto secundario en claro.
  final Color neutral70;
  /// Neutro de texto principal en claro y capa base en oscuro.
  final Color neutral90;
  /// Fondo de página / lienzo de la app.
  final Color background;
  /// Superficie de tiles, tablas, modales y paneles sobre background.
  final Color layer01;
  /// Superficie anidada dentro de layer-01 (cabecera de tabla, bloque secundario).
  final Color layer02;
  /// Hover de filas, ítems de menú y botones ghost.
  final Color layerHover;
  /// Fila o ítem seleccionado.
  final Color layerSelected;
  /// Fondo de inputs, selects y selector de fecha (estilo campo con borde inferior).
  final Color field;
  /// Divisores y bordes de tiles; nunca como único límite de un control.
  final Color borderSubtle;
  /// Borde inferior de campos y bordes de controles. 3.8:1 sobre field claro, 3.9:1 sobre field oscuro.
  final Color borderStrong;
  /// Texto principal sobre background, layer-01, layer-02 y field.
  final Color textPrimary;
  /// Texto secundario, labels y helper sobre background, layer-01, layer-02 (≥5:1).
  final Color textSecondary;
  /// Placeholder en field (4.6:1 claro, 4.9:1 oscuro). Nunca sustituye al label.
  final Color textPlaceholder;
  /// Texto deshabilitado (exento de contraste por WCAG). Siempre con cursor not-allowed.
  final Color textDisabled;
  /// Texto e íconos sobre brand-indigo, interactive-hover y support-error.
  final Color textOnColor;
  /// Texto sobre brand-mint y sobre todos los fills de estado (state-*).
  final Color textOnAccent;
  /// Botón primario, tab activo, checkbox marcado, borde de selección.
  final Color interactive;
  /// Hover del botón primario (texto blanco 7:1).
  final Color interactiveHover;
  /// Pressed del botón primario.
  final Color interactiveActive;
  /// Enlaces y botón ghost/tertiary. 5.2:1 sobre background claro, 6.6:1 sobre layer-01 oscuro.
  final Color link;
  /// Enlaces, info y sintaxis de código sobre brand-ink y sidebar-bg (7:1).
  final Color linkOnInk;
  /// Error/No-show como ícono o texto sobre brand-ink (5.9:1).
  final Color errorOnInk;
  /// Anillo de foco de 2 px en todos los controles; ≥3:1 sobre todas las superficies.
  final Color focus;
  /// Separador interior de 1 px entre el foco y un relleno indigo.
  final Color focusInset;
  /// Navegación lateral del admin y del sitio de docs.
  final Color sidebarBg;
  /// Hover de ítems del sidebar.
  final Color sidebarHover;
  /// Ítem activo del sidebar (con indicador brand-mint de 3 px a la izquierda).
  final Color sidebarActive;
  /// Texto de ítems del sidebar sobre sidebar-bg (≥7:1).
  final Color sidebarText;
  /// Texto del ítem activo y del logo sobre sidebar-bg.
  final Color sidebarTextActive;
  /// Estado En espera. Relleno de badge y barras; texto encima text-on-accent (9.9:1).
  final Color stateWaiting;
  /// "En espera" como texto/ícono sobre layer-01 y background.
  final Color stateWaitingText;
  /// Estado Atendiendo (= brand-mint). Relleno; texto encima text-on-accent (9.3:1).
  final Color stateServing;
  /// "Atendiendo" como texto/ícono sobre layer-01 y background.
  final Color stateServingText;
  /// Estado Finalizado. Relleno; texto encima text-on-accent (5.9:1).
  final Color stateDone;
  /// "Finalizado" como texto/ícono sobre layer-01 y background.
  final Color stateDoneText;
  /// Estado Cancelado. Relleno; texto encima text-on-accent (5.8:1).
  final Color stateCancelled;
  /// "Cancelado" como texto/ícono sobre layer-01 y background.
  final Color stateCancelledText;
  /// Estado No-show. Relleno; texto encima text-on-accent (4.7:1).
  final Color stateNoshow;
  /// "No-show" como texto/ícono sobre layer-01 y background.
  final Color stateNoshowText;
  /// Errores de formulario: borde del campo, ícono y mensaje. Texto blanco sobre él solo en claro.
  final Color supportError;
  /// Confirmaciones (toast de éxito, check).
  final Color supportSuccess;
  /// Advertencias.
  final Color supportWarning;
  /// Información.
  final Color supportInfo;
  /// Velo detrás de modales.
  final Color overlay;
  /// Fondo del esqueleto de carga.
  final Color skeletonBg;
  /// Brillo animado del esqueleto.
  final Color skeletonShine;
  static const QhColors light = QhColors(
    brandIndigo: Color(0xFF3B4EFF),
    brandInk: Color(0xFF0E1330),
    brandMint: Color(0xFF00D1B2),
    neutral10: Color(0xFFF4F5F8),
    neutral20: Color(0xFFE0E3EB),
    neutral50: Color(0xFF8B91A5),
    neutral70: Color(0xFF5B6078),
    neutral90: Color(0xFF161A2E),
    background: Color(0xFFF4F5F8),
    layer01: Color(0xFFFFFFFF),
    layer02: Color(0xFFF4F5F8),
    layerHover: Color(0xFFE8EAF0),
    layerSelected: Color(0xFFE0E3EB),
    field: Color(0xFFF4F5F8),
    borderSubtle: Color(0xFFE0E3EB),
    borderStrong: Color(0xFF767C95),
    textPrimary: Color(0xFF161A2E),
    textSecondary: Color(0xFF5B6078),
    textPlaceholder: Color(0xFF676D8C),
    textDisabled: Color(0xFFA6ABBC),
    textOnColor: Color(0xFFFFFFFF),
    textOnAccent: Color(0xFF0E1330),
    interactive: Color(0xFF3B4EFF),
    interactiveHover: Color(0xFF2E40E6),
    interactiveActive: Color(0xFF2333C2),
    link: Color(0xFF3B4EFF),
    linkOnInk: Color(0xFF8C98FF),
    errorOnInk: Color(0xFFF26368),
    focus: Color(0xFF3B4EFF),
    focusInset: Color(0xFFFFFFFF),
    sidebarBg: Color(0xFF0E1330),
    sidebarHover: Color(0xFF1E2448),
    sidebarActive: Color(0xFF262D5A),
    sidebarText: Color(0xFFB4B9CC),
    sidebarTextActive: Color(0xFFFFFFFF),
    stateWaiting: Color(0xFFFFB020),
    stateWaitingText: Color(0xFF8A5A00),
    stateServing: Color(0xFF00D1B2),
    stateServingText: Color(0xFF00786A),
    stateDone: Color(0xFF1FA866),
    stateDoneText: Color(0xFF157A49),
    stateCancelled: Color(0xFF8B91A5),
    stateCancelledText: Color(0xFF5B6078),
    stateNoshow: Color(0xFFE5484D),
    stateNoshowText: Color(0xFFC42B31),
    supportError: Color(0xFFC42B31),
    supportSuccess: Color(0xFF157A49),
    supportWarning: Color(0xFF8A5A00),
    supportInfo: Color(0xFF3B4EFF),
    overlay: Color(0x990E1330),
    skeletonBg: Color(0xFFE0E3EB),
    skeletonShine: Color(0xFFECEEF3),
  );
  static const QhColors dark = QhColors(
    brandIndigo: Color(0xFF3B4EFF),
    brandInk: Color(0xFF0E1330),
    brandMint: Color(0xFF00D1B2),
    neutral10: Color(0xFFF4F5F8),
    neutral20: Color(0xFFE0E3EB),
    neutral50: Color(0xFF8B91A5),
    neutral70: Color(0xFF5B6078),
    neutral90: Color(0xFF161A2E),
    background: Color(0xFF0E1330),
    layer01: Color(0xFF161A2E),
    layer02: Color(0xFF1E2340),
    layerHover: Color(0xFF252B4A),
    layerSelected: Color(0xFF2A3054),
    field: Color(0xFF1E2340),
    borderSubtle: Color(0xFF2A3050),
    borderStrong: Color(0xFF7A809C),
    textPrimary: Color(0xFFF4F5F8),
    textSecondary: Color(0xFFB4B9CC),
    textPlaceholder: Color(0xFF8B91A5),
    textDisabled: Color(0xFF4A5070),
    textOnColor: Color(0xFFFFFFFF),
    textOnAccent: Color(0xFF0E1330),
    interactive: Color(0xFF3B4EFF),
    interactiveHover: Color(0xFF2E40E6),
    interactiveActive: Color(0xFF2333C2),
    link: Color(0xFF8C98FF),
    linkOnInk: Color(0xFF8C98FF),
    errorOnInk: Color(0xFFF26368),
    focus: Color(0xFFFFFFFF),
    focusInset: Color(0xFF0E1330),
    sidebarBg: Color(0xFF0A0D22),
    sidebarHover: Color(0xFF1A1F3C),
    sidebarActive: Color(0xFF232A52),
    sidebarText: Color(0xFFB4B9CC),
    sidebarTextActive: Color(0xFFFFFFFF),
    stateWaiting: Color(0xFFFFB020),
    stateWaitingText: Color(0xFFFFB020),
    stateServing: Color(0xFF00D1B2),
    stateServingText: Color(0xFF00D1B2),
    stateDone: Color(0xFF1FA866),
    stateDoneText: Color(0xFF1FA866),
    stateCancelled: Color(0xFF8B91A5),
    stateCancelledText: Color(0xFF8B91A5),
    stateNoshow: Color(0xFFE5484D),
    stateNoshowText: Color(0xFFF26368),
    supportError: Color(0xFFF26368),
    supportSuccess: Color(0xFF1FA866),
    supportWarning: Color(0xFFFFB020),
    supportInfo: Color(0xFF8C98FF),
    overlay: Color(0x99050712),
    skeletonBg: Color(0xFF252B4A),
    skeletonShine: Color(0xFF2F3657),
  );
  @override
  QhColors copyWith({
    Color? brandIndigo,
    Color? brandInk,
    Color? brandMint,
    Color? neutral10,
    Color? neutral20,
    Color? neutral50,
    Color? neutral70,
    Color? neutral90,
    Color? background,
    Color? layer01,
    Color? layer02,
    Color? layerHover,
    Color? layerSelected,
    Color? field,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textPlaceholder,
    Color? textDisabled,
    Color? textOnColor,
    Color? textOnAccent,
    Color? interactive,
    Color? interactiveHover,
    Color? interactiveActive,
    Color? link,
    Color? linkOnInk,
    Color? errorOnInk,
    Color? focus,
    Color? focusInset,
    Color? sidebarBg,
    Color? sidebarHover,
    Color? sidebarActive,
    Color? sidebarText,
    Color? sidebarTextActive,
    Color? stateWaiting,
    Color? stateWaitingText,
    Color? stateServing,
    Color? stateServingText,
    Color? stateDone,
    Color? stateDoneText,
    Color? stateCancelled,
    Color? stateCancelledText,
    Color? stateNoshow,
    Color? stateNoshowText,
    Color? supportError,
    Color? supportSuccess,
    Color? supportWarning,
    Color? supportInfo,
    Color? overlay,
    Color? skeletonBg,
    Color? skeletonShine,
  }) =>
      QhColors(
        brandIndigo: brandIndigo ?? this.brandIndigo,
        brandInk: brandInk ?? this.brandInk,
        brandMint: brandMint ?? this.brandMint,
        neutral10: neutral10 ?? this.neutral10,
        neutral20: neutral20 ?? this.neutral20,
        neutral50: neutral50 ?? this.neutral50,
        neutral70: neutral70 ?? this.neutral70,
        neutral90: neutral90 ?? this.neutral90,
        background: background ?? this.background,
        layer01: layer01 ?? this.layer01,
        layer02: layer02 ?? this.layer02,
        layerHover: layerHover ?? this.layerHover,
        layerSelected: layerSelected ?? this.layerSelected,
        field: field ?? this.field,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textPlaceholder: textPlaceholder ?? this.textPlaceholder,
        textDisabled: textDisabled ?? this.textDisabled,
        textOnColor: textOnColor ?? this.textOnColor,
        textOnAccent: textOnAccent ?? this.textOnAccent,
        interactive: interactive ?? this.interactive,
        interactiveHover: interactiveHover ?? this.interactiveHover,
        interactiveActive: interactiveActive ?? this.interactiveActive,
        link: link ?? this.link,
        linkOnInk: linkOnInk ?? this.linkOnInk,
        errorOnInk: errorOnInk ?? this.errorOnInk,
        focus: focus ?? this.focus,
        focusInset: focusInset ?? this.focusInset,
        sidebarBg: sidebarBg ?? this.sidebarBg,
        sidebarHover: sidebarHover ?? this.sidebarHover,
        sidebarActive: sidebarActive ?? this.sidebarActive,
        sidebarText: sidebarText ?? this.sidebarText,
        sidebarTextActive: sidebarTextActive ?? this.sidebarTextActive,
        stateWaiting: stateWaiting ?? this.stateWaiting,
        stateWaitingText: stateWaitingText ?? this.stateWaitingText,
        stateServing: stateServing ?? this.stateServing,
        stateServingText: stateServingText ?? this.stateServingText,
        stateDone: stateDone ?? this.stateDone,
        stateDoneText: stateDoneText ?? this.stateDoneText,
        stateCancelled: stateCancelled ?? this.stateCancelled,
        stateCancelledText: stateCancelledText ?? this.stateCancelledText,
        stateNoshow: stateNoshow ?? this.stateNoshow,
        stateNoshowText: stateNoshowText ?? this.stateNoshowText,
        supportError: supportError ?? this.supportError,
        supportSuccess: supportSuccess ?? this.supportSuccess,
        supportWarning: supportWarning ?? this.supportWarning,
        supportInfo: supportInfo ?? this.supportInfo,
        overlay: overlay ?? this.overlay,
        skeletonBg: skeletonBg ?? this.skeletonBg,
        skeletonShine: skeletonShine ?? this.skeletonShine,
      );
  @override
  QhColors lerp(ThemeExtension<QhColors>? other, double t) {
    if (other is! QhColors) return this;
    return QhColors(
      brandIndigo: Color.lerp(brandIndigo, other.brandIndigo, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      brandMint: Color.lerp(brandMint, other.brandMint, t)!,
      neutral10: Color.lerp(neutral10, other.neutral10, t)!,
      neutral20: Color.lerp(neutral20, other.neutral20, t)!,
      neutral50: Color.lerp(neutral50, other.neutral50, t)!,
      neutral70: Color.lerp(neutral70, other.neutral70, t)!,
      neutral90: Color.lerp(neutral90, other.neutral90, t)!,
      background: Color.lerp(background, other.background, t)!,
      layer01: Color.lerp(layer01, other.layer01, t)!,
      layer02: Color.lerp(layer02, other.layer02, t)!,
      layerHover: Color.lerp(layerHover, other.layerHover, t)!,
      layerSelected: Color.lerp(layerSelected, other.layerSelected, t)!,
      field: Color.lerp(field, other.field, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textOnColor: Color.lerp(textOnColor, other.textOnColor, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
      interactiveHover: Color.lerp(interactiveHover, other.interactiveHover, t)!,
      interactiveActive: Color.lerp(interactiveActive, other.interactiveActive, t)!,
      link: Color.lerp(link, other.link, t)!,
      linkOnInk: Color.lerp(linkOnInk, other.linkOnInk, t)!,
      errorOnInk: Color.lerp(errorOnInk, other.errorOnInk, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      focusInset: Color.lerp(focusInset, other.focusInset, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      sidebarHover: Color.lerp(sidebarHover, other.sidebarHover, t)!,
      sidebarActive: Color.lerp(sidebarActive, other.sidebarActive, t)!,
      sidebarText: Color.lerp(sidebarText, other.sidebarText, t)!,
      sidebarTextActive: Color.lerp(sidebarTextActive, other.sidebarTextActive, t)!,
      stateWaiting: Color.lerp(stateWaiting, other.stateWaiting, t)!,
      stateWaitingText: Color.lerp(stateWaitingText, other.stateWaitingText, t)!,
      stateServing: Color.lerp(stateServing, other.stateServing, t)!,
      stateServingText: Color.lerp(stateServingText, other.stateServingText, t)!,
      stateDone: Color.lerp(stateDone, other.stateDone, t)!,
      stateDoneText: Color.lerp(stateDoneText, other.stateDoneText, t)!,
      stateCancelled: Color.lerp(stateCancelled, other.stateCancelled, t)!,
      stateCancelledText: Color.lerp(stateCancelledText, other.stateCancelledText, t)!,
      stateNoshow: Color.lerp(stateNoshow, other.stateNoshow, t)!,
      stateNoshowText: Color.lerp(stateNoshowText, other.stateNoshowText, t)!,
      supportError: Color.lerp(supportError, other.supportError, t)!,
      supportSuccess: Color.lerp(supportSuccess, other.supportSuccess, t)!,
      supportWarning: Color.lerp(supportWarning, other.supportWarning, t)!,
      supportInfo: Color.lerp(supportInfo, other.supportInfo, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      skeletonBg: Color.lerp(skeletonBg, other.skeletonBg, t)!,
      skeletonShine: Color.lerp(skeletonShine, other.skeletonShine, t)!,
    );
  }
}

abstract final class QhSpacing {
  /// Separación ícono–borde mínima.
  static const double s01 = 2;
  /// Gap entre ícono y texto en badges.
  static const double s02 = 4;
  /// Unidad base. Gap entre ícono y label en botones.
  static const double s03 = 8;
  /// Padding vertical de filas compactas.
  static const double s04 = 12;
  /// Padding de campos y botones; margen lateral móvil.
  static const double s05 = 16;
  /// Padding de tiles y modales; gutter de la cuadrícula.
  static const double s06 = 24;
  /// Separación entre secciones de un formulario.
  static const double s07 = 32;
  /// Separación entre bloques de página.
  static const double s08 = 40;
  /// Margen de cabecera de página.
  static const double s09 = 48;
  /// Separación de secciones de landing.
  static const double s10 = 64;
  /// Separación mayor de landing.
  static const double s11 = 80;
}

abstract final class QhSize {
  /// Controles en barras de herramientas de tabla y filtros.
  static const double controlSm = 32;
  /// Altura por defecto de botones, inputs y selects en escritorio.
  static const double controlMd = 40;
  /// Altura en móvil y CTA de landing (objetivo táctil).
  static const double controlLg = 48;
  /// Barra superior del admin y del sitio.
  static const double headerHeight = 48;
  /// Navegación lateral expandida (48 px colapsada).
  static const double sidebarWidth = 256;
  /// Fila de tabla por defecto (40 px en modo compacto).
  static const double rowHeight = 48;
}

abstract final class QhRadius {
  /// Tiles, tablas, sidebar, modales: la norma.
  static const double s0 = 0;
  /// Botones, campos, badges, toasts.
  static const double sm = 2;
  /// Máximo permitido: tarjetas móviles y bloques de código.
  static const double md = 4;
  /// Solo el punto del indicador "en vivo" y avatares.
  static const double round = 999;
}

/// Estilos de texto sin color (el color lo pone el tema/widget).
abstract final class QhText {
  /// Solo landing y pantallas de bienvenida. Una vez por vista.
  static const TextStyle display = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 54, height: 1.1852, fontWeight: FontWeight.w300, letterSpacing: -0.5,
    fontVariations: [FontVariation('wght', 300)],
  );
  /// Título de página.
  static const TextStyle h1 = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 32, height: 1.2500, fontWeight: FontWeight.w400, letterSpacing: 0,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Título de sección mayor o cabecera de modal grande.
  static const TextStyle h2 = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 28, height: 1.2857, fontWeight: FontWeight.w400, letterSpacing: 0,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Título de tile, de panel y de modal.
  static const TextStyle h3 = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 20, height: 1.4000, fontWeight: FontWeight.w400, letterSpacing: 0,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Subsección, cabecera de grupo de formulario.
  static const TextStyle h4 = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 16, height: 1.5000, fontWeight: FontWeight.w600, letterSpacing: 0,
    fontVariations: [FontVariation('wght', 600)],
  );
  /// Texto de interfaz por defecto: tablas, formularios, botones.
  static const TextStyle body = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 14, height: 1.4286, fontWeight: FontWeight.w400, letterSpacing: 0.16,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Párrafos de landing y documentación; texto principal en móvil.
  static const TextStyle bodyLong = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 16, height: 1.5000, fontWeight: FontWeight.w400, letterSpacing: 0,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Labels de campos, cabeceras de tabla, badges.
  static const TextStyle label = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 12, height: 1.3333, fontWeight: FontWeight.w500, letterSpacing: 0.32,
    fontVariations: [FontVariation('wght', 500)],
  );
  /// Helper text, metadatos, marcas de tiempo.
  static const TextStyle caption = TextStyle(
    fontFamily: 'IBMPlexSans', package: 'qhub_ui', fontSize: 12, height: 1.3333, fontWeight: FontWeight.w400, letterSpacing: 0.32,
    fontVariations: [FontVariation('wght', 400)],
  );
  /// Número de turno en "Mi turno" (móvil) y en la vista en vivo.
  static const TextStyle turnXl = TextStyle(
    fontFamily: 'IBMPlexMono', package: 'qhub_ui', fontSize: 64, height: 1.1250, fontWeight: FontWeight.w500, letterSpacing: 0,
  );
  /// Número de turno en tiles, filas y toasts.
  static const TextStyle turn = TextStyle(
    fontFamily: 'IBMPlexMono', package: 'qhub_ui', fontSize: 20, height: 1.4000, fontWeight: FontWeight.w500, letterSpacing: 0,
  );
  /// Bloques de código y endpoints de la documentación.
  static const TextStyle code = TextStyle(
    fontFamily: 'IBMPlexMono', package: 'qhub_ui', fontSize: 14, height: 1.4286, fontWeight: FontWeight.w400, letterSpacing: 0,
  );
  /// Código en línea, IDs y valores técnicos en tablas.
  static const TextStyle codeSm = TextStyle(
    fontFamily: 'IBMPlexMono', package: 'qhub_ui', fontSize: 12, height: 1.3333, fontWeight: FontWeight.w400, letterSpacing: 0,
  );
}
