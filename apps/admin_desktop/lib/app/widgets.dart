import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

/// Cabecera de página: migas, título y acciones.
class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.breadcrumb, this.actions = const []});
  final String title;
  final String? breadcrumb;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Padding(
      padding: const EdgeInsets.only(bottom: QhSpacing.s06),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (breadcrumb != null) Text(breadcrumb!, style: QhText.caption.copyWith(color: c.textSecondary)),
            Semantics(header: true, child: Text(title, style: QhText.h1)),
          ]),
        ),
        for (final a in actions) Padding(padding: const EdgeInsets.only(left: QhSpacing.s03), child: a),
      ]),
    );
  }
}

/// Error con mensaje claro y reintento.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is Failure ? (error as Failure).message : 'Ocurrió un error inesperado.';
    return EmptyState(
      title: 'No pudimos cargar esto',
      message: msg,
      action: onRetry == null ? null : QhButton(label: 'Reintentar', onPressed: onRetry, kind: QhButtonKind.tertiary),
    );
  }
}

/// Atajo para `AsyncValue`: cargando → esqueletos; error → [ErrorView].
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        error: (e, _) => ErrorView(error: e, onRetry: onRetry),
        loading: () =>
            loading ??
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 24, width: 240),
              SizedBox(height: QhSpacing.s04),
              Skeleton(height: 120),
            ]),
      );
}

/// Contenedor de panel (layer-01, borde sutil, sin radio ni sombra).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.padding = const EdgeInsets.all(QhSpacing.s06), this.trailing});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: c.layer01, border: Border.all(color: c.borderSubtle)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[
          Row(children: [Expanded(child: Text(title!, style: QhText.h3)), ?trailing]),
          const SizedBox(height: QhSpacing.s05),
        ],
        child,
      ]),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Container(
      padding: const EdgeInsets.all(QhSpacing.s05),
      color: c.layer01,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: QhText.caption.copyWith(color: c.textSecondary)),
        const SizedBox(height: QhSpacing.s02),
        Text(value, style: QhText.h1.copyWith(fontWeight: FontWeight.w300, fontVariations: const [FontVariation('wght', 300)])),
        if (hint != null) Text(hint!, style: QhText.caption.copyWith(color: c.textSecondary)),
      ]),
    );
  }
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
    duration: Duration(seconds: error ? 8 : 6),
  ));
}
