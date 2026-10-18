import { Pressable, View } from 'react-native';
import { formatHmUtc } from '@qhub/core';
import { inQueueTime, slotIsFull, slotIsLow, type Slot } from '@qhub/api-client';
import { cx, Icon, Skeleton, Txt } from './kit';

const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const DAYS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const LETTERS = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const isoWeekday = (d: Date) => ((d.getDay() + 6) % 7) + 1;
const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

export const longDate = (d: Date) => { const s = `${DAYS[isoWeekday(d) - 1]} ${d.getDate()} de ${MONTHS[d.getMonth()]}`; return s[0]!.toUpperCase() + s.slice(1); };
/** Hora de la franja en la zona de la cola (desfase en minutos). */
export const slotTime = (s: Slot, offsetMinutes: number | null, fallback: (d: Date) => string) => (offsetMinutes === null ? fallback(s.start) : formatHmUtc(inQueueTime(s.start, offsetMinutes)));

/** Selector de día (calendario de 7 columnas) y franja. El consumidor provee días habilitados y franjas. */
export function DateSlotPicker(p: {
  month: Date; selectedDate: Date | null; enabledWeekdays: readonly number[]; firstDate: Date; lastDate: Date; slots: readonly Slot[]; selectedSlot: Slot | null;
  loadingSlots?: boolean; offsetMinutes: number | null; formatLocal: (d: Date) => string;
  onDateChange: (d: Date) => void; onMonthChange: (d: Date) => void; onSlotChange: (s: Slot) => void;
}) {
  const first = new Date(p.month.getFullYear(), p.month.getMonth(), 1);
  const days = new Date(p.month.getFullYear(), p.month.getMonth() + 1, 0).getDate();
  const lead = isoWeekday(first) - 1;
  const rows = Math.ceil((lead + days) / 7);
  const enabled = (d: Date) => startOfDay(d) >= startOfDay(p.firstDate) && startOfDay(d) <= startOfDay(p.lastDate) && p.enabledWeekdays.includes(isoWeekday(d));
  const today = new Date();

  return (
    <View className="gap-2">
      <View className="flex-row items-center">
        <Pressable accessibilityRole="button" accessibilityLabel="Mes anterior" onPress={() => p.onMonthChange(new Date(p.month.getFullYear(), p.month.getMonth() - 1, 1))} className="p-2"><Icon name="chevron-left" size={20} /></Pressable>
        <Txt variant="h4" className="flex-1 text-center">{`${MONTHS[p.month.getMonth()]![0]!.toUpperCase()}${MONTHS[p.month.getMonth()]!.slice(1)} ${p.month.getFullYear()}`}</Txt>
        <Pressable accessibilityRole="button" accessibilityLabel="Mes siguiente" onPress={() => p.onMonthChange(new Date(p.month.getFullYear(), p.month.getMonth() + 1, 1))} className="p-2"><Icon name="chevron-right" size={20} /></Pressable>
      </View>
      <View className="flex-row">{LETTERS.map((l) => <View key={l} className="flex-1 items-center"><Txt variant="label" color="textSecondary">{l}</Txt></View>)}</View>
      {Array.from({ length: rows }, (_, r) => (
        <View key={r} className="flex-row">
          {Array.from({ length: 7 }, (_, col) => {
            const n = r * 7 + col - lead + 1;
            if (n < 1 || n > days) return <View key={col} className="h-10 flex-1" />;
            const date = new Date(p.month.getFullYear(), p.month.getMonth(), n);
            const ok = enabled(date);
            const sel = p.selectedDate !== null && sameDay(p.selectedDate, date);
            return (
              <Pressable key={col} disabled={!ok} accessibilityRole="button" accessibilityLabel={`${n} de ${MONTHS[date.getMonth()]}`} accessibilityState={{ disabled: !ok, selected: sel }} onPress={() => p.onDateChange(date)}
                className={cx('h-10 flex-1 items-center justify-center', sel && 'bg-interactive', sameDay(today, date) && !sel && 'border-b-2 border-interactive')}>
                <Txt color={sel ? 'textOnColor' : ok ? 'textPrimary' : 'textDisabled'}>{String(n)}</Txt>
              </Pressable>
            );
          })}
        </View>
      ))}
      <View className="h-2" />
      {p.selectedDate ? <Txt variant="h4">{longDate(p.selectedDate)}</Txt> : <Txt color="textSecondary">Elige un día</Txt>}
      {p.loadingSlots ? <Skeleton height={48} /> : p.selectedDate && p.slots.length === 0 ? <Txt color="textSecondary">No hay franjas ese día.</Txt> : (
        <View className="flex-row flex-wrap gap-2">
          {p.slots.map((s) => {
            const full = slotIsFull(s);
            const sel = p.selectedSlot?.start.getTime() === s.start.getTime();
            const time = slotTime(s, p.offsetMinutes, p.formatLocal);
            return (
              <Pressable key={s.start.toISOString()} disabled={full} accessibilityRole="button" accessibilityLabel={`${time}, ${full ? 'llena' : `${s.available} cupos`}`} accessibilityState={{ disabled: full, selected: sel }} onPress={() => p.onSlotChange(s)}
                className={cx('min-h-14 w-[31.5%] items-center justify-center rounded-sm border', sel ? 'border-interactive bg-interactive' : full ? 'border-border-subtle bg-layer-selected' : 'border-border-subtle bg-layer-01')}>
                <Txt variant="code" weight={500} color={sel ? 'textOnColor' : full ? 'textDisabled' : 'textPrimary'}>{time}</Txt>
                <Txt variant="caption" color={sel ? 'textOnColor' : full ? 'textDisabled' : slotIsLow(s) ? 'stateWaitingText' : 'textSecondary'}>{full ? 'Llena' : `${s.available} cupos`}</Txt>
              </Pressable>
            );
          })}
        </View>
      )}
    </View>
  );
}
