import { useQuery } from '@tanstack/react-query';
import { unwrap } from '@qhub/core';
import { useContainer } from './container';

/** Con un turno vigente se consulta seguido; sin turnos, con calma. */
export const ACTIVE_REFRESH_MS = 8_000;
export const IDLE_REFRESH_MS = 20_000;

/**
 * Mis turnos vigentes. El proxy no expone WebSocket, así que se consulta en intervalos: rápido mientras haya un turno vigente
 * y solo con la app a la vista (react-query pausa en segundo plano y refresca al volver; ver `focusManager` en App).
 */
export function useActiveTickets() {
  const { loadActiveTickets } = useContainer();
  return useQuery({
    queryKey: ['active-tickets'],
    queryFn: async () => unwrap(await loadActiveTickets.run()),
    refetchInterval: (q) => (q.state.data?.length ? ACTIVE_REFRESH_MS : IDLE_REFRESH_MS),
  });
}
export function useOrgSearch(query: string) {
  const { organizations } = useContainer();
  return useQuery({ queryKey: ['orgs', query], queryFn: async () => unwrap(await organizations.search(query)) });
}
/** Organizaciones a las que estoy vinculado. */
export function useLinkedOrgs() {
  const { organizations } = useContainer();
  return useQuery({ queryKey: ['linked'], queryFn: async () => unwrap(await organizations.linked()) });
}
export function useLinkedIds() {
  const q = useLinkedOrgs();
  return { ...q, ids: new Set((q.data ?? []).map((o) => o.id)) };
}
export function useOrg(id: string) {
  const { organizations } = useContainer();
  return useQuery({ queryKey: ['org', id], queryFn: async () => unwrap(await organizations.get(id)) });
}
export function useOrgPrefixes(id: string) {
  const { organizations } = useContainer();
  return useQuery({ queryKey: ['prefixes', id], queryFn: async () => { const r = await organizations.queuePrefixes(id); return r.ok ? r.value : {}; } });
}
export function useOrgQueues(orgId: string) {
  const { gateway } = useContainer();
  return useQuery({ queryKey: ['org-queues', orgId], queryFn: async () => unwrap(await gateway.queues(orgId).list({ active: true })).filter((q) => q.active) });
}
export function useQueueState(orgId: string, queueId: string) {
  const { gateway } = useContainer();
  return useQuery({ queryKey: ['queue-state', orgId, queueId], queryFn: async () => unwrap(await gateway.queues(orgId).state(queueId)) });
}
export function useSchedule(orgId: string, queueId: string) {
  const { gateway } = useContainer();
  return useQuery({ queryKey: ['schedule', orgId, queueId], queryFn: async () => unwrap(await gateway.queues(orgId).schedule(queueId)) });
}
export function useSlots(orgId: string, queueId: string, date: Date | null) {
  const { gateway } = useContainer();
  const key = date ? `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}` : null;
  return useQuery({ queryKey: ['slots', orgId, queueId, key], enabled: date !== null, queryFn: async () => unwrap(await gateway.queues(orgId).slots(queueId, date!)) });
}
export function useHistory() {
  const { history } = useContainer();
  return useQuery({ queryKey: ['history'], queryFn: async () => unwrap(await history.list()) });
}
