import { ProxyQhubGateway, toProxyPayload, type ProxyRequest } from '@/features/gateway/proxy-gateway';

describe('proxy: la app nunca ve la credencial de la API', () => {
  const setup = (respond: (r: ProxyRequest) => { status: number; body: unknown }) => {
    const sent: Array<[string, ProxyRequest]> = [];
    const gw = new ProxyQhubGateway(async (org, req) => { sent.push([org, req]); return respond(req); });
    return { sent, gw };
  };
  it('traduce las llamadas del cliente a sobres para la función', async () => {
    const { sent, gw } = setup(() => ({ status: 201, body: { id: 't1', cola_id: 'q1', propietario_nombre: 'N12', usuario_id: 'u1', franja_inicio: '2026-10-20T15:00:00Z', programado: true, numero: 5, estado: 'en_espera', posicion: 1, hora_creacion: '2026-10-20T14:00:00Z' } }));
    const r = await gw.tickets('org1').create('q1', new Date('2026-10-20T15:00:00Z'));
    expect(r.ok && r.value.number).toBe(5);
    const [org, req] = sent[0]!;
    expect(org).toBe('org1');
    expect(req).toMatchObject({ method: 'POST', path: '/turnos', body: { cola_id: 'q1', franja_inicio: '2026-10-20T15:00:00.000Z' } });
    expect(JSON.stringify(toProxyPayload(org, req))).not.toMatch(/Authorization|X-Usuario/i);
  });
  it('el estado del sobre se vuelve el mismo Failure que con la API directa', async () => {
    const { gw } = setup(() => ({ status: 409, body: { detail: 'La franja está llena' } }));
    const r = await gw.tickets('org1').create('q1');
    expect(!r.ok && r.failure.kind).toBe('conflict');
    expect(!r.ok && r.failure.message).toBe('La franja está llena');
  });
  it('query de franjas', async () => {
    const { sent, gw } = setup(() => ({ status: 200, body: [{ inicio: '2026-10-20T13:00:00Z', fin: '2026-10-20T13:30:00Z', cupos: 6, ocupados: 1, disponibles: 5 }] }));
    const r = await gw.queues('org1').slots('q1', new Date(2026, 9, 20));
    expect(r.ok && r.value[0]!.available).toBe(5);
    expect(sent[0]![1].query).toEqual({ fecha: '2026-10-20' });
  });
  it('un fallo del invocador (sin red) es network', async () => {
    const gw = new ProxyQhubGateway(async () => { throw new Error('boom'); });
    const r = await gw.queues('org1').list();
    expect(!r.ok && r.failure.kind).toBe('network');
  });
  it('cada organización tiene su propio canal', async () => {
    const { sent, gw } = setup(() => ({ status: 200, body: [] }));
    await gw.queues('orgA').list(); await gw.queues('orgB').list();
    expect(sent.map((s) => s[0])).toEqual(['orgA', 'orgB']);
  });
});
