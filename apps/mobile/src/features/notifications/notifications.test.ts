import { styleOf } from '@/features/notifications/NotificationsScreen';

describe('avisos', () => {
  it('ícono y color por tipo', () => {
    expect(styleOf('turno_llamado')).toEqual({ icon: 'call', color: 'link' });
    expect(styleOf('turno_no_show').icon).toBe('noshow');
    expect(styleOf(null).icon).toBe('info');
  });
});
