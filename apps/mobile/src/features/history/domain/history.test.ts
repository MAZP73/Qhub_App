import { dayLabel, groupByDay } from '@/features/history/domain/history';

describe('historial', () => {
  it('agrupa por día, más reciente primero, y etiqueta Hoy/Ayer', () => {
    const now = new Date(2026, 9, 20, 12);
    const g = groupByDay([
      { createdAt: new Date(2026, 9, 19, 9), id: 'a' }, { createdAt: now, id: 'b' }, { createdAt: new Date(2026, 9, 20, 8), id: 'c' },
    ]);
    expect(g[0]!.items.map((i) => i.id)).toEqual(['b', 'c']);
    expect(dayLabel(new Date(2026, 9, 20), now)).toBe('Hoy');
    expect(dayLabel(new Date(2026, 9, 19), now)).toBe('Ayer');
    expect(dayLabel(new Date(2026, 9, 3), now)).toBe('3 oct');
  });
});
