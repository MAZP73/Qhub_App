import { Pressable, ScrollView, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Button, Icon, ListRow, Logo, OrgMark, Screen, SectionHeader, Skeleton, Tile, Txt } from '@/shared/ui/kit';
import { orgLocation, orgMark } from '@/features/organizations/organizations';
import { TicketCard } from '@/features/tickets/TicketCard';
import { useAuth } from '@/app/container';
import { useActiveTickets, useLinkedOrgs } from '@/app/hooks';
import type { Nav } from '@/app/navigation';

/** Saludo según la hora. */
export const greeting = (d: Date = new Date()) => (d.getHours() < 12 ? 'Buenos días' : d.getHours() < 19 ? 'Buenas tardes' : 'Buenas noches');
const firstName = (name?: string, email?: string) => (name?.trim().split(/\s+/)[0] ?? email?.split('@')[0] ?? '');

/** Inicio: saludo, tu turno más cercano y dos accesos rápidos (Turnos y Organizaciones), sin mezclar cosas. */
export function HomeScreen() {
  const nav = useNavigation<Nav>();
  const insets = useSafeAreaInsets();
  const auth = useAuth();
  const user = auth.status === 'ready' ? auth.value : null;
  const tickets = useActiveTickets();
  const linked = useLinkedOrgs().data ?? [];
  const active = tickets.data ?? [];
  const go = (screen: 'Turns' | 'Orgs') => nav.navigate('Tabs', { screen });

  return (
    <Screen>
      <ScrollView contentContainerClassName="pb-8" showsVerticalScrollIndicator={false}>
        <View className="bg-brand-ink px-4 pb-14" style={{ paddingTop: insets.top + 12 }}>
          <View className="flex-row items-center justify-between">
            <Logo name="qhub-horizontal-negativo" height={22} />
            <Pressable accessibilityRole="button" accessibilityLabel="Perfil" onPress={() => nav.navigate('Profile')} hitSlop={8} className="size-10 items-center justify-center rounded-full bg-layer-02">
              <Icon name="user" size={20} />
            </Pressable>
          </View>
          <View className="pt-6">
            <Txt variant="caption" color="sidebarText">{greeting()}</Txt>
            <Txt variant="h1" color="sidebarTextActive" accessibilityRole="header">{`Hola${firstName(user?.displayName, user?.email) ? `, ${firstName(user?.displayName, user?.email)}` : ''}`}</Txt>
          </View>
        </View>

        <View className="-mt-10 gap-6 px-4">
          {tickets.isLoading ? <Skeleton height={200} /> : active.length > 0 ? (
            <View className="gap-2">
              <TicketCard item={active[0]!} />
              {active.length > 1 ? <Button label={`Ver mis ${active.length} turnos`} kind="tertiary" block onPress={() => go('Turns')} /> : null}
            </View>
          ) : (
            <View className="items-center gap-3 rounded-md border border-border-subtle bg-layer-01 p-6">
              <View className="size-14 items-center justify-center rounded-full bg-layer-02"><Icon name="ticket" size={28} color="link" /></View>
              <Txt variant="h4" className="text-center">No tienes turnos activos</Txt>
              <Txt color="textSecondary" className="text-center">{linked.length === 0 ? 'Vincúlate a una organización para sacar turno o reservar una cita.' : 'Elige una de tus organizaciones y saca turno o reserva una cita.'}</Txt>
              <Button label={linked.length === 0 ? 'Buscar organización' : 'Ver mis organizaciones'} icon="search" onPress={() => go('Orgs')} />
            </View>
          )}

          <View className="flex-row gap-3">
            <Tile icon="ticket" title="Turnos" caption={active.length === 0 ? 'Sin turnos activos' : active.length === 1 ? '1 turno activo' : `${active.length} turnos activos`} onPress={() => go('Turns')} />
            <Tile icon="building" title="Organizaciones" caption={linked.length === 0 ? 'Busca y vincúlate' : linked.length === 1 ? '1 vinculada' : `${linked.length} vinculadas`} onPress={() => go('Orgs')} />
          </View>

          {linked.length > 0 ? (
            <View className="gap-2">
              <SectionHeader title="Tus organizaciones" action="Ver todas" onAction={() => go('Orgs')} />
              <View className="overflow-hidden rounded-md border border-border-subtle">
                {linked.slice(0, 3).map((o) => (
                  <ListRow key={o.id} leading={<OrgMark text={orgMark(o.name)} />} title={o.name} subtitles={orgLocation(o) ? [orgLocation(o)] : []} trailing={<Icon name="chevron-right" />} onPress={() => nav.navigate('Org', { organizationId: o.id })} />
                ))}
              </View>
            </View>
          ) : null}
        </View>
      </ScrollView>
    </Screen>
  );
}
