import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/widgets.dart';
import '../domain/active_tickets.dart';
import 'providers.dart';

class MyTurnPage extends ConsumerWidget {
  const MyTurnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(activeTicketsProvider);
    return Column(children: [
      QhAppBar(title: 'Mi turno', actions: [
        QhIconButton(icon: QhIcons.user, label: 'Perfil', onPressed: () => context.push('/perfil')),
      ]),
      Expanded(
        child: tickets.when(
          loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Column(children: [Skeleton(height: 200), SizedBox(height: 16), Skeleton(height: 60)])),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(activeTicketsProvider)),
          data: (list) => RefreshIndicator(
            onRefresh: () => ref.read(activeTicketsProvider.notifier).refresh(),
            child: list.isEmpty
                ? LayoutBuilder(
                    builder: (_, box) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: box.maxHeight,
                        child: EmptyState(
                          title: 'No tienes turnos activos',
                          message: 'Busca una organización y saca un turno en segundos.',
                          action: QhButton(label: 'Explorar', icon: QhIcons.search, onPressed: () => context.go('/explorar')),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(QhSpacing.s05),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: QhSpacing.s05),
                    itemBuilder: (_, i) => TicketCard(ticket: list[i]),
                  ),
          ),
        ),
      ),
    ]);
  }
}

class TicketCard extends ConsumerWidget {
  const TicketCard({super.key, required this.ticket});
  final ActiveTicket ticket;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await qhConfirm(context,
        title: 'Cancelar turno',
        message: 'Se libera tu lugar en ${ticket.entry.queueName ?? 'la cola'}. Esta acción no se puede deshacer.',
        confirmLabel: 'Cancelar turno',
        cancelLabel: 'Volver');
    if (!ok || !context.mounted) return;
    final res = await ref.read(activeTicketsProvider.notifier).cancel(ticket);
    if (!context.mounted) return;
    res.when(ok: (_) => showToast(context, 'Cancelaste tu turno ${ticket.label}.'), err: (f) => showToast(context, f.message, error: true));
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    final res = await ref.read(activeTicketsProvider.notifier).postpone(ticket);
    if (!context.mounted) return;
    res.when(ok: (_) => showToast(context, 'Te pasamos al final de tu franja.'), err: (f) => showToast(context, f.message, error: true));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final t = ticket.ticket;
    final title = [ticket.entry.organizationName, ticket.entry.queueName].whereType<String>().join(' · ');
    return Semantics(
      container: true,
      label: 'Turno ${ticket.label}, ${t.status.label}, ${ticket.peopleAhead} personas delante',
      child: Container(
        decoration: BoxDecoration(color: c.layer01, border: Border.all(color: c.borderSubtle), borderRadius: BorderRadius.circular(QhRadius.md)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: c.brandInk,
            padding: const EdgeInsets.all(QhSpacing.s05),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: QhText.caption.copyWith(color: c.sidebarText), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const LiveIndicator(onInk: true),
              ]),
              const SizedBox(height: QhSpacing.s03),
              Text(ticket.label, style: QhText.turnXl.copyWith(color: Colors.white)),
              const SizedBox(height: QhSpacing.s03),
              TurnBadge(t.status),
            ]),
          ),
          if (ticket.isMyTurn)
            Padding(
              padding: const EdgeInsets.all(QhSpacing.s05),
              child: QhNotice(kind: QhNoticeKind.success, title: 'Es tu turno', message: 'Acércate a ${ticket.entry.queueName ?? 'la ventanilla'}.'),
            )
          else
            Row(children: [
              Expanded(child: _Metric(label: 'Personas delante', value: '${ticket.peopleAhead}')),
              Container(width: 1, height: 72, color: c.borderSubtle),
              Expanded(child: _Metric(label: 'Tiempo estimado', value: ticket.estimateMinutes == null ? '—' : '~${ticket.estimateMinutes} min')),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(QhSpacing.s05, QhSpacing.s03, QhSpacing.s05, QhSpacing.s05),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (t.scheduled)
                Text('Reservado para ${_when(t.slotStart, ticket.schedule)}', style: QhText.caption.copyWith(color: c.textSecondary))
              else
                Text('Turno inmediato · sacado a las ${formatHm(t.createdAt.toLocal())}', style: QhText.caption.copyWith(color: c.textSecondary)),
              const SizedBox(height: QhSpacing.s04),
              Row(children: [
                if (t.status == TicketStatus.enEspera)
                  Expanded(child: QhButton(label: 'Posponer', kind: QhButtonKind.tertiary, size: QhButtonSize.lg, onPressed: () => _postpone(context, ref))),
                if (t.status == TicketStatus.enEspera) const SizedBox(width: QhSpacing.s03),
                Expanded(child: QhButton(label: 'Cancelar', kind: QhButtonKind.ghost, size: QhButtonSize.lg, onPressed: () => _cancel(context, ref))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _when(DateTime start, Schedule? s) => '${start.toLocal().day}/${start.toLocal().month} a las ${formatHm(start.toLocal())}';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Padding(
      padding: const EdgeInsets.all(QhSpacing.s05),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: QhText.caption.copyWith(color: c.textSecondary)),
        Text(value, style: QhText.h2.copyWith(fontFamily: 'IBMPlexMono', fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
