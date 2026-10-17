import 'package:flutter/material.dart';
import 'package:qhub_api_client/qhub_api_client.dart' show Slot;
import 'package:qhub_core/qhub_core.dart';

import '../theme/qh_theme.dart';
import '../tokens/qh_tokens.g.dart';
import 'qh_icon.dart';
import 'qh_misc.dart';

/// Selector de día (calendario 7 columnas) y franja. El consumidor provee días habilitados y franjas.
class QhDateSlotPicker extends StatelessWidget {
  const QhDateSlotPicker({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.enabledWeekdays,
    required this.firstDate,
    required this.lastDate,
    required this.slots,
    required this.selectedSlot,
    required this.onDateChanged,
    required this.onMonthChanged,
    required this.onSlotChanged,
    this.loadingSlots = false,
    this.slotColumns = 3,
  });

  final DateTime month;
  final DateTime? selectedDate;
  final Set<int> enabledWeekdays; // ISO 1=lunes … 7=domingo
  final DateTime firstDate;
  final DateTime lastDate;
  final List<Slot> slots;
  final Slot? selectedSlot;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<Slot> onSlotChanged;
  final bool loadingSlots;
  final int slotColumns;

  static const _monthNames = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];
  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  bool _enabled(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(DateTime(firstDate.year, firstDate.month, firstDate.day)) &&
        !day.isAfter(DateTime(lastDate.year, lastDate.month, lastDate.day)) &&
        enabledWeekdays.contains(d.weekday);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime.now();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(
          tooltip: 'Mes anterior',
          onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)),
          icon: const QhIcon(QhIcons.chevronLeft, size: 20),
        ),
        Expanded(
          child: Text('${_monthNames[month.month - 1]} ${month.year}'.replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
              textAlign: TextAlign.center, style: QhText.h4),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)),
          icon: const QhIcon(QhIcons.chevronRight, size: 20),
        ),
      ]),
      Row(children: [
        for (final d in _dayLabels)
          Expanded(child: Center(child: Text(d, style: QhText.label.copyWith(color: c.textSecondary)))),
      ]),
      for (var r = 0; r < rows; r++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(child: Builder(builder: (_) {
              final n = r * 7 + col - lead + 1;
              if (n < 1 || n > daysInMonth) return const SizedBox(height: 40);
              final date = DateTime(month.year, month.month, n);
              final enabled = _enabled(date);
              final selected = selectedDate != null &&
                  selectedDate!.year == date.year && selectedDate!.month == date.month && selectedDate!.day == date.day;
              final isToday = today.year == date.year && today.month == date.month && today.day == date.day;
              return Semantics(
                button: true,
                enabled: enabled,
                selected: selected,
                label: '$n de ${_monthNames[date.month - 1]}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: enabled ? () => onDateChanged(date) : null,
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? c.interactive : null,
                      border: isToday && !selected ? Border(bottom: BorderSide(color: c.interactive, width: 2)) : null,
                    ),
                    child: Text('$n',
                        style: QhText.body.copyWith(
                            color: selected ? c.textOnColor : (enabled ? c.textPrimary : c.textDisabled))),
                  ),
                ),
              );
            })),
        ]),
      const SizedBox(height: QhSpacing.s05),
      if (selectedDate != null)
        Text(_longDate(selectedDate!), style: QhText.h4)
      else
        Text('Elige un día', style: QhText.body.copyWith(color: c.textSecondary)),
      const SizedBox(height: QhSpacing.s03),
      if (loadingSlots)
        const Skeleton(height: 48)
      else if (selectedDate != null && slots.isEmpty)
        Text('No hay franjas ese día.', style: QhText.body.copyWith(color: c.textSecondary))
      else
        GridView.count(
          crossAxisCount: slotColumns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: QhSpacing.s03,
          crossAxisSpacing: QhSpacing.s03,
          childAspectRatio: 2,
          children: [
            for (final s in slots)
              _SlotTile(slot: s, selected: selectedSlot?.start == s.start, onTap: s.isFull ? null : () => onSlotChanged(s)),
          ],
        ),
    ]);
  }

  static String _longDate(DateTime d) {
    const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final s = '${days[d.weekday - 1]} ${d.day} de ${_monthNames[d.month - 1]}';
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.selected, required this.onTap});
  final Slot slot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final full = slot.isFull;
    final fg = selected ? c.textOnColor : (full ? c.textDisabled : c.textPrimary);
    final sub = selected ? c.textOnColor : (full ? c.textDisabled : (slot.isLow ? c.stateWaitingText : c.textSecondary));
    return Semantics(
      button: true,
      enabled: !full,
      selected: selected,
      label: '${formatHm(slot.start.toLocal())}, ${full ? 'llena' : '${slot.available} cupos'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.interactive : (full ? c.layerSelected : c.layer01),
            border: Border.all(color: selected ? c.interactive : c.borderSubtle),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatHm(slot.start.toLocal()), style: QhText.code.copyWith(color: fg, fontWeight: FontWeight.w500)),
            Text(full ? 'Llena' : '${slot.available} cupos', style: QhText.caption.copyWith(color: sub)),
          ]),
        ),
      ),
    );
  }
}
