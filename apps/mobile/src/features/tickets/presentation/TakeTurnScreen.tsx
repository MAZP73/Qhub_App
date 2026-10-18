import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { useNavigation, useRoute, type RouteProp } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { defaultQueuePrefix, formatHm, formatHmUtc, formatTurnNumber, trimSeconds, type Failure, friendlyError } from '@qhub/core';
import { inQueueTime, queueUtcOffsetMinutes, type Slot } from '@qhub/api-client';
import { AppBar, Button, EmptyState, IconButton, Notice, OrgMark, Screen, Segmented, Skeleton, Txt, useToast } from '@/shared/ui/kit';
import { DateSlotPicker, slotTime } from '@/shared/ui/DateSlotPicker';
import { useContainer } from '@/app/container';
import { useOrg, useOrgPrefixes, useOrgQueues, useSchedule, useSlots } from '@/app/hooks';
import { orgLocation, orgMark } from '@/features/organizations/domain/organizations';
import type { Nav, RootStackParamList } from '@/app/navigation';

const DAYS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const isoWeekday = (d: Date) => ((d.getDay() + 6) % 7) + 1;

export function TakeTurnScreen() {
  const nav = useNavigation<Nav>();
  const { organizationId, queueId } = useRoute<RouteProp<RootStackParamList, 'TakeTurn'>>().params;
  const { gateway } = useContainer();
  const qc = useQueryClient();
  const toast = useToast();
  const org = useOrg(organizationId).data;
  const queue = useOrgQueues(organizationId).data?.find((q) => q.id === queueId);
  const prefix = useOrgPrefixes(organizationId).data?.[queueId] ?? defaultQueuePrefix(queue?.name ?? '');
  const schedule = useSchedule(organizationId, queueId);

  const [reserve, setReserve] = useState(false);
  const [month, setMonth] = useState(() => { const n = new Date(); return new Date(n.getFullYear(), n.getMonth(), 1); });
  const [date, setDate] = useState<Date | null>(null);
  const [slot, setSlot] = useState<Slot | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<Failure | null>(null);
  const slots = useSlots(organizationId, queueId, date);
  const offset = schedule.data ? queueUtcOffsetMinutes(schedule.data, slots.data ?? []) : null;

  async function submit() {
    setBusy(true); setError(null);
    const r = await gateway.tickets(organizationId).create(queueId, reserve ? slot?.start : undefined);
    setBusy(false);
    if (r.ok) {
      toast.show(`Listo: tu turno es ${formatTurnNumber(r.value.number, prefix)}.`);
      await qc.invalidateQueries({ queryKey: ['active-tickets'] });
      nav.navigate('Tabs', { screen: 'MyTurn' });
    } else {
      setError(r.failure);
      if (r.failure.kind === 'conflict') { setSlot(null); await qc.invalidateQueries({ queryKey: ['slots', organizationId, queueId] }); }
    }
  }

  const sch = schedule.data;
  const cta = !reserve ? 'Sacar turno ahora' : !slot || !date ? 'Elige día y franja' : `Reservar ${DAYS[isoWeekday(date) - 1]} ${date.getDate()}, ${slotTime(slot, offset, formatHm)}`;
  const canSubmit = !busy && (!reserve || slot !== null) && !!queue;

  return (
    <Screen>
      <AppBar title={queue?.name ?? 'Cola'} left={<IconButton icon="chevron-left" label="Atrás" onPress={() => nav.goBack()} />} />
      {schedule.isLoading ? <View className="p-4"><Skeleton height={200} /></View> : schedule.isError ? (
        <EmptyState title="No pudimos cargar esto" message={friendlyError(schedule.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void schedule.refetch()} />} />
      ) : sch ? (
        <ScrollView contentContainerClassName="gap-4 p-4">
          {org && (
            <View className="flex-row gap-3 items-center">
              <OrgMark text={orgMark(org.name)} />
              <View className="flex-1"><Txt weight={600}>{org.name}</Txt>{orgLocation(org) ? <Txt variant="caption" color="textSecondary">{orgLocation(org)}</Txt> : null}</View>
            </View>
          )}
          <Segmented labels={['Turno ahora', 'Reservar franja']} icons={['ticket', 'calendar']} index={reserve ? 1 : 0} onChange={(i) => { setReserve(i === 1); setError(null); }} />
          {error ? <Notice kind={error.kind === 'conflict' ? 'warning' : 'error'} title={error.message} /> : null}
          {!reserve ? (
            <Txt variant="bodyLong" color="textSecondary">{`Atiende de ${trimSeconds(sch.opens)} a ${trimSeconds(sch.closes)}. Te avisamos cuando se acerque tu turno.`}</Txt>
          ) : (
            <DateSlotPicker month={month} selectedDate={date} enabledWeekdays={sch.days} firstDate={new Date()} lastDate={new Date(Date.now() + sch.maxDaysAhead * 864e5)} slots={slots.data ?? []} selectedSlot={slot}
              loadingSlots={slots.isLoading} offsetMinutes={offset} formatLocal={formatHm} onMonthChange={setMonth} onDateChange={(d) => { setDate(d); setSlot(null); setError(null); }} onSlotChange={setSlot} />
          )}
          {reserve && slots.isError ? <Notice kind="error" title={friendlyError(slots.error)} /> : null}
        </ScrollView>
      ) : null}
      <View className="p-4 gap-2">
        {reserve ? <Txt variant="caption" color="textSecondary" className="text-center">Puedes cancelar tu reserva cuando quieras.</Txt> : null}
        <Button label={cta} icon="arrow-right" kind="accent" block loading={busy} disabled={!canSubmit} onPress={() => void submit()} />
      </View>
    </Screen>
  );
}
export { formatHmUtc, inQueueTime };
