import { err, notFoundFailure, ok, type Failure, type Result } from '@qhub/core';
import type {
  AppNotification, CreateQueueInput, QueueNow, SlotBlock, NotificationRepository, Queue, QueueLimit, QueueRepository, QueueState, Schedule, ScheduleInput, Slot, Ticket, TicketFilter, TicketRepository, TicketStatus,
} from '@qhub/api-client';
import type { AppEnv } from '@/app/env';
import { AppSession } from '@/app/session';
import type { Container } from '@/app/container';
import type { AppUser, UserRepository } from '@/features/auth/user';
import type { QhubGateway } from '@/features/gateway/gateway';
import type { HistoryEntry, HistoryRepository } from '@/features/history/history';
import type { OrganizationRepository, OrganizationSummary } from '@/features/organizations/organizations';
import type { EditRequest, EditRequestRepository } from '@/features/permissions/edit-requests';
import { EMPTY_PROFILE, type Profile } from '@qhub/core';
import type { ProfileRepository } from '@/features/profile/profile';
import type { PushService } from '@/features/push/push';
import { LoadActiveTickets } from '@/features/tickets/active-tickets';

export const testEnv: AppEnv = { appEnv: 'production', supabaseUrl: 'https://x.supabase.co', supabaseKey: 'sb_publishable_test' };
export const camila: AppUser = { id: 'u1', email: 'camila@x.co', displayName: 'Camila Ríos' };
export const notaria: OrganizationSummary = { id: 'org1', code: 'QH-N12ABC', name: 'Notaría 12', slug: 'notaria-12', address: 'Cra. 13 #54-21', city: 'Bogotá', phone: '601 555 0100' };
export const banco: OrganizationSummary = { id: 'org2', code: 'QH-BCO234', name: 'Banco Cooperativo', slug: 'banco', city: 'Quito' };

export class FakeUserRepository implements UserRepository {
  user: AppUser | null; listeners = new Set<(u: AppUser | null) => void>(); signInFailure: Failure | null = null; calls: string[] = [];
  constructor(user: AppUser | null = null) { this.user = user; }
  onAuthChange(cb: (u: AppUser | null) => void) { this.listeners.add(cb); cb(this.user); return () => { this.listeners.delete(cb); }; }
  private emit() { this.listeners.forEach((l) => l(this.user)); }
  async signIn(email: string): Promise<Result<AppUser>> { this.calls.push(`signIn:${email}`); if (this.signInFailure) return err(this.signInFailure); this.user = { id: 'u1', email, displayName: 'Camila Ríos' }; this.emit(); return ok(this.user); }
  async signUp(i: { email: string }): Promise<Result<AppUser | null>> { this.calls.push(`signUp:${i.email}`); return ok(null); }
  async signOut(): Promise<Result<void>> { this.calls.push('signOut'); this.user = null; this.emit(); return ok(undefined); }
  linkFailure: Failure | null = null; resetFailure: Failure | null = null; passwordFailure: Failure | null = null;
  async requestPasswordReset(email: string): Promise<Result<void>> { this.calls.push(`reset:${email}`); return this.resetFailure ? err(this.resetFailure) : ok(undefined); }
  async openLinkSession(l: { accessToken: string }): Promise<Result<void>> { this.calls.push(`link:${l.accessToken}`); if (this.linkFailure) return err(this.linkFailure); this.user = { id: 'u1', email: 'camila@x.co', displayName: 'Camila Ríos' }; this.emit(); return ok(undefined); }
  async updatePassword(p: string): Promise<Result<void>> { this.calls.push(`password:${p}`); return this.passwordFailure ? err(this.passwordFailure) : ok(undefined); }
}

