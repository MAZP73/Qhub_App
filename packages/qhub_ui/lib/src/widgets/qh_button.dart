import 'package:flutter/material.dart';

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_icon.dart';

enum QhButtonKind { primary, secondary, tertiary, ghost, danger, accent }

enum QhButtonSize { sm, md, lg }

/// Botón del design system. Texto a la izquierda, ícono a la derecha; una sola primaria por vista.
class QhButton extends StatelessWidget {
  const QhButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = QhButtonKind.primary,
    this.size = QhButtonSize.md,
    this.icon,
    this.block = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final QhButtonKind kind;
  final QhButtonSize size;
  final QhIcons? icon;
  final bool block;
  final bool loading;

  double get _height => switch (size) {
        QhButtonSize.sm => QhSize.controlSm,
        QhButtonSize.md => QhSize.controlMd,
        QhButtonSize.lg => QhSize.controlLg,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final enabled = onPressed != null && !loading;

    final (Color bg, Color fg, BorderSide side) = switch (kind) {
      QhButtonKind.primary => (c.interactive, c.textOnColor, BorderSide.none),
      QhButtonKind.secondary => (c.layer02, c.textPrimary, BorderSide(color: c.borderStrong)),
      QhButtonKind.tertiary => (Colors.transparent, c.link, BorderSide(color: c.link)),
      QhButtonKind.ghost => (Colors.transparent, c.link, BorderSide.none),
      QhButtonKind.danger => (c.supportError, Theme.of(context).colorScheme.onError, BorderSide.none),
      QhButtonKind.accent => (c.brandMint, c.textOnAccent, BorderSide.none),
    };

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, _height)),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(_height)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: QhSpacing.s05)),
      elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(QhRadius.sm)))),
      textStyle: const WidgetStatePropertyAll(QhText.body),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return c.layerSelected;
        if (kind == QhButtonKind.primary) {
          if (s.contains(WidgetState.pressed)) return c.interactiveActive;
          if (s.contains(WidgetState.hovered)) return c.interactiveHover;
        }
        if (s.contains(WidgetState.hovered) && bg == Colors.transparent) return c.layerHover;
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.textDisabled : fg),
      side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? BorderSide.none : side),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );

    final content = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (loading) ...[
          const SizedBox(width: QhSpacing.s03),
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.textDisabled)),
        ] else if (icon != null) ...[
          const SizedBox(width: QhSpacing.s03),
          QhIcon(icon!),
        ],
      ],
    );

    final button = FilledButton(onPressed: enabled ? onPressed : null, style: style, child: content);
    final focusWrapped = Focus(
      canRequestFocus: false,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(QhRadius.sm)),
            border: focused ? Border.all(color: c.focus, width: 2) : null,
          ),
          child: button,
        );
      }),
    );
    return Semantics(button: true, enabled: enabled, label: label, excludeSemantics: true, child: block ? SizedBox(width: double.infinity, child: focusWrapped) : focusWrapped);
  }
}

/// Botón cuadrado de solo ícono (requiere etiqueta accesible).
class QhIconButton extends StatelessWidget {
  const QhIconButton({super.key, required this.icon, required this.label, required this.onPressed, this.size = 40});
  final QhIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onPressed,
          radius: size / 2,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: QhIcon(icon, size: 20, color: onPressed == null ? c.textDisabled : c.textPrimary)),
          ),
        ),
      ),
    );
  }
}
