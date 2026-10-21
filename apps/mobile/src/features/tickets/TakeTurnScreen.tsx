import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useNavigation, useRoute, type RouteProp } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { defaultQueuePrefix, formatHm, formatHmUtc, formatTurnNumber, trimSeconds, type Failure, friendlyError } from '@qhub/core';
import { inQueueTime, queueUtcOffsetMinutes, type Slot } from '@qhub/api-client';
import { AppBar, Button, Card, EmptyState, Icon, IconButton, Notice, OrgMark, Screen, Skeleton, Txt, useToast } from '@/shared/ui/kit';
import { DateSlotPicker, longDate, slotTime } from '@/shared/ui/DateSlotPicker';
import { useContainer } from '@/app/container';
import { useOrg, useOrgPrefixes, useOrgQueues, useQueueNow, useSchedule, useSlots } from '@/app/hooks';
import { orgLocation, orgMark } from '@/features/organizations/organizations';
import type { Nav, RootStackParamList } from '@/app/navigation';

type Step = 'choose' | 'schedule' | 'confirm' | 'done';

/** Tarjeta de elección (turno ahora / reservar cita) con ícono, título, descripción y chevron. */
function ChoiceCard({ icon, title, description, onPress, disabled }: { icon: 'ticket' | 'calendar'; title: string; description: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityState={{ disabled: !!disabled }} disabled={disabled} onPress={onPress} className={disabled ? 'opacity-60' : 'active:opacity-80'}>
      <Card>
        <View className="flex-row items-center gap-3">
          <Icon name={icon} size={20} color={disabled ? 'textDisabled' : 'link'} />
          <View className="flex-1"><Txt weight={600}>{title}</Txt><Txt variant="caption" color="textSecondary">{description}</Txt></View>
          {disabled ? null : <Icon name="chevron-right" />}
        </View>
      </Card>
    </Pressable>
  );
}

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
  const now = useQueueNow(organizationId, queueId).data;

  const [step, setStep] = useState<Step>('choose');
  const [reserve, setReserve] = useState(false);
  const [month, setMonth] = useState(() => { const n = new Date(); return new Date(n.getFullYear(), n.getMonth(), 1); });
  const [date, setDate] = useState<Date | null>(null);
  const [slot, setSlot] = useState<Slot | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<Failure | null>(null);
  const [created, setCreated] = useState<{ number: number } | null>(null);
  const slots = useSlots(organizationId, queueId, date);
  const offset = schedule.data ? queueUtcOffsetMinutes(schedule.data, slots.data ?? []) : null;

  async function submit() {
    setBusy(true); setError(null);
    const r = await gateway.tickets(organizationId).create(queueId, reserve ? slot?.start : undefined);
    setBusy(false);
    if (r.ok) {
      setCreated({ number: r.value.number });
      toast.show(`Listo: tu turno es ${formatTurnNumber(r.value.number, prefix)}.`);
      await Promise.all([qc.invalidateQueries({ queryKey: ['active-tickets'] }), qc.invalidateQueries({ queryKey: ['queue-now', organizationId, queueId] })]);
      setStep('done');
    } else {
      setError(r.failure);
      void qc.invalidateQueries({ queryKey: ['queue-now', organizationId, queueId] });
      if ((r.failure.kind === 'conflict' || r.failure.kind === 'validation') && reserve) {
        setSlot(null);
        await qc.invalidateQueries({ queryKey: ['slots', organizationId, queueId] });
        setStep('schedule');
      }
    }
  }

  const sch = schedule.data;

  const header = org ? (
    <View className="flex-row gap-3 items-center">
      <OrgMark text={orgMark(org.name)} />
      <View className="flex-1"><Txt weight={600}>{org.name}</Txt>{orgLocation(org) ? <Txt variant="caption" color="textSecondary">{orgLocation(org)}</Txt> : null}</View>
    </View>
  ) : null;

  const queueContext = (
    <Txt variant="h4">{`${prefix} · ${queue?.name ?? 'Cola'}`}</Txt>
  );

  /** Qué se le dice a la persona sobre sacar turno ahora: espera aproximada, o por qué no se puede. */
  const nowText = (): { text: string; disabled: boolean } => {
    if (!now) return { text: `Atiende de ${trimSeconds(sch!.opens)} a ${trimSeconds(sch!.closes)}. Te avisamos cuando se acerque tu turno.`, disabled: false };
    if (now.alreadyHasNow) return { text: 'Ya tienes un turno ahora en esta cola. Termínalo o cancélalo para sacar otro.', disabled: true };
    if (!now.open) return { text: `${now.reason ?? 'Ahora no hay atención.'} Puedes reservar una cita.`, disabled: true };
    const people = now.ahead === 0 ? 'No hay nadie delante' : now.ahead === 1 ? '1 persona delante' : `${now.ahead} personas delante`;
    return { text: `${people} · espera aproximada de ${now.waitMinutes ?? now.marginMinutes} min. Te avisamos cuando se acerque.`, disabled: false };
  };

  function renderBody() {
    if (step === 'done') {
      return (
        <EmptyState
          title="¡Listo!"
          message={created ? `Tu turno es ${formatTurnNumber(created.number, prefix)}.` : undefined}
          action={<Button label="Ver mi turno" icon="arrow-right" kind="accent" onPress={() => nav.navigate('Tabs', { screen: 'Turns' })} />}
        />
      );
    }
    if (!sch) return null;

    if (step === 'choose') {
      return (
        <ScrollView contentContainerClassName="gap-4 p-4">
          {header}
          {queueContext}
          {error ? <Notice kind={error.kind === 'conflict' ? 'warning' : 'error'} title={error.message} /> : null}
          <ChoiceCard icon="ticket" title="Turno ahora" description={nowText().text} disabled={nowText().disabled}
            onPress={() => { setReserve(false); setError(null); setStep('confirm'); }} />
          <ChoiceCard icon="calendar" title="Reservar cita" description={`Elige el día y la hora${now?.breaks.length ? ` (descanso ${now.breaks.map((b) => `${trimSeconds(b.from)}–${trimSeconds(b.to)}`).join(', ')})` : ''}. Puedes tener varias citas.`}
            onPress={() => { setReserve(true); setError(null); setStep('schedule'); }} />
        </ScrollView>
      );
    }

    if (step === 'schedule') {
      return (
        <ScrollView contentContainerClassName="gap-4 p-4">
          {header}
          {queueContext}
          {error ? <Notice kind={error.kind === 'conflict' ? 'warning' : 'error'} title={error.message} /> : null}
          <DateSlotPicker month={month} selectedDate={date} enabledWeekdays={sch.days} firstDate={new Date()} lastDate={new Date(Date.now() + sch.maxDaysAhead * 864e5)} slots={slots.data ?? []} selectedSlot={slot}
            loadingSlots={slots.isLoading} offsetMinutes={offset} formatLocal={formatHm} onMonthChange={setMonth}
            onDateChange={(d) => { setDate(d); setSlot(null); setError(null); }}
            onSlotChange={(s) => { setSlot(s); setError(null); setStep('confirm'); }} />
          {slots.isError ? <Notice kind="error" title={friendlyError(slots.error)} /> : null}
        </ScrollView>
      );
    }

    // step === 'confirm'
    const canSubmit = !busy && (!reserve || (slot !== null && date !== null)) && !!queue;
    return (
      <ScrollView contentContainerClassName="gap-4 p-4">
        {header}
        {error ? <Notice kind={error.kind === 'conflict' ? 'warning' : 'error'} title={error.message} /> : null}
        <Card>
          <View className="gap-2">
            <Txt variant="h4">{`${prefix} · ${queue?.name ?? 'Cola'}`}</Txt>
            {reserve ? (
              <>
                <View className="flex-row justify-between gap-3"><Txt color="textSecondary">Día</Txt><Txt weight={600}>{date ? longDate(date) : 'Elige un día'}</Txt></View>
                <View className="flex-row justify-between gap-3"><Txt color="textSecondary">Hora</Txt><Txt weight={600}>{slot ? slotTime(slot, offset, formatHm) : 'Elige una hora'}</Txt></View>
                <View className="flex-row justify-between gap-3"><Txt color="textSecondary">Cupos</Txt><Txt weight={600}>{slot ? String(slot.available) : '—'}</Txt></View>
              </>
            ) : (
              <Txt color="textSecondary">{nowText().text}</Txt>
            )}
          </View>
        </Card>
        {reserve ? <Txt variant="caption" color="textSecondary" className="text-center">Puedes cancelar tu reserva cuando quieras.</Txt> : null}
        <Button label={reserve ? 'Reservar cita' : 'Sacar turno ahora'} icon="arrow-right" kind="accent" block loading={busy} disabled={!canSubmit} onPress={() => void submit()} />
      </ScrollView>
    );
  }

  const back = () => {
    if (step === 'schedule' || (step === 'confirm' && !reserve)) { setStep('choose'); setError(null); return; }
    if (step === 'confirm' && reserve) { setStep('schedule'); setError(null); return; }
    nav.goBack();
  };

  return (
    <Screen>
      <AppBar title={queue?.name ?? 'Cola'} left={step === 'done' ? undefined : <IconButton icon="chevron-left" label="Atrás" onPress={back} />} />
      {schedule.isLoading ? <View className="p-4"><Skeleton height={200} /></View> : schedule.isError ? (
        <EmptyState title="No pudimos cargar esto" message={friendlyError(schedule.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void schedule.refetch()} />} />
      ) : renderBody()}
    </Screen>
  );
}
export { formatHmUtc, inQueueTime };
