import { useState } from 'react';
import { FlatList, RefreshControl, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { friendlyError } from '@qhub/core';
import { AppBar, Button, EmptyState, Screen, Skeleton, Tabs } from '@/shared/ui/kit';
import { useActiveTickets, useLinkedOrgs } from '@/app/hooks';
import { HistoryList } from '@/features/history/HistoryList';
import { TicketCard } from './TicketCard';
import type { Nav } from '@/app/navigation';

/** Turnos: los vigentes (con su espera) y el historial, separados del resto de la app. */
export function TurnsScreen() {
  const nav = useNavigation<Nav>();
  const [tab, setTab] = useState(0);
  const tickets = useActiveTickets();
  const linked = useLinkedOrgs().data ?? [];
  return (
    <Screen>
      <AppBar title="Turnos" />
      <Tabs labels={['Activos', 'Historial']} index={tab} onChange={setTab} />
      {tab === 1 ? <HistoryList /> : tickets.isLoading ? (
        <View className="gap-3 p-4"><Skeleton height={200} /><Skeleton height={60} /></View>
      ) : tickets.isError ? (
        <EmptyState title="No pudimos cargar esto" message={friendlyError(tickets.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void tickets.refetch()} />} />
      ) : (
        <FlatList
          data={tickets.data}
          keyExtractor={(t) => t.ticket.id}
          contentContainerClassName="grow gap-4 p-4"
          refreshControl={<RefreshControl refreshing={tickets.isRefetching} onRefresh={() => void tickets.refetch()} />}
          ListEmptyComponent={linked.length === 0
            ? <EmptyState title="Aún no estás vinculado a ninguna organización" message="Busca tu organización por nombre o por su ID (QH-XXXXXX) y vincúlate para ver sus colas y sacar turno." action={<Button label="Buscar organización" icon="search" onPress={() => nav.navigate('Tabs', { screen: 'Orgs' })} />} />
            : <EmptyState title="No tienes turnos activos" message="Elige una de tus organizaciones y saca un turno o reserva una cita en segundos." action={<Button label="Ver mis organizaciones" kind="tertiary" onPress={() => nav.navigate('Tabs', { screen: 'Orgs' })} />} />}
          renderItem={({ item }) => <TicketCard item={item} />}
        />
      )}
    </Screen>
  );
}
