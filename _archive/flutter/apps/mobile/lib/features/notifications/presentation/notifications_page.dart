import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/widgets.dart';
import '../../history/domain/history.dart';
import '../../tickets/presentation/providers.dart';

/// Ícono y color por tipo de aviso (design: Avisos).
(QhIcons, Color Function(QhColors)) styleOf(String? kind) => switch (kind) {
      'turno_llamado' => (QhIcons.call, (c) => c.link),
      'turno_pospuesto' => (QhIcons.clock, (c) => c.stateWaitingText),
      'turno_no_show' => (QhIcons.noshow, (c) => c.stateNoshowText),
      'recordatorio' => (QhIcons.bell, (c) => c.stateWaitingText),
      _ => (QhIcons.info, (c) => c.supportInfo),
    };

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final async = ref.watch(notificationsProvider);
    final unread = async.value?.where((n) => !n.notification.read).length ?? 0;

    return Column(children: [
      QhAppBar(title: 'Avisos', actions: [
        QhButton(label: 'Marcar leídas', kind: QhButtonKind.ghost, size: QhButtonSize.sm, onPressed: unread == 0 ? null : () => ref.read(notificationsProvider.notifier).markAllRead()),
      ]),
      Align(alignment: Alignment.centerLeft, child: QhTabs(labels: ['Todas', 'Sin leer${unread > 0 ? ' ($unread)' : ''}'], index: _tab, onChanged: (i) => setState(() => _tab = i))),
      Expanded(
        child: async.when(
          loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Skeleton(height: 64)),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
          data: (all) {
            final list = _tab == 1 ? all.where((n) => !n.notification.read).toList() : all;
            if (list.isEmpty) {
              return EmptyState(title: _tab == 1 ? 'Estás al día' : 'Sin avisos todavía', message: 'Te avisaremos cuando se acerque tu turno.');
            }
            final now = DateTime.now();
            return RefreshIndicator(
              onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
              child: ListView(children: [
                for (final entry in groupByDay(list.map((n) => _AsEntry(n))).entries.map((e) => (e.key, e.value.cast<_AsEntry>()))) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(QhSpacing.s05, QhSpacing.s05, QhSpacing.s05, QhSpacing.s02),
                    child: Text(dayLabel(entry.$1, now), style: QhText.label.copyWith(color: c.textSecondary)),
                  ),
                  for (final item in entry.$2) _Row(item.n),
                ],
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

/// Adaptador mínimo para reutilizar `groupByDay` con avisos.
class _AsEntry extends HistoryEntry {
  _AsEntry(this.n)
      : super(
          ticketId: n.notification.id,
          organizationId: n.organizationId,
          queueId: '',
          number: 0,
          status: TicketStatus.enEspera,
          createdAt: n.notification.createdAt,
        );
  final OrgNotification n;
}

class _Row extends ConsumerWidget {
  const _Row(this.n);
  final OrgNotification n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final (icon, color) = styleOf(n.notification.kind);
    final unread = !n.notification.read;
    return ListRow(
      highlighted: unread,
      leading: QhIcon(icon, size: 20, color: color(c)),
      title: Text(n.notification.message, style: QhText.body.copyWith(fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: c.textPrimary)),
      subtitles: [n.organizationName],
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(formatHm(n.notification.createdAt.toLocal()), style: QhText.caption.copyWith(color: c.textSecondary)),
        if (unread) ...[
          const SizedBox(width: 8),
          Semantics(label: 'No leída', child: Container(width: 8, height: 8, color: c.interactive)),
        ],
      ]),
      onTap: unread ? () => ref.read(notificationsProvider.notifier).markRead(n) : null,
    );
  }
}
