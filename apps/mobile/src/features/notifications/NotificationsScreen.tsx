import { useState } from 'react';
import { FlatList, View } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { formatHm, unwrap, friendlyError } from '@qhub/core';
import type { AppNotification } from '@qhub/api-client';
import type { ColorName, IconName } from '@qhub/design';
import { AppBar, Button, EmptyState, Icon, ListRow, Screen, Skeleton, Tabs, Txt } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { dayLabel, groupByDay } from '@/features/history/history';
import { EditRequestsSection } from '@/features/permissions/EditRequestsSection';

/** Marca de los avisos de la cuenta (no pertenecen a una organización). */
const ACCOUNT = '';

interface OrgNotification { organizationId: string; organizationName: string; notification: AppNotification }

/** Ícono y color por tipo de aviso (design: Avisos). */
export function styleOf(kind: string | null): { icon: IconName; color: ColorName } {
  switch (kind) {
    case 'turno_llamado': return { icon: 'call', color: 'link' };
    case 'turno_pospuesto': return { icon: 'clock', color: 'stateWaitingText' };
    case 'turno_no_show': return { icon: 'noshow', color: 'stateNoshowText' };
    case 'recordatorio': return { icon: 'bell', color: 'stateWaitingText' };
    case 'bienvenida': case 'vinculacion': return { icon: 'check', color: 'stateServingText' };
    case 'desvinculacion': return { icon: 'info', color: 'supportInfo' };
    case 'turno_creado': case 'cita_creada': return { icon: 'ticket', color: 'link' };
    case 'turno_cancelado': return { icon: 'noshow', color: 'stateNoshowText' };
    default: return { icon: 'info', color: 'supportInfo' };
  }
}

export function NotificationsScreen() {
  const { history, gateway, accountNotices } = useContainer();
  const qc = useQueryClient();
  const [tab, setTab] = useState(0);

  const q = useQuery({
    queryKey: ['notifications'],
    refetchInterval: 30_000,   // sin WebSocket en el proxy: se consulta con la app a la vista
    queryFn: async () => {
      // Avisos de la cuenta (bienvenida, vinculación, turno creado): no dependen de una organización ni de tener turnos.
      const own = await accountNotices.list();
      const account: OrgNotification[] = own.ok ? own.value.map((a) => ({
        organizationId: ACCOUNT, organizationName: 'Qhub',
        notification: { id: a.id, userId: '', ticketId: null, message: /[.!?]$/.test(a.title) ? `${a.title} ${a.message}` : `${a.title}. ${a.message}`, read: a.read, createdAt: a.createdAt, kind: a.type },
      })) : [];
      const hist = unwrap(await history.list());
      const orgs = new Map(hist.map((e) => [e.organizationId, e.organizationName ?? 'Organización']));
      const out: OrgNotification[] = [];
      let failure: Error | null = null;
      await Promise.all([...orgs.entries()].map(async ([id, name]) => {
        const r = await gateway.notifications(id).list({ limit: 50 });
        if (r.ok) out.push(...r.value.map((n) => ({ organizationId: id, organizationName: name, notification: n }))); else failure ??= r.failure;
      }));
      if (out.length === 0 && account.length === 0 && failure) throw failure;
      out.push(...account);
      return out.sort((a, b) => b.notification.createdAt.getTime() - a.notification.createdAt.getTime());
    },
  });

  async function markRead(n: OrgNotification) {
    const r = n.organizationId === ACCOUNT ? await accountNotices.markRead(n.notification.id) : await gateway.notifications(n.organizationId).markRead(n.notification.id);
    if (r.ok) qc.setQueryData<OrgNotification[]>(['notifications'], (cur) => (cur ?? []).map((x) => (x.notification.id === n.notification.id ? { ...x, notification: { ...x.notification, read: true } } : x)));
  }

  const all = q.data ?? [];
  const unread = all.filter((n) => !n.notification.read);
  const list = tab === 1 ? unread : all;
  const groups = groupByDay(list.map((n) => ({ ...n, createdAt: n.notification.createdAt })));
  const now = new Date();

  return (
    <Screen>
      <AppBar title="Avisos" right={<Button label="Marcar leídas" kind="ghost" big={false} disabled={unread.length === 0} onPress={async () => { for (const n of unread) await markRead(n); }} />} />
      <EditRequestsSection />
      <Tabs labels={['Todas', `Sin leer${unread.length ? ` (${unread.length})` : ''}`]} index={tab} onChange={setTab} />
      {q.isLoading ? <View className="p-4"><Skeleton height={64} /></View> : q.isError ? (
        <EmptyState title="No pudimos cargar esto" message={friendlyError(q.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void q.refetch()} />} />
      ) : list.length === 0 ? <EmptyState title={tab === 1 ? 'Estás al día' : 'Sin avisos todavía'} message="Te avisaremos cuando se acerque tu turno." /> : (
        <FlatList data={groups} keyExtractor={(g) => g.day.toISOString()} onRefresh={() => void q.refetch()} refreshing={q.isRefetching} renderItem={({ item: g }) => (
          <View>
            <View className="px-4 pt-4 pb-1"><Txt variant="label" color="textSecondary">{dayLabel(g.day, now)}</Txt></View>
            {g.items.map((n) => {
              const { icon, color } = styleOf(n.notification.kind);
              const isUnread = !n.notification.read;
              return (
                <ListRow key={n.notification.id} highlighted={isUnread} leading={<Icon name={icon} size={20} color={color} />}
                  title={<Txt weight={isUnread ? 600 : 400}>{n.notification.message}</Txt>} subtitles={[n.organizationName]}
                  trailing={<View className="flex-row items-center gap-1"><Txt variant="caption" color="textSecondary">{formatHm(n.notification.createdAt)}</Txt>{isUnread && <View accessibilityLabel="No leída" className="size-2 bg-interactive" />}</View>}
                  onPress={isUnread ? () => void markRead(n) : undefined} />
              );
            })}
          </View>
        )} />
      )}
    </Screen>
  );
}