export class FakeOrganizationRepository implements OrganizationRepository {
  linkedSet = new Set<string>(); searches: string[] = []; searchFailure: Failure | null = null; linkFailure: Failure | null = null;
  constructor(public orgs: OrganizationSummary[] = [notaria, banco]) {}
  async search(query: string): Promise<Result<OrganizationSummary[]>> {
    this.searches.push(query);
    if (this.searchFailure) return err(this.searchFailure);
    const q = query.toLowerCase();
    return ok(this.orgs.filter((o) => !q || o.name.toLowerCase().includes(q) || (o.city ?? '').toLowerCase().includes(q) || (o.code ?? '').toLowerCase() === q).map((o) => ({ ...o, linked: this.linkedSet.has(o.id) })));
  }
  async get(id: string): Promise<Result<OrganizationSummary>> { const o = this.orgs.find((x) => x.id === id); return o ? ok(o) : err(notFoundFailure()); }
  async queuePrefixes() { return ok({ q1: 'E' } as Record<string, string>); }
  async linked() { return ok(this.orgs.filter((o) => this.linkedSet.has(o.id)).map((o) => ({ ...o, linked: true }))); }
  async link(id: string): Promise<Result<void>> { if (this.linkFailure) return err(this.linkFailure); this.linkedSet.add(id); return ok(undefined); }
  async unlink(id: string): Promise<Result<void>> { this.linkedSet.delete(id); return ok(undefined); }
}

export class FakeHistoryRepository implements HistoryRepository {
  constructor(public entries: HistoryEntry[] = []) {}
  async list() { return ok([...this.entries]); }
}

export const entry = (id: string, n: number, status: TicketStatus, o: Partial<HistoryEntry> = {}): HistoryEntry => ({
  ticketId: id, organizationId: 'org1', queueId: 'q1', number: n, status, createdAt: new Date(), queueName: 'Escrituras', organizationName: 'Notaría 12', ...o,
});
export const ticket = (id: string, n: number, status: TicketStatus, o: Partial<Ticket> = {}): Ticket => ({
  id, queueId: 'q1', ownerName: 'Notaría 12', userId: 'u1', slotStart: new Date(), scheduled: false, number: n, status, position: 1, createdAt: new Date(), calledAt: null, finishedAt: null, agentId: null, ...o,
});

export class FakeQueues implements QueueRepository {
  slotRequests: number[] = [];
  /** Si se define, la franja con cupo llega bloqueada por el servidor (descanso, muy pronto…). */
  slotBlock: SlotBlock | null = null;
  nowInfo: QueueNow = { queueId: 'q1', open: true, reason: null, reopensAt: null, ahead: 2, waitMinutes: 20, alreadyHasNow: false, breaks: [], marginMinutes: 3 };
  async now(): Promise<Result<QueueNow>> { return ok(this.nowInfo); }
  async list() { return ok<Queue[]>([{ id: 'q1', ownerName: 'Notaría 12', name: 'Escrituras', description: 'Con cita', active: true }, { id: 'q2', ownerName: 'Notaría 12', name: 'Archivo', description: null, active: false }]); }
  async get(): Promise<Result<Queue>> { return err(notFoundFailure()); }
  async create(_i: CreateQueueInput): Promise<Result<Queue>> { throw new Error('no usado'); }
  async update(): Promise<Result<Queue>> { throw new Error('no usado'); }
  async delete(): Promise<Result<void>> { throw new Error('no usado'); }
  async limit(): Promise<Result<QueueLimit>> { throw new Error('no usado'); }
  async schedule(): Promise<Result<Schedule>> {
    return ok({ queueId: 'q1', timeZone: 'America/Bogota', opens: '08:00:00', closes: '17:00:00', slotMinutes: 30, days: [1, 2, 3, 4, 5, 6, 7], turnMinutes: 10, stations: 2, dailyCapacity: 0, maxDaysAhead: 7, slotsPerDay: 18, capacityPerSlot: 6, turnsPerDay: 108 });
  }
  async replaceSchedule(_id: string, _i: ScheduleInput): Promise<Result<Schedule>> { throw new Error('no usado'); }
  async slots(_id: string, date?: Date): Promise<Result<Slot[]>> {
    this.slotRequests.push(date?.getDate() ?? 0);
    const d = date ?? new Date();
    const at = (h: number, m: number) => new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), h, m));
    return ok([
      { start: at(13, 0), end: at(13, 30), capacity: 6, taken: 6, available: 0 },
      { start: at(13, 30), end: at(14, 0), capacity: 6, taken: 4, available: 2, blocked: this.slotBlock },
    ]);
  }
  async state(id: string): Promise<Result<QueueState>> { return ok({ queueId: id, waiting: 5, serving: 1 }); }
}

