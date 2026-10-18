import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import 'providers.dart';

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _dayNames = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

class TakeTurnPage extends ConsumerStatefulWidget {
  const TakeTurnPage({super.key, required this.organizationId, required this.queueId});
  final String organizationId;
  final String queueId;

  @override
  ConsumerState<TakeTurnPage> createState() => _TakeTurnPageState();
}

class _TakeTurnPageState extends ConsumerState<TakeTurnPage> {
  var _reserve = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _date;
  Slot? _slot;
  var _busy = false;
  Failure? _error;

  ({String org, String queue}) get _key => (org: widget.organizationId, queue: widget.queueId);

  Future<void> _submit(Queue queue, String prefix) async {
    setState(() { _busy = true; _error = null; });
    final res = await ref.read(gatewayProvider).tickets(widget.organizationId).create(widget.queueId, slotStart: _reserve ? _slot?.start : null);
    if (!mounted) return;
    res.when(
      ok: (t) {
        ref.invalidate(activeTicketsProvider);
        showToast(context, 'Listo: tu turno es ${formatTurnNumber(t.number, prefix: prefix)}.');
        context.go('/turno');
      },
      err: (f) {
        setState(() { _busy = false; _error = f; });
        if (f is ConflictFailure && _date != null) {
          ref.invalidate(slotsProvider((org: widget.organizationId, queue: widget.queueId, date: _dateKey(_date!))));
          setState(() => _slot = null);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final queues = ref.watch(orgQueuesProvider(widget.organizationId));
    final org = ref.watch(orgProvider(widget.organizationId)).value;
    final prefixes = ref.watch(orgPrefixesProvider(widget.organizationId)).value ?? const {};
    final schedule = ref.watch(scheduleProvider(_key));
    final queue = queues.value?.where((q) => q.id == widget.queueId).firstOrNull;
    final prefix = prefixes[widget.queueId] ?? defaultQueuePrefix(queue?.name ?? '');
    final slotsAsync = _date == null ? null : ref.watch(slotsProvider((org: widget.organizationId, queue: widget.queueId, date: _dateKey(_date!))));
    final slots = slotsAsync?.value ?? const <Slot>[];
    final offset = schedule.value == null ? null : queueUtcOffset(schedule.value!, slots);

    final canSubmit = !_busy && (!_reserve || _slot != null);
    final cta = !_reserve
        ? 'Sacar turno ahora'
        : _slot == null
            ? 'Elige día y franja'
            : 'Reservar ${_dayNames[_date!.weekday - 1]} ${_date!.day}, ${formatHm(inQueueTime(_slot!.start, offset ?? Duration.zero))}';

    return Scaffold(
      body: Column(children: [
        QhAppBar(
          title: queue?.name ?? 'Cola',
          leading: QhIconButton(icon: QhIcons.chevronLeft, label: 'Atrás', onPressed: () => context.pop()),
        ),
        Expanded(
          child: schedule.when(
            loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Skeleton(height: 200)),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(scheduleProvider(_key))),
            data: (sch) => ListView(padding: const EdgeInsets.all(QhSpacing.s05), children: [
              if (org != null)
                Row(children: [
                  OrgMark(org.mark),
                  const SizedBox(width: QhSpacing.s04),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(org.name, style: QhText.body.copyWith(fontWeight: FontWeight.w600)),
                      if (org.location.isNotEmpty) Text(org.location, style: QhText.caption.copyWith(color: c.textSecondary)),
                    ]),
                  ),
                ]),
              const SizedBox(height: QhSpacing.s05),
              _Segmented(
                labels: const ['Turno ahora', 'Reservar franja'],
                icons: const [QhIcons.ticket, QhIcons.calendar],
                index: _reserve ? 1 : 0,
                onChanged: (i) => setState(() { _reserve = i == 1; _error = null; }),
              ),
              const SizedBox(height: QhSpacing.s05),
              if (_error != null) ...[
                QhNotice(kind: _error is ConflictFailure ? QhNoticeKind.warning : QhNoticeKind.error, title: _error!.message),
                const SizedBox(height: QhSpacing.s05),
              ],
              if (!_reserve) ...[
                Text('Atiende de ${trimSeconds(sch.opens)} a ${trimSeconds(sch.closes)}. Te avisamos cuando se acerque tu turno.',
                    style: QhText.bodyLong.copyWith(color: c.textSecondary)),
              ] else
                QhDateSlotPicker(
                  month: _month,
                  selectedDate: _date,
                  enabledWeekdays: sch.days.toSet(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(Duration(days: sch.maxDaysAhead)),
                  slots: slots,
                  selectedSlot: _slot,
                  loadingSlots: slotsAsync?.isLoading ?? false,
                  displayOffset: offset,
                  onMonthChanged: (m) => setState(() => _month = m),
                  onDateChanged: (d) => setState(() { _date = d; _slot = null; _error = null; }),
                  onSlotChanged: (s) => setState(() => _slot = s),
                ),
              if (_reserve && slotsAsync?.hasError == true) ...[
                const SizedBox(height: QhSpacing.s04),
                QhNotice(kind: QhNoticeKind.error, title: (slotsAsync!.error is Failure) ? (slotsAsync.error as Failure).message : 'No pudimos cargar las franjas.'),
              ],
            ]),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(QhSpacing.s05),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_reserve) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Puedes cancelar tu reserva cuando quieras.', style: QhText.caption.copyWith(color: c.textSecondary))),
              QhButton(
                label: cta,
                icon: QhIcons.arrowRight,
                size: QhButtonSize.lg,
                kind: QhButtonKind.accent,
                block: true,
                loading: _busy,
                onPressed: canSubmit && queue != null ? () => _submit(queue, prefix) : null,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.labels, required this.icons, required this.index, required this.onChanged});
  final List<String> labels;
  final List<QhIcons> icons;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Container(
      decoration: BoxDecoration(color: c.layer02, borderRadius: BorderRadius.circular(QhRadius.sm)),
      padding: const EdgeInsets.all(2),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              label: labels[i],
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  height: QhSize.controlLg - 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i == index ? c.interactive : null, borderRadius: BorderRadius.circular(QhRadius.sm)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    QhIcon(icons[i], color: i == index ? c.textOnColor : c.textPrimary),
                    const SizedBox(width: QhSpacing.s03),
                    Flexible(child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: QhText.body.copyWith(color: i == index ? c.textOnColor : c.textPrimary, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
