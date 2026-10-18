import { err, estimateWaitMinutes, defaultQueuePrefix, formatTurnNumber, isFailure, ok, type Failure, type Result } from '@qhub/core';
import type { Schedule, Ticket } from '@qhub/api-client';
import { isActiveStatus } from '@qhub/api-client';
import type { QhubGateway } from '@/features/gateway/domain/gateway';
import { isActiveEntry, type HistoryEntry, type HistoryRepository } from '@/features/history/domain/history';
import type { OrganizationRepository } from '@/features/organizations/domain/organizations';

/** Un turno vigente del usuario con todo lo que necesita la tarjeta "Mi turno". */
export interface ActiveTicket {
  entry: HistoryEntry; ticket: Ticket; prefix: string; schedule: Schedule | null; peopleAhead: number; estimateMinutes: number | null;
}
export const activeLabel = (a: ActiveTicket) => formatTurnNumber(a.ticket.number, a.prefix);
export const isMyTurn = (a: ActiveTicket) => a.ticket.status === 'atendiendo';

/** Personas delante en la misma franja: `posición - 1` (0 cuando ya lo están atendiendo). */
export const aheadOf = (t: Ticket) => (t.status === 'en_espera' ? Math.max(t.position - 1, 0) : 0);

/** Carga los turnos vigentes: los activos del historial, refrescados contra la API de su organización. */
export class LoadActiveTickets {
  constructor(private readonly history: HistoryRepository, private readonly gateway: QhubGateway, private readonly organizations: OrganizationRepository) {}

  async run(): Promise<Result<ActiveTicket[]>> {
    const hist = await this.history.list();
    if (!hist.ok) return err(hist.failure);
    const active = hist.value.filter(isActiveEntry);
    if (active.length === 0) return ok([]);

    const prefixCache = new Map<string, Promise<Record<string, string>>>();
    const prefixesOf = (org: string) => {
      let p = prefixCache.get(org);
      if (!p) { p = this.organizations.queuePrefixes(org).then((r) => (r.ok ? r.value : {})); prefixCache.set(org, p); }
      return p;
    };

    let firstFailure: Failure | null = null;
    const results = await Promise.all(active.map(async (e): Promise<ActiveTicket | null> => {
      const fresh = await this.gateway.tickets(e.organizationId).get(e.ticketId);
      if (!fresh.ok) { if (fresh.failure.kind !== 'not_found') firstFailure ??= fresh.failure; return null; }
      const ticket = fresh.value;
      if (!isActiveStatus(ticket.status)) return null; // ya se resolvió: sale de "Mi turno"
      const sch = await this.gateway.queues(e.organizationId).schedule(e.queueId);
      const schedule = sch.ok ? sch.value : null;
      const prefixes = await prefixesOf(e.organizationId);
      const ahead = aheadOf(ticket);
      return {
        entry: e, ticket, prefix: prefixes[e.queueId] ?? defaultQueuePrefix(e.queueName ?? ''), schedule, peopleAhead: ahead,
        estimateMinutes: schedule ? estimateWaitMinutes({ peopleAhead: ahead, turnMinutes: schedule.turnMinutes, stations: schedule.stations }) : null,
      };
    }));

    const list = results.filter((x): x is ActiveTicket => x !== null).sort((a, b) => a.ticket.slotStart.getTime() - b.ticket.slotStart.getTime());
    if (list.length === 0 && firstFailure) return err(firstFailure);
    return ok(list);
  }
}
export { isFailure };
