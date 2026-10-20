import { ScrollView, View } from 'react-native';
import { useNavigation, useRoute, type RouteProp } from '@react-navigation/native';
import { useQueryClient } from '@tanstack/react-query';
import { defaultQueuePrefix, friendlyError } from '@qhub/core';
import { useState } from 'react';
import { AppBar, Button, Card, ConfirmModal, EmptyState, Icon, IconButton, ListRow, OrgMark, Screen, Skeleton, Txt, useToast } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { useLinkedIds, useOrg, useOrgPrefixes, useOrgQueues, useQueueState } from '@/app/hooks';
import { orgLocation, orgMark } from './organizations';
import type { Nav, RootStackParamList } from '@/app/navigation';

export function OrgScreen() {
  const nav = useNavigation<Nav>();
  const { organizationId } = useRoute<RouteProp<RootStackParamList, 'Org'>>().params;
  const { organizations } = useContainer();
  const qc = useQueryClient();
  const org = useOrg(organizationId);
  const queues = useOrgQueues(organizationId);
  const prefixes = useOrgPrefixes(organizationId).data ?? {};
  const linkedState = useLinkedIds();
  const linked = linkedState.ids.has(organizationId);
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [confirmUnlink, setConfirmUnlink] = useState(false);
  const o = org.data;

  async function setLinked(link: boolean) {
    setBusy(true); setConfirmUnlink(false);
    const r = link ? await organizations.link(organizationId) : await organizations.unlink(organizationId);
    setBusy(false);
    if (!r.ok) { toast.show(r.failure.message, { error: true }); return; }
    toast.show(link ? `Te vinculaste a ${o?.name ?? 'la organización'}.` : 'Te desvinculaste de la organización.');
    await Promise.all([qc.invalidateQueries({ queryKey: ['linked'] }), qc.invalidateQueries({ queryKey: ['orgs'] }), qc.invalidateQueries({ queryKey: ['org-queues', organizationId] })]);
  }

  return (
    <Screen>
      <AppBar title={o?.name ?? 'Organización'} left={<IconButton icon="chevron-left" label="Atrás" onPress={() => nav.goBack()} />}
        right={linked ? <Button label="Desvincular" kind="ghost" big={false} loading={busy} onPress={() => setConfirmUnlink(true)} /> : undefined} />
      <ConfirmModal visible={confirmUnlink} title="Desvincular" message={`Dejarás de ver las colas de ${o?.name ?? 'esta organización'} y de poder sacar turno. Tus turnos pasados se conservan.`} confirmLabel="Desvincular" onConfirm={() => void setLinked(false)} onCancel={() => setConfirmUnlink(false)} />
      <ScrollView>
        {org.isLoading ? <View className="p-4"><Skeleton height={120} /></View> : org.isError ? (
          <EmptyState title="No pudimos cargar esto" message={friendlyError(org.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void org.refetch()} />} />
        ) : o ? (
          <>
            <View className="flex-row gap-3 p-4 items-center">
              <OrgMark text={orgMark(o.name)} sizePx={48} />
              <View className="flex-1"><Txt variant="h4">{o.name}</Txt>{orgLocation(o) ? <Txt variant="caption" color="textSecondary">{orgLocation(o)}</Txt> : null}{o.code ? <Txt variant="caption" color="textSecondary">ID {o.code}</Txt> : null}{o.phone ? <Txt variant="caption" color="textSecondary">{o.phone}</Txt> : null}</View>
            </View>
            {!linked ? (
              <View className="mx-4">
                <Card>
                  <View className="gap-3">
                    <Txt variant="h4">Vincúlate para continuar</Txt>
                    <Txt color="textSecondary">Al vincularte a {o.name} pasas a ser su cliente: ves sus colas abiertas y sacas turno. Puedes estar vinculado a varias organizaciones.</Txt>
                    <Button label="Vincular" icon="check" loading={busy} onPress={() => void setLinked(true)} />
                  </View>
                </Card>
              </View>
            ) : (
            <>
            <View className="px-4 pb-2"><Txt variant="h4">Colas abiertas</Txt></View>
            {queues.isLoading ? <View className="p-4"><Skeleton height={64} /></View> : queues.isError ? (
              <EmptyState title="No pudimos cargar esto" message={friendlyError(queues.error)} action={<Button label="Reintentar" kind="tertiary" onPress={() => void queues.refetch()} />} />
            ) : (queues.data ?? []).length === 0 ? <EmptyState title="Sin colas abiertas" message="Esta organización no tiene colas activas ahora." /> : (
              (queues.data ?? []).map((q) => <QueueRow key={q.id} orgId={organizationId} queueId={q.id} name={q.name} description={q.description} prefix={prefixes[q.id] ?? defaultQueuePrefix(q.name)} onPress={() => nav.navigate('TakeTurn', { organizationId, queueId: q.id })} />)
            )}
            </>
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
      leading={<View className="size-10 bg-layer-02 items-center justify-center"><Txt variant="turn">{prefix}</Txt></View>}
      title={name} subtitles={[...(description ? [description] : []), state ? `${state.waiting} en espera · ${state.serving} atendiendo` : 'Consultando fila…']}
      trailing={<Icon name="chevron-right" />} onPress={onPress} />
  );
}
