import type { SupabaseClient } from '@supabase/supabase-js';
import type { NotificationsRealtime } from './notifications';

/** Supabase Realtime sobre `notificaciones_staff` acotado a una organización. La RLS decide qué filas se entregan. */
export class SupabaseNotificationsRealtime implements NotificationsRealtime {
  constructor(private readonly sb: SupabaseClient) {}

  subscribe(orgId: string, { onChange, onStatus }: { onChange: () => void; onStatus: (s: 'connected' | 'error' | 'closed') => void }): () => void {
    const channel = this.sb
      .channel(`staff-notices:${orgId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notificaciones_staff', filter: `organizacion_id=eq.${orgId}` }, () => onChange())
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') onStatus('connected');
        else if (status === 'CLOSED') onStatus('closed');
        else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') onStatus('error');
      });
    return () => { void this.sb.removeChannel(channel); };
  }
}
