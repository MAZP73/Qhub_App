import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { createContext, useContext, useSyncExternalStore, type ReactNode } from 'react';
import { SupabaseUserRepository } from '@/features/auth/data/supabase-user-repository';
import type { UserRepository } from '@/features/auth/domain/user';
import { ProxyQhubGateway } from '@/features/gateway/data/proxy-gateway';
import { supabaseProxyInvoker } from '@/features/gateway/data/supabase-invoker';
import type { QhubGateway } from '@/features/gateway/domain/gateway';
import { SupabaseHistoryRepository } from '@/features/history/data/supabase-history-repository';
import type { HistoryRepository } from '@/features/history/domain/history';
import { SupabaseOrganizationRepository } from '@/features/organizations/data/supabase-organization-repository';
import type { OrganizationRepository } from '@/features/organizations/domain/organizations';
import { LoadActiveTickets } from '@/features/tickets/domain/active-tickets';
import type { AppEnv } from './env';
import { AppSession } from './session';

/** Raíz de composición. En tests se sustituye por fakes. */
export interface Container {
  env: AppEnv; users: UserRepository; organizations: OrganizationRepository; history: HistoryRepository; gateway: QhubGateway;
  loadActiveTickets: LoadActiveTickets; session: AppSession;
}

export function buildContainer(env: AppEnv): Container {
  const sb = createClient(env.supabaseUrl, env.supabaseKey, { auth: { storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false } });
  const users = new SupabaseUserRepository(sb);
  const organizations = new SupabaseOrganizationRepository(sb);
  const history = new SupabaseHistoryRepository(sb);
  const gateway = new ProxyQhubGateway(supabaseProxyInvoker(sb));
  return { env, users, organizations, history, gateway, loadActiveTickets: new LoadActiveTickets(history, gateway, organizations), session: new AppSession(users) };
}

const Ctx = createContext<Container | null>(null);
export const ContainerProvider = ({ value, children }: { value: Container; children: ReactNode }) => <Ctx.Provider value={value}>{children}</Ctx.Provider>;
export function useContainer(): Container { const c = useContext(Ctx); if (!c) throw new Error('ContainerProvider ausente'); return c; }
export function useAuth() {
  const { session } = useContainer();
  return useSyncExternalStore(session.subscribe, session.getSnapshot);
}
