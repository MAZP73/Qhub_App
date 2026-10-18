import { View } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { unwrap } from '@qhub/core';
import { Button, Icon, Txt, useToast } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { expiresIn } from './edit-requests';

/** Peticiones de una organización para editar mis datos: no cambia nada sin mi permiso. */
export function EditRequestsSection() {
  const { editRequests } = useContainer();
  const qc = useQueryClient();
  const toast = useToast();
  const q = useQuery({ queryKey: ['edit-requests'], queryFn: async () => unwrap(await editRequests.pending()), refetchInterval: 30_000 });
  const items = q.data ?? [];
  if (items.length === 0) return null;

  async function respond(id: string, org: string, approve: boolean) {
    const r = await editRequests.respond(id, approve);
    if (r.ok) { toast.show(approve ? `Le diste permiso a ${org} para un cambio en tus datos.` : 'Rechazaste la solicitud.'); await qc.invalidateQueries({ queryKey: ['edit-requests'] }); }
    else toast.show(r.failure.message, { error: true });
  }

  return (
    <View className="gap-3 p-4">
      <Txt variant="h4">Solicitudes de permiso</Txt>
      {items.map((e) => (
        <View key={e.id} className="gap-2 border border-border-subtle bg-layer-01 p-4">
          <View className="flex-row items-center gap-2"><Icon name="warning" color="stateWaitingText" /><Txt weight={600}>{e.organization} quiere cambiar tus datos</Txt></View>
          <Txt color="textSecondary">Pide permiso para editar tu nombre, apellido o teléfono. Solo podrá hacer un cambio en las 24 horas siguientes a tu aprobación.</Txt>
          {e.reason ? <Txt color="textSecondary">Motivo: “{e.reason}”</Txt> : null}
          <Txt variant="caption" color="textSecondary">{expiresIn(e)}</Txt>
          <View className="flex-row gap-2">
            <Button label="Aprobar" big={false} onPress={() => void respond(e.id, e.organization, true)} />
            <Button label="Rechazar" kind="secondary" big={false} onPress={() => void respond(e.id, e.organization, false)} />
          </View>
        </View>
      ))}
    </View>
  );
}
