import type { SupabaseClient } from '@supabase/supabase-js';
import { ExpoPushService } from './expo-push';

jest.mock('expo-device', () => ({ isDevice: true }));
jest.mock('expo-constants', () => ({ __esModule: true, default: { expoConfig: { extra: { eas: { projectId: 'proj-1' } } } } }));
const mockNotifications = {
  setNotificationHandler: jest.fn(), setNotificationChannelAsync: jest.fn(), AndroidImportance: { MAX: 5 },
  getPermissionsAsync: jest.fn(), requestPermissionsAsync: jest.fn(), getExpoPushTokenAsync: jest.fn(),
};
jest.mock('expo-notifications', () => mockNotifications);

function client() {
  const rpc = jest.fn().mockResolvedValue({ error: null });
  const eq = jest.fn().mockResolvedValue({ error: null });
  const del = jest.fn(() => ({ eq }));
  const sb = { rpc, from: jest.fn(() => ({ delete: del })) } as unknown as SupabaseClient;
  return { sb, rpc, eq, from: (sb as unknown as { from: jest.Mock }).from };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockNotifications.getPermissionsAsync.mockResolvedValue({ status: 'granted' });
  mockNotifications.getExpoPushTokenAsync.mockResolvedValue({ data: 'ExponentPushToken[abc]' });
});

describe('ExpoPushService', () => {
  it('con permiso registra el teléfono con su token', async () => {
    const { sb, rpc } = client();
    await new ExpoPushService(sb).enable();
    expect(mockNotifications.getExpoPushTokenAsync).toHaveBeenCalledWith({ projectId: 'proj-1' });
    expect(rpc).toHaveBeenCalledWith('registrar_dispositivo_push', { p_token: 'ExponentPushToken[abc]', p_plataforma: expect.stringMatching(/android|ios/) });
  });
  it('pide el permiso si aún no se dio y no registra si lo niegan', async () => {
    mockNotifications.getPermissionsAsync.mockResolvedValue({ status: 'undetermined' });
    mockNotifications.requestPermissionsAsync.mockResolvedValue({ status: 'denied' });
    const { sb, rpc } = client();
    await new ExpoPushService(sb).enable();
    expect(mockNotifications.requestPermissionsAsync).toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
  });
  it('nunca lanza: si Expo falla, la app sigue', async () => {
    mockNotifications.getExpoPushTokenAsync.mockRejectedValue(new Error('sin FCM'));
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { sb, rpc } = client();
    await expect(new ExpoPushService(sb).enable()).resolves.toBeUndefined();
    expect(rpc).not.toHaveBeenCalled();
    warn.mockRestore();
  });
  it('disable borra el token registrado; sin registro no hace nada', async () => {
    const { sb, eq, from } = client();
    const s = new ExpoPushService(sb);
    await s.disable();
    expect(from).not.toHaveBeenCalled();
    await s.enable(); await s.disable();
    expect(eq).toHaveBeenCalledWith('token', 'ExponentPushToken[abc]');
  });
});
