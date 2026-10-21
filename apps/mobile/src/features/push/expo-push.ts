import type { SupabaseClient } from '@supabase/supabase-js';
import type { PushService } from './push';

/** Push con Expo. Los módulos nativos se cargan al usarlos: en pruebas y en entornos sin push no se tocan. */
export class ExpoPushService implements PushService {
  private token: string | null = null;
  private handlerSet = false;

  constructor(private readonly sb: SupabaseClient) {}

  async enable() {
    try {
      /* eslint-disable @typescript-eslint/no-require-imports */
      const Notifications = require('expo-notifications') as typeof import('expo-notifications');
      const Device = require('expo-device') as typeof import('expo-device');
      const Constants = (require('expo-constants') as typeof import('expo-constants')).default;
      const { Platform } = require('react-native') as typeof import('react-native');
      if (!Device.isDevice || (Platform.OS !== 'android' && Platform.OS !== 'ios')) return;   // el emulador no recibe push
      if (!this.handlerSet) {
        // Con la app abierta el aviso también se muestra (el sistema solo lo muestra solo si la app está cerrada o en segundo plano).
        Notifications.setNotificationHandler({ handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }) });
        this.handlerSet = true;
      }
      if (Platform.OS === 'android') {
        await Notifications.setNotificationChannelAsync('turnos', { name: 'Turnos', importance: Notifications.AndroidImportance.MAX, vibrationPattern: [0, 250, 250, 250] });
      }
      let { status } = await Notifications.getPermissionsAsync();
      if (status !== 'granted') status = (await Notifications.requestPermissionsAsync()).status;
      if (status !== 'granted') return;
      const projectId = (Constants.expoConfig?.extra as { eas?: { projectId?: string } } | undefined)?.eas?.projectId ?? Constants.easConfig?.projectId;
      if (!projectId) return;
      const { data: token } = await Notifications.getExpoPushTokenAsync({ projectId });
      const { error } = await this.sb.rpc('registrar_dispositivo_push', { p_token: token, p_plataforma: Platform.OS });
      if (error) throw error;
      this.token = token;
    } catch (e) {
      // Sin push la app funciona igual (se refresca sola): el detalle va a la consola, no a la pantalla.
      console.warn('[qhub] push no disponible', e instanceof Error ? e.message : e);
    }
  }

  async disable() {
    const token = this.token;
    this.token = null;
    if (!token) return;
    try { await this.sb.from('dispositivos_push').delete().eq('token', token); } catch { /* se limpia solo cuando Expo reporta el token inválido */ }
  }
}
