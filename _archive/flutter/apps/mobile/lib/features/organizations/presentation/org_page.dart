import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../../tickets/presentation/providers.dart';

class OrgPage extends ConsumerWidget {
  const OrgPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final org = ref.watch(orgProvider(organizationId));
    final queues = ref.watch(orgQueuesProvider(organizationId));
    final prefixes = ref.watch(orgPrefixesProvider(organizationId)).value ?? const {};
    final fav = ref.watch(favoritesProvider).value?.contains(organizationId) ?? false;

    return Scaffold(
      body: Column(children: [
        QhAppBar(
          title: org.value?.name ?? 'Organización',
          leading: QhIconButton(icon: QhIcons.chevronLeft, label: 'Atrás', onPressed: () => context.pop()),
          actions: [
            QhButton(
              label: fav ? 'Quitar' : 'Favorita',
              kind: QhButtonKind.ghost,
              size: QhButtonSize.sm,
              onPressed: () async {
                await ref.read(organizationRepositoryProvider).setFavorite(organizationId, !fav);
                ref.invalidate(favoritesProvider);
              },
            ),
          ],
        ),
        Expanded(
          child: org.when(
            loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Skeleton(height: 120)),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(orgProvider(organizationId))),
            data: (o) => ListView(children: [
              Padding(
                padding: const EdgeInsets.all(QhSpacing.s05),
                child: Row(children: [
                  OrgMark(o.mark, size: 48),
                  const SizedBox(width: QhSpacing.s04),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.name, style: QhText.h4),
                      if (o.location.isNotEmpty) Text(o.location, style: QhText.caption.copyWith(color: c.textSecondary)),
                      if (o.phone != null) Text(o.phone!, style: QhText.caption.copyWith(color: c.textSecondary)),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(QhSpacing.s05, 0, QhSpacing.s05, QhSpacing.s03),
                child: Text('Colas abiertas', style: QhText.h4),
              ),
              queues.when(
                loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Skeleton(height: 64)),
                error: (e, _) => SizedBox(height: 300, child: ErrorView(error: e, onRetry: () => ref.invalidate(orgQueuesProvider(organizationId)))),
                data: (list) => list.isEmpty
                    ? const SizedBox(height: 280, child: EmptyState(title: 'Sin colas abiertas', message: 'Esta organización no tiene colas activas ahora.'))
                    : Column(children: [
                        for (final q in list)
                          Consumer(builder: (context, ref, _) {
                            final state = ref.watch(queueStateProvider((org: organizationId, queue: q.id))).value;
                            final prefix = prefixes[q.id] ?? defaultQueuePrefix(q.name);
                            return ListRow(
                              leading: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                color: c.layer02,
                                child: Text(prefix, style: QhText.turn.copyWith(color: c.textPrimary)),
                              ),
                              title: Text(q.name, style: QhText.body.copyWith(fontWeight: FontWeight.w600)),
                              subtitles: [
                                if (q.description != null && q.description!.isNotEmpty) q.description!,
                                state == null ? 'Consultando fila…' : '${state.waiting} en espera · ${state.serving} atendiendo',
                              ],
                              trailing: const QhIcon(QhIcons.chevronRight),
                              onTap: () => context.push('/org/$organizationId/cola/${q.id}'),
                            );
                          }),
                      ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
