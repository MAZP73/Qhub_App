import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { createContext, useContext, useSyncExternalStore, type ReactNode } from 'react';
import { SupabaseUserRepository } from '@/features/auth/supabase-user-repository';
import type { UserRepository } from '@/features/auth/user';
import { ProxyQhubGateway } from '@/features/gateway/proxy-gateway';
import { supabaseProxyInvoker } from '@/features/gateway/supabase-invoker';
import type { QhubGateway } from '@/features/gateway/gateway';
import { SupabaseHistoryRepository } from '@/features/history/supabase-history-repository';
import type { HistoryRepository } from '@/features/history/history';
import { SupabaseOrganizationRepository } from '@/features/organizations/supabase-organization-repository';
import type { OrganizationRepository } from '@/features/organizations/organizations';
import { SupabaseEditRequestRepository } from '@/features/permissions/supabase-edit-request-repository';
import type { EditRequestRepository } from '@/features/permissions/edit-requests';
import { SupabaseProfileRepository } from '@/features/profile/supabase-profile-repository';
import type { ProfileRepository } from '@/features/profile/profile';
import { ExpoPushService } from '@/features/push/expo-push';
import type { PushService } from '@/features/push/push';
import { LoadActiveTickets } from '@/features/tickets/active-tickets';
import type { AppEnv } from './env';
import { AppSession } from './session';

/** Raíz de composición. En tests se sustituye por fakes. */
export interface Container {
  env: AppEnv; users: UserRepository; organizations: OrganizationRepository; history: HistoryRepository; gateway: QhubGateway;
  profiles: ProfileRepository; loadActiveTickets: LoadActiveTickets; session: AppSession; editRequests: EditRequestRepository; push: PushService;
}

export function buildContainer(env: AppEnv): Container {
  const sb = createClient(env.supabaseUrl, env.supabaseKey, { auth: { storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false } });
  const users = new SupabaseUserRepository(sb);
  const organizations = new SupabaseOrganizationRepository(sb);
  const history = new SupabaseHistoryRepository(sb);
  const gateway = new ProxyQhubGateway(supabaseProxyInvoker(sb));
  const profiles = new SupabaseProfileRepository(sb);
  return { env, users, organizations, history, gateway, profiles, loadActiveTickets: new LoadActiveTickets(history, gateway, organizations), session: new AppSession(users), editRequests: new SupabaseEditRequestRepository(sb), push: new ExpoPushService(sb) };
}

const Ctx = createContext<Container | null>(null);
export const ContainerProvider = ({ value, children }: { value: Container; children: ReactNode }) => <Ctx.Provider value={value}>{children}</Ctx.Provider>;
export function useContainer(): Container { const c = useContext(Ctx); if (!c) throw new Error('ContainerProvider ausente'); return c; }
export function useAuth() {
  const { session } = useContainer();
  return useSyncExternalStore(session.subscribe, session.getSnapshot);
}
/** ¿Está eligiendo contraseña nueva tras el enlace del correo? */
export function useRecovering() {
  const { session } = useContainer();
  return useSyncExternalStore(session.subscribe, session.isRecovering);
}
/** Aviso que dejó un enlace del correo (vencido, etc.). */
export function useLinkNotice() {
  const { session } = useContainer();
  return useSyncExternalStore(session.subscribe, session.getNotice);
}
