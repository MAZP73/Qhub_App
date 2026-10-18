import type { SupabaseClient, User } from '@supabase/supabase-js';
import { err, failureFromSupabase, ok, type Result } from '@qhub/core';
import type { AppUser, UserRepository } from '../domain/user';

export class SupabaseUserRepository implements UserRepository {
  constructor(private readonly sb: SupabaseClient) {}

  private toUser(u: User | null | undefined): AppUser | null {
    if (!u) return null;
    const meta = u.user_metadata as Record<string, unknown> | undefined;
    const name = [meta?.nombre, meta?.apellido].filter((x): x is string => typeof x === 'string' && x.length > 0).join(' ').trim();
    return { id: u.id, email: u.email ?? '', ...(name ? { displayName: name } : {}) };
  }
  private async run<T>(body: () => Promise<T>): Promise<Result<T>> { try { return ok(await body()); } catch (e) { return err(failureFromSupabase(e)); } }

  onAuthChange(cb: (u: AppUser | null) => void) {
    void this.sb.auth.getSession().then(({ data }) => cb(this.toUser(data.session?.user)));
    const { data } = this.sb.auth.onAuthStateChange((_e, s) => cb(this.toUser(s?.user)));
    return () => data.subscription.unsubscribe();
  }
  signIn(email: string, password: string) {
    return this.run(async () => {
      const { data, error } = await this.sb.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
      return this.toUser(data.user)!;
    });
  }
  signUp(i: { email: string; password: string; firstName: string; lastName: string }) {
    return this.run(async () => {
      const { data, error } = await this.sb.auth.signUp({ email: i.email.trim(), password: i.password, options: { data: { nombre: i.firstName.trim(), apellido: i.lastName.trim() } } });
      if (error) throw error;
      return data.session ? this.toUser(data.user) : null;
    });
  }
  signOut() { return this.run(async () => { const { error } = await this.sb.auth.signOut(); if (error) throw error; }); }
}
