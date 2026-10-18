import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { AppBar, Button, EmptyState, Icon, ListRow, OrgMark, Screen, Skeleton, TextField, Txt } from '@/shared/ui/kit';
import { useFavorites, useOrgSearch } from '@/app/hooks';
import { orgLocation, orgMark } from '../domain/organizations';
import type { Nav } from '@/app/navigation';
import { friendlyError } from '@qhub/core';

export function ExploreScreen() {
  const nav = useNavigation<Nav>();
  const [text, setText] = useState('');
  const [query, setQuery] = useState('');
  useEffect(() => { const t = setTimeout(() => setQuery(text.trim()), 350); return () => clearTimeout(t); }, [text]);
  const orgs = useOrgSearch(query);
  const favorites = useFavorites().data ?? new Set<string>();
  const sorted = [...(orgs.data ?? [])].sort((a, b) => Number(favorites.has(b.id)) - Number(favorites.has(a.id)));

  return (
    <Screen>
      <AppBar title="Elige dónde" />
      <View className="p-4"><TextField label="Buscar" placeholder="Organización, ciudad o dirección" value={text} onChangeText={setText} autoCapitalize="none" /></View>
      {orgs.isLoading ? <View className="p-4 gap-2"><Skeleton height={64} /><Skeleton height={64} /></View>
        : orgs.isError ? <EmptyState title="No pudimos cargar esto" message={friendlyError(orgs.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void orgs.refetch()} />} />
        : sorted.length === 0 ? <EmptyState title={query ? 'Sin resultados' : 'Aún no hay organizaciones'} message={query ? 'Prueba con otro nombre o ciudad.' : 'Cuando una organización se publique en Qhub la verás aquí.'} />
        : (
          <FlatList data={sorted} keyExtractor={(o) => o.id} renderItem={({ item: o }) => (
            <ListRow leading={<OrgMark text={orgMark(o.name)} />} title={o.name} subtitles={orgLocation(o) ? [orgLocation(o)] : []}
              trailing={<View className="flex-row items-center gap-1">{favorites.has(o.id) && <Txt variant="caption" color="link">Favorita</Txt>}<Icon name="chevron-right" /></View>}
              onPress={() => nav.navigate('Org', { organizationId: o.id })} />
          )} />
        )}
    </Screen>
  );
}
