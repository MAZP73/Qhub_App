import 'package:flutter/material.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

/// Barra superior móvil (título + acciones). Respeta el área segura.
class QhAppBar extends StatelessWidget {
  const QhAppBar({super.key, required this.title, this.leading, this.actions = const []});
  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Container(
      color: c.layer01,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s03),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.borderSubtle))),
        child: Row(children: [
          leading ?? const SizedBox(width: QhSpacing.s03),
          Expanded(child: Semantics(header: true, child: Text(title, style: QhText.h3, maxLines: 1, overflow: TextOverflow.ellipsis))),
          ...actions,
        ]),
      ),
    );
  }
}

/// Marca de organización (iniciales sobre cuadrado de color).
class OrgMark extends StatelessWidget {
  const OrgMark(this.text, {super.key, this.color, this.size = 40});
  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: color ?? c.brandInk,
      child: Text(text, style: QhText.code.copyWith(color: Colors.white, fontWeight: FontWeight.w500, fontSize: size * 0.3)),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        title: 'No pudimos cargar esto',
        message: error is Failure ? (error as Failure).message : 'Ocurrió un error inesperado.',
        action: onRetry == null ? null : QhButton(label: 'Reintentar', kind: QhButtonKind.tertiary, onPressed: onRetry),
      );
}

void showToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      QhIcon(error ? QhIcons.error : QhIcons.check, color: error ? context.qh.errorOnInk : context.qh.brandMint),
      const SizedBox(width: QhSpacing.s03),
      Expanded(child: Text(message)),
    ]),
  ));
}

/// Fila de lista: icono/marca, título, subtítulos y chevron (design: `.qh-list`).
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.leading, required this.title, this.subtitles = const [], this.trailing, this.onTap, this.highlighted = false});
  final Widget leading;
  final Widget title;
  final List<String> subtitles;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05, vertical: QhSpacing.s04),
        decoration: BoxDecoration(
          color: highlighted ? c.layerHover : c.layer01,
          border: Border(bottom: BorderSide(color: c.borderSubtle)),
        ),
        child: Row(children: [
          leading,
          const SizedBox(width: QhSpacing.s04),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              for (final s in subtitles) Text(s, style: QhText.caption.copyWith(color: c.textSecondary)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}
