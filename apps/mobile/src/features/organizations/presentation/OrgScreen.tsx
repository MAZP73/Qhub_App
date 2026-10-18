import { ScrollView, View } from 'react-native';
import { useNavigation, useRoute, type RouteProp } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { defaultQueuePrefix, friendlyError } from '@qhub/core';
import { AppBar, Button, EmptyState, Icon, IconButton, ListRow, OrgMark, Screen, Skeleton, Txt } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { useFavorites, useOrg, useOrgPrefixes, useOrgQueues, useQueueState } from '@/app/hooks';
import { orgLocation, orgMark } from '../domain/organizations';
import type { Nav, RootStackParamList } from '@/app/navigation';

export function OrgScreen() {
  const nav = useNavigation<Nav>();
  const { organizationId } = useRoute<RouteProp<RootStackParamList, 'Org'>>().params;
  const { organizations } = useContainer();
  const qc = useQueryClient();
  const org = useOrg(organizationId);
  const queues = useOrgQueues(organizationId);
  const prefixes = useOrgPrefixes(organizationId).data ?? {};
  const fav = useFavorites().data?.has(organizationId) ?? false;
  const o = org.data;

  return (
    <Screen>
      <AppBar title={o?.name ?? 'Organización'} left={<IconButton icon="chevron-left" label="Atrás" onPress={() => nav.goBack()} />}
        right={<Button label={fav ? 'Quitar' : 'Favorita'} kind="ghost" big={false} onPress={async () => { await organizations.setFavorite(organizationId, !fav); await qc.invalidateQueries({ queryKey: ['favorites'] }); }} />} />
      <ScrollView>
        {org.isLoading ? <View className="p-4"><Skeleton height={120} /></View> : org.isError ? (
          <EmptyState title="No pudimos cargar esto" message={friendlyError(org.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void org.refetch()} />} />
        ) : o ? (
          <>
            <View className="flex-row gap-3 p-4 items-center">
              <OrgMark text={orgMark(o.name)} sizePx={48} />
              <View className="flex-1"><Txt variant="h4">{o.name}</Txt>{orgLocation(o) ? <Txt variant="caption" color="textSecondary">{orgLocation(o)}</Txt> : null}{o.phone ? <Txt variant="caption" color="textSecondary">{o.phone}</Txt> : null}</View>
            </View>
            <View className="px-4 pb-2"><Txt variant="h4">Colas abiertas</Txt></View>
            {queues.isLoading ? <View className="p-4"><Skeleton height={64} /></View> : queues.isError ? (
              <EmptyState title="No pudimos cargar esto" message={friendlyError(queues.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void queues.refetch()} />} />
            ) : (queues.data ?? []).length === 0 ? <EmptyState title="Sin colas abiertas" message="Esta organización no tiene colas activas ahora." /> : (
              (queues.data ?? []).map((q) => <QueueRow key={q.id} orgId={organizationId} queueId={q.id} name={q.name} description={q.description} prefix={prefixes[q.id] ?? defaultQueuePrefix(q.name)} onPress={() => nav.navigate('TakeTurn', { organizationId, queueId: q.id })} />)
            )}
          </>
        ) : null}
      </ScrollView>
    </Screen>
  );
}

function QueueRow({ orgId, queueId, name, description, prefix, onPress }: { orgId: string; queueId: string; name: string; description: string | null; prefix: string; onPress: () => void }) {
  const state = useQueueState(orgId, queueId).data;
  return (
    <ListRow
      leading={<View className="w-[40px] h-[40px] bg-layer-02 items-center justify-center"><Txt variant="turn">{prefix}</Txt></View>}
      title={name} subtitles={[...(description ? [description] : []), state ? `${state.waiting} en espera · ${state.serving} atendiendo` : 'Consultando fila…']}
      trailing={<Icon name="chevron-right" />} onPress={onPress} />
  );
}
