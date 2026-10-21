import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { AppBar, Button, Chips, EmptyState, Icon, ListRow, OrgMark, Screen, Skeleton, Tag, TextField, Txt, useToast } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { useLinkedIds, useOrgSearch } from '@/app/hooks';
import { KIND_LABEL, orgLocation, orgMark, type OrganizationSummary } from './organizations';
import type { Nav } from '@/app/navigation';
import { friendlyError } from '@qhub/core';

export function ExploreScreen() {
  const nav = useNavigation<Nav>();
  const [text, setText] = useState('');
  const [query, setQuery] = useState('');
  useEffect(() => { const t = setTimeout(() => setQuery(text.trim()), 350); return () => clearTimeout(t); }, [text]);
  const orgs = useOrgSearch(query);
  const linked = useLinkedIds().ids;
  const { organizations } = useContainer();
  const qc = useQueryClient();
  const toast = useToast();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [filter, setFilter] = useState(0);   // 0 todas · 1 empresas · 2 personas
  const shown = (orgs.data ?? []).filter((o) => filter === 0 || (filter === 1 ? o.kind !== 'persona' : o.kind === 'persona'));
  const sorted = [...shown].sort((a, b) => Number(linked.has(b.id)) - Number(linked.has(a.id)));

  async function link(o: OrganizationSummary) {
    setBusyId(o.id);
    const r = await organizations.link(o.id);
    setBusyId(null);
    if (r.ok) { toast.show(`Te vinculaste a ${o.name}. Ya puedes ver sus colas.`); await Promise.all([qc.invalidateQueries({ queryKey: ['linked'] }), qc.invalidateQueries({ queryKey: ['orgs'] })]); }
    else toast.show(r.failure.message, { error: true });
  }

  return (
    <Screen>
      <AppBar title="Organizaciones" />
      <View className="gap-3 p-4">
        <TextField label="Buscar" placeholder="Nombre o ID (QH-XXXXXX)" value={text} onChangeText={setText} autoCapitalize="none" />
        <Chips labels={['Todas', 'Empresas', 'Personas']} index={filter} onChange={setFilter} />
      </View>
      {orgs.isLoading ? <View className="p-4 gap-2"><Skeleton height={64} /><Skeleton height={64} /></View>
        : orgs.isError ? <EmptyState title="No pudimos cargar esto" message={friendlyError(orgs.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void orgs.refetch()} />} />
        : sorted.length === 0 ? <EmptyState title={query || filter !== 0 ? 'Sin resultados' : 'Aún no hay organizaciones'} message={query || filter !== 0 ? 'Prueba con otro nombre, ciudad, otro filtro o con el ID que te dio la organización (QH-XXXXXX).' : 'Cuando una organización o una persona publique su espacio en Qhub lo verás aquí.'} />
        : (
          <FlatList data={sorted} keyExtractor={(o) => o.id} renderItem={({ item: o }) => (
            <ListRow leading={<OrgMark text={orgMark(o.name)} />} title={<View className="gap-1"><Txt weight={600}>{o.name}</Txt><Tag label={KIND_LABEL[o.kind ?? 'empresa']} icon={o.kind === 'persona' ? 'user' : 'building'} /></View>} subtitles={[...(orgLocation(o) ? [orgLocation(o)] : []), ...(o.code ? [`ID ${o.code}`] : [])]}
              trailing={linked.has(o.id)
                ? <View className="flex-row items-center gap-1"><Icon name="check" color="link" /><Txt variant="caption" color="link">Vinculada</Txt><Icon name="chevron-right" /></View>
                : <Button label="Vincular" kind="secondary" big={false} loading={busyId === o.id} onPress={() => void link(o)} />}
              onPress={() => nav.navigate('Org', { organizationId: o.id })} />
          )} />
        )}
    </Screen>
  );
}
