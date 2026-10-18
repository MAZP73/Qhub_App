import { expiresIn } from './edit-requests';

describe('solicitudes de edición', () => {
  const now = new Date('2026-10-18T12:00:00Z');
  const at = (min: number) => ({ id: 'r', organization: 'Notaría 12', reason: null, expiresAt: new Date(now.getTime() + min * 60000) });
  it('dice cuánto falta para que venza', () => {
    expect(expiresIn(at(40), now)).toBe('Vence en 40 min');
    expect(expiresIn(at(300), now)).toBe('Vence en 5 h');
    expect(expiresIn(at(-5), now)).toBe('Vencida');
  });
});
