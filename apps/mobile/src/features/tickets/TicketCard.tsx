import { useState } from 'react';
import { View } from 'react-native';
import { useQueryClient } from '@tanstack/react-query';
import { formatHm } from '@qhub/core';
import { Button, ConfirmModal, LiveIndicator, Notice, ProgressBar, TurnBadge, Txt, useToast } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { activeLabel, isMyTurn, type ActiveTicket } from './active-tickets';

/** Tarjeta de un turno vigente: número grande, estado, personas delante, espera estimada y acciones. */
export function TicketCard({ item }: { item: ActiveTicket }) {
  const { gateway } = useContainer();
  const qc = useQueryClient();
  const toast = useToast();
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const t = item.ticket;
  const title = [item.entry.organizationName, item.entry.queueName].filter(Boolean).join(' · ');

  async function run(kind: 'cancel' | 'postpone') {
    setBusy(true);
    const repo = gateway.tickets(item.entry.organizationId);
    const r = kind === 'cancel' ? await repo.cancel(t.id) : await repo.postpone(t.id);
    setBusy(false);
    if (r.ok) { toast.show(kind === 'cancel' ? `Cancelaste tu turno ${activeLabel(item)}.` : 'Te pasamos al final de tu franja.'); await qc.invalidateQueries({ queryKey: ['active-tickets'] }); }
    else toast.show(r.failure.message, { error: true });
  }

  return (
    <View accessible accessibilityLabel={`Turno ${activeLabel(item)}, ${t.status}, ${item.peopleAhead} personas delante`} className="bg-layer-01 border border-border-subtle rounded-md overflow-hidden">
      <View className="bg-brand-ink p-4 gap-2">
        <View className="flex-row justify-between"><Txt variant="caption" color="sidebarText" className="flex-1" numberOfLines={1}>{title}</Txt><LiveIndicator onInk /></View>
        <Txt variant="turnXl" color="sidebarTextActive">{activeLabel(item)}</Txt>
        <TurnBadge status={t.status} />
      </View>
      {isMyTurn(item) ? (
        <View className="p-4"><Notice kind="success" title="Es tu turno" message={`Acércate a ${item.entry.queueName ?? 'la ventanilla'}.`} /></View>
      ) : (
        <View>
          <View className="flex-row">
            <Metric label="Personas delante" value={String(item.peopleAhead)} />
            <View className="w-[1px] bg-border-subtle" />
            <Metric label="Tiempo estimado" value={item.estimateMinutes === null ? '—' : `~${item.estimateMinutes} min`} />
          </View>
          <View className="px-4 pb-3"><ProgressBar value={1 / (item.peopleAhead + 1)} label="Qué tan cerca está tu turno" /></View>
        </View>
      )}
      <View className="p-4 pt-2 gap-3">
        <Txt variant="caption" color="textSecondary">{t.scheduled ? `Reservado para ${t.slotStart.getDate()}/${t.slotStart.getMonth() + 1} a las ${formatHm(t.slotStart)}` : `Turno inmediato · sacado a las ${formatHm(t.createdAt)}`}</Txt>
        <View className="flex-row gap-2">
          {t.status === 'en_espera' && <View className="flex-1"><Button label="Posponer" kind="tertiary" block loading={busy} onPress={() => void run('postpone')} /></View>}
          <View className="flex-1"><Button label="Cancelar" kind="ghost" block disabled={busy} onPress={() => setConfirm(true)} /></View>
        </View>
      </View>
      <ConfirmModal visible={confirm} title="Cancelar turno" message={`Se libera tu lugar en ${item.entry.queueName ?? 'la cola'}. Esta acción no se puede deshacer.`} confirmLabel="Cancelar turno" cancelLabel="Volver"
        onCancel={() => setConfirm(false)} onConfirm={() => { setConfirm(false); void run('cancel'); }} />
    </View>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return <View className="flex-1 p-4"><Txt variant="caption" color="textSecondary">{label}</Txt><Txt variant="turn" className="text-[28px] leading-9">{value}</Txt></View>;
}
