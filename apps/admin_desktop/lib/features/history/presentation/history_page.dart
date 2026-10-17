import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../../queues/presentation/queue_providers.dart';
import '../domain/history.dart';

final historyDaysProvider = NotifierProvider<_Days, int>(_Days.new);

class _Days extends Notifier<int> {
  @override
  int build() => 1;
  void set(int d) => state = d;
}

final historyProvider = FutureProvider.autoDispose<List<Ticket>>((ref) async {
  final days = ref.watch(historyDaysProvider);
  final res = await loadHistory(ref.watch(ticketRepositoryProvider), days: days, today: DateTime.now());
  return res.getOrThrow();
});

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  static const _pageSize = 25;
  var _page = 0;
  var _query = '';
  TicketStatus? _status;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final days = ref.watch(historyDaysProvider);
    final history = ref.watch(historyProvider);
    final Map<String, String> queues = {for (final q in ref.watch(queuesProvider).value ?? const []) q.id: q.name};
    final prefixes = ref.watch(queuePrefixesProvider).value ?? const {};
    String prefixOf(String qid) => prefixes[qid] ?? defaultQueuePrefix(queues[qid] ?? '');

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHead(
          title: 'Historial y métricas',
          breadcrumb: 'Operación',
          actions: [
            QhTabs(
              labels: const ['Hoy', '7 días', '30 días'],
              index: switch (days) { 1 => 0, 7 => 1, _ => 2 },
              onChanged: (i) {
                ref.read(historyDaysProvider.notifier).set(const [1, 7, 30][i]);
                setState(() => _page = 0);
              },
            ),
          ],
        ),
        AsyncBody<List<Ticket>>(
          value: history,
          onRetry: () => ref.invalidate(historyProvider),
          builder: (all) {
            final stats = computeStats(all);
            final q = _query.trim().toLowerCase();
            final filtered = all.where((t) {
              if (_status != null && t.status != _status) return false;
              if (q.isEmpty) return true;
              final label = formatTurnNumber(t.number, prefix: prefixOf(t.queueId)).toLowerCase();
              return label.contains(q) || (queues[t.queueId] ?? '').toLowerCase().contains(q) || t.userId.toLowerCase().contains(q);
            }).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final pages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
            final page = _page.clamp(0, pages - 1);
            final rows = filtered.skip(page * _pageSize).take(_pageSize).toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Kpi(label: 'Turnos atendidos', value: '${stats.attended}', hint: 'de ${stats.total} en el periodo')),
                const SizedBox(width: 1),
                Expanded(child: Kpi(label: 'Espera promedio', value: formatDuration(stats.avgWait))),
                const SizedBox(width: 1),
                Expanded(child: Kpi(label: 'Atención promedio', value: formatDuration(stats.avgService))),
                const SizedBox(width: 1),
                Expanded(child: Kpi(label: 'Tasa de no-show', value: formatPercent(stats.noShowRate), hint: '${stats.noShow} no-show · ${stats.cancelled} cancelados')),
              ]),
              const SizedBox(height: QhSpacing.s05),
              Row(children: [
                SizedBox(width: 320, child: QhTextField(label: 'Buscar por turno, cola o cliente', onChanged: (v) => setState(() { _query = v; _page = 0; }))),
                const SizedBox(width: QhSpacing.s05),
                SizedBox(
                  width: 220,
                  child: QhSelect<TicketStatus?>(
                    label: 'Estado',
                    value: _status,
                    items: <TicketStatus?, String>{null: 'Todos', for (final s in TicketStatus.values) s: s.label},
                    onChanged: (v) => setState(() { _status = v; _page = 0; }),
                  ),
                ),
                const Spacer(),
                QhButton(
                  label: 'Copiar CSV',
                  icon: QhIcons.copy,
                  onPressed: filtered.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: ticketsToCsv(filtered, queueNames: queues, prefixes: {for (final k in queues.keys) k: prefixOf(k)})));
                          if (context.mounted) showToast(context, 'Copiamos ${filtered.length} turnos como CSV.');
                        },
                ),
              ]),
              const SizedBox(height: QhSpacing.s05),
              Panel(
                padding: EdgeInsets.zero,
                child: filtered.isEmpty
                    ? const SizedBox(height: 220, child: EmptyState(title: 'Sin turnos', message: 'No hay turnos para este periodo o filtro.'))
                    : Column(children: [
                        _HeaderRow(),
                        for (final t in rows)
                          Container(
                            height: QhSize.rowHeight,
                            padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.borderSubtle))),
                            child: Row(children: [
                              SizedBox(width: 100, child: TurnNumber(number: t.number, prefix: prefixOf(t.queueId))),
                              Expanded(flex: 2, child: Text(queues[t.queueId] ?? '—', overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 2, child: Text(t.userId, style: QhText.codeSm, overflow: TextOverflow.ellipsis)),
                              SizedBox(width: 90, child: Text(formatHm(t.createdAt.toLocal()), style: QhText.code)),
                              Expanded(child: Text(t.agentId ?? '—', overflow: TextOverflow.ellipsis)),
                              SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: TurnBadge(t.status))),
                              SizedBox(width: 90, child: Text(t.calledAt != null && t.finishedAt != null ? formatDuration(t.finishedAt!.difference(t.calledAt!)) : '—', style: QhText.code, textAlign: TextAlign.right)),
                            ]),
                          ),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.borderSubtle))),
                          child: Row(children: [
                            Expanded(child: Text('${page * _pageSize + 1}–${page * _pageSize + rows.length} de ${filtered.length} turnos', style: QhText.caption)),
                            Text('Página ${page + 1} de $pages', style: QhText.caption),
                            QhIconButton(icon: QhIcons.chevronLeft, label: 'Anterior', onPressed: page == 0 ? null : () => setState(() => _page = page - 1), size: 36),
                            QhIconButton(icon: QhIcons.chevronRight, label: 'Siguiente', onPressed: page >= pages - 1 ? null : () => setState(() => _page = page + 1), size: 36),
                          ]),
                        ),
                      ]),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    TextStyle s = QhText.label.copyWith(color: c.textSecondary);
    return Container(
      height: 40,
      color: c.layer02,
      padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
      child: Row(children: [
        SizedBox(width: 100, child: Text('Turno', style: s)),
        Expanded(flex: 2, child: Text('Cola', style: s)),
        Expanded(flex: 2, child: Text('Cliente', style: s)),
        SizedBox(width: 90, child: Text('Llegada', style: s)),
        Expanded(child: Text('Atendió', style: s)),
        SizedBox(width: 130, child: Text('Estado', style: s)),
        SizedBox(width: 90, child: Text('Duración', style: s, textAlign: TextAlign.right)),
      ]),
    );
  }
}
