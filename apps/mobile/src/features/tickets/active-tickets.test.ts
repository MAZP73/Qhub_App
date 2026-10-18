import { aheadOf, LoadActiveTickets } from '@/features/tickets/active-tickets';
import { entry, FakeGateway, FakeHistoryRepository, FakeOrganizationRepository, ticket } from '@/testing/fakes';
import { networkFailure } from '@qhub/core';

describe('LoadActiveTickets', () => {
  const build = () => {
    const gw = new FakeGateway();
    const hist = new FakeHistoryRepository([
      entry('t1', 7, 'en_espera'), entry('t2', 8, 'finalizado'), entry('t3', 9, 'en_espera'), entry('t4', 10, 'en_espera'),
    ]);
    gw.ticketRepo.stored.set('t1', ticket('t1', 7, 'en_espera', { position: 4 }));
    gw.ticketRepo.stored.set('t3', ticket('t3', 9, 'no_show'));
    return { gw, hist, uc: new LoadActiveTickets(hist, gw, new FakeOrganizationRepository()) };
  };
  it('solo devuelve los vigentes, refrescados, con prefijo y espera estimada', async () => {
    const r = await build().uc.run();
    expect(r.ok && r.value).toHaveLength(1);
    const t = (r as { value: Array<{ prefix: string; peopleAhead: number; estimateMinutes: number | null }> }).value[0]!;
    expect(t.prefix).toBe('E');
    expect(t.peopleAhead).toBe(3);
    expect(t.estimateMinutes).toBe(20); // ceil(3/2) × 10
  });
  it('si la API falla en todo propaga el error; con 404 no', async () => {
    const { gw, uc } = build();
    gw.ticketRepo.getFailure = networkFailure();
    const r = await uc.run();
    expect(!r.ok && r.failure.kind).toBe('network');
  });
  it('sin turnos activos → lista vacía', async () => {
    const { hist, uc } = build();
    hist.entries = [entry('x', 1, 'finalizado')];
    expect(await uc.run()).toEqual({ ok: true, value: [] });
  });
  it('aheadOf', () => {
    expect(aheadOf(ticket('a', 1, 'atendiendo', { position: 0 }))).toBe(0);
    expect(aheadOf(ticket('a', 1, 'en_espera', { position: 1 }))).toBe(0);
    expect(aheadOf(ticket('a', 1, 'en_espera', { position: 5 }))).toBe(4);
  });
});