export class FakeTickets implements TicketRepository {
  created: Array<{ queue: string; slot?: Date }> = []; createFailure: Failure | null = null; calls: string[] = []; stored = new Map<string, Ticket>(); getFailure: Failure | null = null;
  async create(queue: string, slot?: Date): Promise<Result<Ticket>> {
    this.created.push({ queue, slot });
    if (this.createFailure) return err(this.createFailure);
    return ok(ticket('t-new', 23, 'en_espera', { scheduled: !!slot }));
  }
  async mine() { return ok([...this.stored.values()]); }
  async list(_f: TicketFilter): Promise<Result<Ticket[]>> { throw new Error('no usado'); }
  async get(id: string): Promise<Result<Ticket>> { if (this.getFailure) return err(this.getFailure); const t = this.stored.get(id); return t ? ok(t) : err(notFoundFailure()); }
  private act(name: string, id: string, status: TicketStatus): Result<Ticket> { this.calls.push(`${name}:${id}`); const next = { ...this.stored.get(id)!, status }; this.stored.set(id, next); return ok(next); }
  async postpone(id: string) { return this.act('postpone', id, 'en_espera'); }
  async cancel(id: string) { return this.act('cancel', id, 'cancelado'); }
  async call(): Promise<Result<Ticket>> { throw new Error('no usado'); }
  async finish(): Promise<Result<Ticket>> { throw new Error('no usado'); }
  async noShow(): Promise<Result<Ticket>> { throw new Error('no usado'); }
}

export class FakeNotifications implements NotificationRepository {
  read: string[] = [];
  constructor(public items: AppNotification[] = []) {}
  async list() { return ok([...this.items]); }
  async markRead(id: string): Promise<Result<AppNotification>> { this.read.push(id); return ok({ ...this.items.find((n) => n.id === id)!, read: true }); }
  async delete(): Promise<Result<void>> { return ok(undefined); }
}

export class FakeProfileRepository implements ProfileRepository {
  calls: string[] = [];
  updateFailure: Failure | null = null;
  constructor(public data: Profile = { ...EMPTY_PROFILE, firstName: 'Camila', lastName: 'Ríos', phone: '+57 3001112233', country: 'CO', city: 'Bogotá', timeZone: 'America/Bogota' }, public managed = false) {}
  async get(): Promise<Result<Profile>> { return ok({ ...this.data }); }
  async update(p: Profile): Promise<Result<Profile>> { this.calls.push(`update:${p.firstName}:${p.city}`); if (this.updateFailure) return err(this.updateFailure); this.data = { ...p }; return ok({ ...p }); }
  async managementStatus(): Promise<Result<boolean>> { return ok(this.managed); }
}

export class FakeGateway implements QhubGateway {
  constructor(public queueRepo = new FakeQueues(), public ticketRepo = new FakeTickets(), public notificationRepo = new FakeNotifications()) {}
  queues() { return this.queueRepo; }
  tickets() { return this.ticketRepo; }
  notifications() { return this.notificationRepo; }
}

export class FakeEditRequests implements EditRequestRepository {
  calls: string[] = [];
  constructor(public items: EditRequest[] = []) {}
  async pending(): Promise<Result<EditRequest[]>> { return ok([...this.items]); }
  async respond(id: string, approve: boolean): Promise<Result<void>> { this.calls.push(`${approve ? 'approve' : 'reject'}:${id}`); this.items = this.items.filter((e) => e.id !== id); return ok(undefined); }
}

export interface TestContainer extends Container { fakes: { users: FakeUserRepository; orgs: FakeOrganizationRepository; history: FakeHistoryRepository; gateway: FakeGateway; editRequests: FakeEditRequests; profiles: FakeProfileRepository; push: FakePush } }
export class FakePush implements PushService {
  calls: string[] = [];
  async enable() { this.calls.push('enable'); }
  async disable() { this.calls.push('disable'); }
}

export function makeContainer(o: Partial<TestContainer['fakes']> = {}): TestContainer {
  const users = o.users ?? new FakeUserRepository();
  const orgs = o.orgs ?? new FakeOrganizationRepository();
  const history = o.history ?? new FakeHistoryRepository();
  const gateway = o.gateway ?? new FakeGateway();
  const editRequests = o.editRequests ?? new FakeEditRequests();
  const profiles = o.profiles ?? new FakeProfileRepository();
  const push = o.push ?? new FakePush();
  return { env: testEnv, users, organizations: orgs, history, gateway, profiles, loadActiveTickets: new LoadActiveTickets(history, gateway, orgs), session: new AppSession(users), editRequests, push, fakes: { users, orgs, history, gateway, editRequests, profiles, push } };
}
