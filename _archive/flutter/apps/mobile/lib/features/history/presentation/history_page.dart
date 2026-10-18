import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/widgets.dart';
import '../../tickets/presentation/providers.dart';
import '../domain/history.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final async = ref.watch(historyEntriesProvider);
    return Column(children: [
      const QhAppBar(title: 'Historial'),
      Expanded(
        child: async.when(
          loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Skeleton(height: 64)),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(historyEntriesProvider)),
          data: (entries) {
            if (entries.isEmpty) return const EmptyState(title: 'Aún no tienes turnos', message: 'Tus turnos pasados aparecerán aquí.');
            final groups = groupByDay(entries);
            final now = DateTime.now();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(historyEntriesProvider),
              child: ListView(children: [
                for (final g in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(QhSpacing.s05, QhSpacing.s05, QhSpacing.s05, QhSpacing.s02),
                    child: Text(dayLabel(g.key, now), style: QhText.label.copyWith(color: c.textSecondary)),
                  ),
                  for (final e in g.value)
                    ListRow(
                      leading: OrgMark((e.organizationName ?? '?').substring(0, 1).toUpperCase(), size: 36),
                      title: Row(children: [
                        Text(formatTurnNumber(e.number, prefix: defaultQueuePrefix(e.queueName ?? '')), style: QhText.turn.copyWith(color: c.textPrimary)),
                        const SizedBox(width: QhSpacing.s03),
                        Flexible(child: Text(e.queueName ?? '', overflow: TextOverflow.ellipsis, style: QhText.body)),
                      ]),
                      subtitles: [e.organizationName ?? ''],
                      trailing: TurnBadge(e.status),
                    ),
                ],
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
