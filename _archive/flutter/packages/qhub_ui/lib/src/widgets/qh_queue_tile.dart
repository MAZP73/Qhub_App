import 'package:flutter/material.dart';
import 'package:qhub_api_client/qhub_api_client.dart' show TicketStatus;

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_misc.dart';
import 'qh_turn.dart';

/// Resumen rectangular de una cola. Sin sombra ni radio.
class QueueTile extends StatelessWidget {
  const QueueTile({
    super.key,
    required this.name,
    required this.waiting,
    required this.serving,
    this.subtitle,
    this.currentNumber,
    this.prefix = 'A',
    this.live = true,
    this.closed = false,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final String? subtitle;
  final int waiting;
  final int serving;
  final int? currentNumber;
  final String prefix;
  final bool live;
  final bool closed;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final total = waiting + serving;
    return Semantics(
      button: onTap != null,
      label: '$name, $waiting en espera, $serving atendiendo',
      excludeSemantics: true,
      child: InkWell(
        onTap: closed ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(QhSpacing.s06),
          decoration: BoxDecoration(
            color: c.layer01,
            border: Border.all(color: selected ? c.interactive : c.borderSubtle, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: QhText.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) Text(subtitle!, style: QhText.caption.copyWith(color: c.textSecondary)),
                ]),
              ),
              if (closed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s03, vertical: 3),
                  decoration: BoxDecoration(color: c.layerSelected, borderRadius: BorderRadius.circular(QhRadius.sm)),
                  child: Text('Cerrada', style: QhText.label.copyWith(color: c.textSecondary)),
                )
              else
                LiveIndicator(live: live),
            ]),
            const SizedBox(height: QhSpacing.s05),
            Row(children: [
              if (currentNumber != null) ...[
                TurnNumber(number: currentNumber!, prefix: prefix),
                const SizedBox(width: QhSpacing.s03),
                const TurnBadge(TicketStatus.atendiendo),
              ] else
                Text('Sin turno en atención', style: QhText.body.copyWith(color: c.textSecondary)),
            ]),
            const SizedBox(height: QhSpacing.s05),
            _Meter(waiting: waiting, serving: serving, empty: total == 0),
            const SizedBox(height: QhSpacing.s04),
            Row(children: [
              _Stat('En espera', '$waiting'),
              const SizedBox(width: QhSpacing.s07),
              _Stat('Atendiendo', '$serving'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.waiting, required this.serving, required this.empty});
  final int waiting;
  final int serving;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return SizedBox(
      height: 8,
      child: empty
          ? ColoredBox(color: c.borderSubtle, child: const SizedBox.expand())
          : Row(children: [
              if (serving > 0) Expanded(flex: serving, child: ColoredBox(color: c.stateServing, child: const SizedBox.expand())),
              if (serving > 0 && waiting > 0) const SizedBox(width: 2),
              if (waiting > 0) Expanded(flex: waiting, child: ColoredBox(color: c.stateWaiting, child: const SizedBox.expand())),
            ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: QhText.caption.copyWith(color: c.textSecondary)),
      Text(value, style: QhText.turn.copyWith(color: c.textPrimary)),
    ]);
  }
}
