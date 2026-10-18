import 'package:flutter/material.dart';
import 'package:qhub_api_client/qhub_api_client.dart' show TicketStatus;
import 'package:qhub_core/qhub_core.dart';

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_icon.dart';

extension TicketStatusUi on TicketStatus {
  /// Nombres fijos del design system.
  String get label => switch (this) {
        TicketStatus.enEspera => 'En espera',
        TicketStatus.atendiendo => 'Atendiendo',
        TicketStatus.finalizado => 'Finalizado',
        TicketStatus.cancelado => 'Cancelado',
        TicketStatus.noShow => 'No-show',
      };

  QhIcons get icon => switch (this) {
        TicketStatus.enEspera => QhIcons.clock,
        TicketStatus.atendiendo => QhIcons.play,
        TicketStatus.finalizado => QhIcons.check,
        TicketStatus.cancelado => QhIcons.close,
        TicketStatus.noShow => QhIcons.noshow,
      };

  /// Relleno del badge (el texto encima es `textOnAccent`).
  Color fill(QhColors c) => switch (this) {
        TicketStatus.enEspera => c.stateWaiting,
        TicketStatus.atendiendo => c.stateServing,
        TicketStatus.finalizado => c.stateDone,
        TicketStatus.cancelado => c.stateCancelled,
        TicketStatus.noShow => c.stateNoshow,
      };

  /// Color cuando el estado es texto/ícono sobre superficie.
  Color text(QhColors c) => switch (this) {
        TicketStatus.enEspera => c.stateWaitingText,
        TicketStatus.atendiendo => c.stateServingText,
        TicketStatus.finalizado => c.stateDoneText,
        TicketStatus.cancelado => c.stateCancelledText,
        TicketStatus.noShow => c.stateNoshowText,
      };
}

/// Estado del turno: color + ícono + palabra, nunca solo color.
class TurnBadge extends StatelessWidget {
  const TurnBadge(this.status, {super.key});
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Semantics(
      label: 'Estado: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s03, vertical: QhSpacing.s01 + 2),
        decoration: BoxDecoration(color: status.fill(c), borderRadius: BorderRadius.circular(QhRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            QhIcon(status.icon, size: 14, color: c.textOnAccent),
            const SizedBox(width: QhSpacing.s02),
            Text(status.label, style: QhText.label.copyWith(color: c.textOnAccent)),
          ],
        ),
      ),
    );
  }
}

/// Número de turno en mono (`A-023`). `xl` para "Mi turno" y la vista en vivo.
class TurnNumber extends StatelessWidget {
  const TurnNumber({super.key, required this.number, this.prefix = 'A', this.xl = false, this.color});
  final int number;
  final String prefix;
  final bool xl;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        formatTurnNumber(number, prefix: prefix),
        style: (xl ? QhText.turnXl : QhText.turn).copyWith(color: color ?? context.qh.textPrimary),
      );
}
