import 'package:flutter/material.dart';

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_icon.dart';

/// Punto "en vivo" con pulso (se detiene con `reduce motion`).
class LiveIndicator extends StatefulWidget {
  const LiveIndicator({super.key, this.live = true, this.onInk = false, this.label});
  final bool live;
  final bool onInk;
  final String? label;

  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.live && !reduce) {
      _ctl.repeat(reverse: true);
    } else {
      _ctl.stop();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final color = widget.live ? c.brandMint : c.neutral50;
    final text = widget.label ?? (widget.live ? 'En vivo' : 'Sin conexión');
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _ctl,
          builder: (_, __) => Opacity(
            opacity: widget.live ? 0.5 + 0.5 * _ctl.value : 1,
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
        ),
        const SizedBox(width: QhSpacing.s02),
        Text(text, style: QhText.caption.copyWith(color: widget.onInk ? c.sidebarText : c.textSecondary)),
      ]),
    );
  }
}

/// Estado vacío con anillo + cola del símbolo.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.action});
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QhSpacing.s07),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Symbol(),
          const SizedBox(height: QhSpacing.s05),
          Text(title, style: QhText.h3, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: QhSpacing.s02),
            Text(message!, style: QhText.body.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: QhSpacing.s05), action!],
        ]),
      ),
    );
  }
}

class _Symbol extends StatelessWidget {
  const _Symbol();
  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return SizedBox(
      width: 48,
      height: 48,
      child: CustomPaint(painter: _SymbolPainter(c.brandIndigo, c.brandMint)),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.ring, this.tail);
  final Color ring;
  final Color tail;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32;
    canvas.drawCircle(Offset(14 * s, 14 * s), 9 * s,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 4 * s..color = ring);
    canvas.drawLine(Offset(19 * s, 19 * s), Offset(24 * s, 24 * s), Paint()..strokeWidth = 4 * s..color = tail);
    final p = Path()
      ..moveTo(30 * s, 30 * s)
      ..lineTo(30 * s, 20.5 * s)
      ..lineTo(20.5 * s, 30 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = tail);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.ring != ring || old.tail != tail;
}

/// Esqueleto de carga (sin brillo animado si hay reduce motion).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 16});
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      Container(width: width, height: height, color: context.qh.skeletonBg);
}

enum QhNoticeKind { info, success, warning, error }

/// Aviso en línea (ícono + texto), con `Semantics(liveRegion)`.
class QhNotice extends StatelessWidget {
  const QhNotice({super.key, required this.kind, required this.title, this.message, this.onClose});
  final QhNoticeKind kind;
  final String title;
  final String? message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final (QhIcons icon, Color color) = switch (kind) {
      QhNoticeKind.info => (QhIcons.info, c.supportInfo),
      QhNoticeKind.success => (QhIcons.check, c.supportSuccess),
      QhNoticeKind.warning => (QhIcons.warning, c.supportWarning),
      QhNoticeKind.error => (QhIcons.error, c.supportError),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(QhSpacing.s04),
        decoration: BoxDecoration(
          color: c.layer01,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: QhIcon(icon, size: 20, color: color)),
          const SizedBox(width: QhSpacing.s04),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: QhText.body.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary)),
              if (message != null) Text(message!, style: QhText.body.copyWith(color: c.textSecondary)),
            ]),
          ),
          if (onClose != null) InkResponse(onTap: onClose, child: const Padding(padding: EdgeInsets.all(4), child: QhIcon(QhIcons.close))),
        ]),
      ),
    );
  }
}

/// Tabs planas con subrayado indigo en la activa.
class QhTabs extends StatelessWidget {
  const QhTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Row(children: [
      for (var i = 0; i < labels.length; i++)
        Semantics(
          button: true,
          selected: i == index,
          label: labels[i],
          child: InkWell(
            onTap: () => onChanged(i),
            child: Container(
              height: QhSize.controlLg,
              padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: i == index ? c.interactive : c.borderSubtle, width: i == index ? 3 : 1)),
              ),
              child: Text(labels[i],
                  style: QhText.body.copyWith(
                      color: i == index ? c.textPrimary : c.textSecondary,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w400)),
            ),
          ),
        ),
    ]);
  }
}

/// Diálogo de confirmación (acciones destructivas: no-show, eliminar cola, cancelar turno).
Future<bool> qhConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  bool danger = true,
}) async {
  final c = context.qh;
  final res = await showDialog<bool>(
    context: context,
    barrierColor: c.overlay,
    builder: (ctx) => Dialog(
      backgroundColor: c.layer01,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(QhSpacing.s06),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: QhText.h3),
            const SizedBox(height: QhSpacing.s03),
            Text(message, style: QhText.body.copyWith(color: c.textSecondary)),
            const SizedBox(height: QhSpacing.s06),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(cancelLabel, style: QhText.body.copyWith(color: c.link)),
              ),
              const SizedBox(width: QhSpacing.s03),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: danger ? c.supportError : c.interactive,
                  foregroundColor: c.textOnColor,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(QhRadius.sm))),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(confirmLabel),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  return res ?? false;
}
