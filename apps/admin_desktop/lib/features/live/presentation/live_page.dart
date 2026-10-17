import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/widgets.dart';
import '../../queues/presentation/queue_providers.dart';
import 'live_controller.dart';

class LivePage extends ConsumerWidget {
  const LivePage({super.key, this.initialQueueId});
  final String? initialQueueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queues = ref.watch(queuesProvider);
    return AsyncBody(
      value: queues,
      onRetry: () => ref.invalidate(queuesProvider),
      builder: (all) {
        final active = all.where((q) => q.active).toList();
        if (active.isEmpty) {
          return const EmptyState(title: 'No hay colas activas', message: 'Crea una cola para ver su fila en vivo.');
        }
        final selected = active.firstWhere((q) => q.id == initialQueueId, orElse: () => active.first);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHead(title: 'En vivo', breadcrumb: 'Operación'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final q in active)
                Padding(
                  padding: const EdgeInsets.only(right: QhSpacing.s03),
                  child: QhButton(
                    label: q.name,
                    kind: q.id == selected.id ? QhButtonKind.primary : QhButtonKind.secondary,
                    size: QhButtonSize.sm,
                    onPressed: () => context.go('/en-vivo?cola=${q.id}'),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: QhSpacing.s06),
          Expanded(child: LiveBoard(key: ValueKey(selected.id), queueId: selected.id, queueName: selected.name)),
        ]);
      },
    );
  }
}

class LiveBoard extends ConsumerWidget {
  const LiveBoard({super.key, required this.queueId, required this.queueName});
  final String queueId;
  final String queueName;

  Future<void> _run(BuildContext context, Future<Result<Ticket>?> Function() action, String ok) async {
    final res = await action();
    if (!context.mounted || res == null) return;
    res.when(ok: (_) => showToast(context, ok), err: (f) => showToast(context, f.message, error: true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final board = ref.watch(liveBoardProvider(queueId));
    final ctl = ref.read(liveBoardProvider(queueId).notifier);
    final prefix = ref.watch(queuePrefixesProvider).value?[queueId] ?? defaultQueuePrefix(queueName);

    if (board.loading && board.tickets.isEmpty) return const SingleChildScrollView(child: Skeleton(height: 220));
    if (board.error != null && board.tickets.isEmpty) return ErrorView(error: board.error!, onRetry: ctl.load);

    final serving = board.serving;
    final waiting = board.waiting;
    final next = board.next;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 2,
            child: Container(
              color: c.brandInk,
              padding: const EdgeInsets.all(QhSpacing.s06),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(queueName, style: QhText.h3.copyWith(color: Colors.white))),
                  LiveIndicator(live: board.isLive, onInk: true),
                ]),
                const SizedBox(height: QhSpacing.s05),
                Text('Atendiendo ahora', style: QhText.caption.copyWith(color: c.sidebarText)),
                if (serving.isEmpty)
                  Text('—', style: QhText.turnXl.copyWith(color: c.sidebarText))
                else
                  for (final t in serving)
                    Padding(
                      padding: const EdgeInsets.only(bottom: QhSpacing.s03),
                      child: Row(children: [
                        TurnNumber(number: t.number, prefix: prefix, xl: serving.length == 1, color: Colors.white),
                        const SizedBox(width: QhSpacing.s05),
                        QhButton(
                          label: 'Finalizar',
                          icon: QhIcons.check,
                          kind: QhButtonKind.accent,
                          loading: board.busyTicketId == t.id,
                          onPressed: board.busyTicketId != null ? null : () => _run(context, () => ctl.finish(t), 'Turno ${formatTurnNumber(t.number, prefix: prefix)} finalizado.'),
                        ),
                        const SizedBox(width: QhSpacing.s03),
                        QhButton(
                          label: 'No-show',
                          icon: QhIcons.noshow,
                          kind: QhButtonKind.danger,
                          onPressed: board.busyTicketId != null
                              ? null
                              : () async {
                                  final ok = await qhConfirm(context,
                                      title: 'Marcar no-show',
                                      message: 'El turno ${formatTurnNumber(t.number, prefix: prefix)} se marcará como no presentado. Esta acción no se puede deshacer.',
                                      confirmLabel: 'Marcar no-show');
                                  if (ok && context.mounted) await _run(context, () => ctl.noShow(t), 'Marcado como no-show.');
                                },
                        ),
                      ]),
                    ),
                const SizedBox(height: QhSpacing.s05),
                QhButton(
                  label: next == null ? 'No hay turnos en espera' : 'Llamar siguiente · ${formatTurnNumber(next.number, prefix: prefix)}',
                  icon: QhIcons.call,
                  size: QhButtonSize.lg,
                  loading: board.busyTicketId == next?.id,
                  onPressed: next == null || board.busyTicketId != null ? null : () => _run(context, ctl.callNext, 'Llamaste a ${formatTurnNumber(next.number, prefix: prefix)}.'),
                ),
              ]),
            ),
          ),
          const SizedBox(width: QhSpacing.s05),
          Expanded(
            child: Column(children: [
              Kpi(label: 'En espera', value: '${waiting.length}'),
              const SizedBox(height: 1),
              Kpi(label: 'Atendiendo', value: '${serving.length}'),
              const SizedBox(height: 1),
              Kpi(label: 'Atendidos hoy', value: '${board.tickets.where((t) => t.status == TicketStatus.finalizado).length}'),
            ]),
          ),
        ]),
        if (board.error != null) ...[
          const SizedBox(height: QhSpacing.s05),
          QhNotice(kind: QhNoticeKind.warning, title: board.error!.message),
        ],
        const SizedBox(height: QhSpacing.s06),
        Panel(
          title: 'Fila (${waiting.length})',
          padding: EdgeInsets.zero,
          child: waiting.isEmpty
              ? const SizedBox(height: 160, child: EmptyState(title: 'Nadie en espera', message: 'Los turnos nuevos aparecerán aquí al instante.'))
              : Column(children: [
                  for (final t in waiting)
                    Container(
                      height: QhSize.rowHeight,
                      padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.borderSubtle))),
                      child: Row(children: [
                        SizedBox(width: 96, child: TurnNumber(number: t.number, prefix: prefix)),
                        SizedBox(width: 90, child: Text(formatHm(t.slotStart.toLocal()), style: QhText.code)),
                        Expanded(child: Text(t.scheduled ? 'Reservado' : 'Turno inmediato', style: QhText.body.copyWith(color: c.textSecondary))),
                        Expanded(child: Text(t.userId, style: QhText.codeSm.copyWith(color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                        const TurnBadge(TicketStatus.enEspera),
                        const SizedBox(width: QhSpacing.s04),
                        QhButton(
                          label: 'Llamar',
                          size: QhButtonSize.sm,
                          kind: QhButtonKind.tertiary,
                          onPressed: board.busyTicketId != null ? null : () => _run(context, () => ctl.call(t), 'Llamaste a ${formatTurnNumber(t.number, prefix: prefix)}.'),
                        ),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}
