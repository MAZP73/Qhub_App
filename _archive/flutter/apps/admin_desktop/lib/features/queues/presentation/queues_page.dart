import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_api_client/qhub_api_client.dart' as api show Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import 'queue_providers.dart';

class QueuesPage extends ConsumerStatefulWidget {
  const QueuesPage({super.key});
  @override
  ConsumerState<QueuesPage> createState() => _QueuesPageState();
}

class _QueuesPageState extends ConsumerState<QueuesPage> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final queues = ref.watch(queuesProvider);
    final limit = ref.watch(queueLimitProvider);
    final prefixes = ref.watch(queuePrefixesProvider).value ?? const {};
    final isAdmin = ref.watch(activeMembershipProvider)?.isAdmin ?? false;
    final org = ref.watch(activeMembershipProvider)?.organization.name;

    final canCreate = isAdmin && (limit.value?.available ?? 0) > 0;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead(
          title: 'Colas',
          breadcrumb: org,
          actions: [
            QhButton(label: 'Actualizar', kind: QhButtonKind.tertiary, onPressed: () {
              ref.invalidate(queuesProvider);
              ref.invalidate(queueLimitProvider);
            }),
            if (isAdmin)
              QhButton(label: 'Crear cola', icon: QhIcons.plus, onPressed: canCreate ? () => context.go('/colas/nueva') : null),
          ],
        ),
        AsyncBody<List<api.Queue>>(
          value: queues,
          onRetry: () => ref.invalidate(queuesProvider),
          builder: (all) {
            final active = all.where((q) => q.active).toList();
            final archived = all.where((q) => !q.active).toList();
            final shown = switch (_tab) { 1 => active, 2 => archived, _ => all };
            final l = limit.value;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Kpi(label: 'Colas activas', value: '${active.length}', hint: l == null ? null : 'de ${l.limit} permitidas')),
                const SizedBox(width: 1),
                Expanded(child: Kpi(label: 'Cupos de cola libres', value: '${l?.available ?? '—'}', hint: l?.available == 0 ? 'Archiva una cola para liberar un lugar' : null)),
              ]),
              if (l != null && l.available == 0 && isAdmin) ...[
                const SizedBox(height: QhSpacing.s05),
                QhNotice(
                  kind: QhNoticeKind.warning,
                  title: 'Llegaste al límite de colas (${l.limit}).',
                  message: 'Archiva una cola que ya no uses para crear otra.',
                ),
              ],
              const SizedBox(height: QhSpacing.s06),
              QhTabs(labels: ['Todas (${all.length})', 'Activas (${active.length})', 'Archivadas (${archived.length})'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
              const SizedBox(height: QhSpacing.s06),
              if (shown.isEmpty)
                SizedBox(
                  height: 320,
                  child: EmptyState(
                    title: all.isEmpty ? 'Crea tu primera cola' : 'No hay colas en esta vista',
                    message: all.isEmpty ? 'Define su horario y empieza a recibir turnos.' : null,
                    action: all.isEmpty && isAdmin ? QhButton(label: 'Crear cola', icon: QhIcons.plus, onPressed: () => context.go('/colas/nueva')) : null,
                  ),
                )
              else
                Wrap(spacing: QhSpacing.s05, runSpacing: QhSpacing.s05, children: [
                  for (final q in shown) _QueueCard(queue: q, prefix: prefixes[q.id] ?? defaultQueuePrefix(q.name), isAdmin: isAdmin),
                ]),
            ]);
          },
        ),
      ]),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({required this.queue, required this.prefix, required this.isAdmin});
  final api.Queue queue;
  final String prefix;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = queue.active ? ref.watch(queueStateProvider(queue.id)).value : null;
    return SizedBox(
      width: 360,
      child: Stack(children: [
        QueueTile(
          name: queue.name,
          subtitle: queue.active ? (queue.description ?? 'Prefijo $prefix') : 'Archivada',
          waiting: state?.waiting ?? 0,
          serving: state?.serving ?? 0,
          prefix: prefix,
          closed: !queue.active,
          onTap: () => context.go('/en-vivo?cola=${queue.id}'),
        ),
        if (isAdmin)
          Positioned(
            right: 8,
            bottom: 8,
            child: QhIconButton(icon: QhIcons.edit, label: 'Editar ${queue.name}', onPressed: () => context.go('/colas/${queue.id}'), size: 32),
          ),
        if (!queue.active)
          Positioned.fill(child: IgnorePointer(child: ColoredBox(color: context.qh.background.withValues(alpha: 0.0)))),
      ]),
    );
  }
}
