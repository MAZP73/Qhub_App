import { FlatList, View } from 'react-native';
import { defaultQueuePrefix, friendlyError } from '@qhub/core';
import { AppBar, Button, EmptyState, ListRow, OrgMark, Screen, Skeleton, TurnBadge, TurnNumber, Txt } from '@/shared/ui/kit';
import { useHistory } from '@/app/hooks';
import { dayLabel, groupByDay } from './history';

export function HistoryScreen() {
  const q = useHistory();
  const groups = groupByDay(q.data ?? []);
  const now = new Date();
  return (
    <Screen>
      <AppBar title="Historial" />
      {q.isLoading ? <View className="p-4"><Skeleton height={64} /></View> : q.isError ? (
        <EmptyState title="No pudimos cargar esto" message={friendlyError(q.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void q.refetch()} />} />
      ) : groups.length === 0 ? <EmptyState title="Aún no tienes turnos" message="Tus turnos pasados aparecerán aquí." /> : (
        <FlatList data={groups} keyExtractor={(g) => g.day.toISOString()} onRefresh={() => void q.refetch()} refreshing={q.isRefetching} renderItem={({ item: g }) => (
          <View>
            <View className="px-4 pt-4 pb-1"><Txt variant="label" color="textSecondary">{dayLabel(g.day, now)}</Txt></View>
            {g.items.map((e) => (
              <ListRow key={e.ticketId} leading={<OrgMark text={(e.organizationName ?? '?').slice(0, 1).toUpperCase()} sizePx={36} />}
                title={<View className="flex-row items-center gap-2"><TurnNumber number={e.number} prefix={defaultQueuePrefix(e.queueName ?? '')} /><Txt numberOfLines={1}>{e.queueName ?? ''}</Txt></View>}
                subtitles={[e.organizationName ?? '']} trailing={<TurnBadge status={e.status} />} />
            ))}
          </View>
        )} />
      )}
    </Screen>
  );
}
