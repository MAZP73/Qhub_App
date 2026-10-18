import 'dart:async';

import 'package:qhub_admin/app/env.dart';
import 'package:qhub_admin/features/qhub/domain/qhub_connection.dart';
import 'package:qhub_admin/features/staff/domain/staff.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

final testEnv = AppEnv.fromMap({
  'QHUB_API_BASE_URL': 'http://api.test',
  'QHUB_WS_BASE_URL': 'ws://api.test',
  'SUPABASE_URL': 'https://x.supabase.co',
  'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test',
});

const org = Organization(id: 'org1', name: 'Notaría 12', slug: 'notaria-12', timeZone: 'America/Guayaquil');

class FakeStaffRepository implements StaffRepository {
  FakeStaffRepository({StaffUser? user, List<Membership> memberships = const []})
      : userState = user,
        _memberships = [...memberships];

  StaffUser? userState;
  final List<Membership> _memberships;
  final _auth = StreamController<StaffUser?>.broadcast();
  Failure? signInFailure;
  final calls = <String>[];
  final prefixes = <String, String>{};
  final audits = <String>[];
  final invitationsList = <Invitation>[];

  @override
  StaffUser? get currentUser => userState;

  @override
  Stream<StaffUser?> authChanges() async* {
    yield userState;
    yield* _auth.stream;
  }

  @override
  Future<Result<StaffUser>> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInFailure != null) return Result.err(signInFailure!);
    userState = StaffUser(id: 'u1', email: email, displayName: 'Ana Gómez');
    _auth.add(userState);
    return Result.ok(userState!);
  }

  @override
  Future<Result<StaffUser?>> signUp({required String email, required String password, required String firstName, required String lastName}) async {
    calls.add('signUp:$email');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signOut() async {
    calls.add('signOut');
    userState = null;
    _auth.add(null);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Membership>>> memberships() async => Result.ok([..._memberships]);

  @override
  Future<Result<String>> createOrganization({required String name, required String slug, String? city, String? country, String timeZone = 'America/Guayaquil'}) async {
    calls.add('createOrg:$name');
    _memberships.add(Membership(organization: Organization(id: 'org-new', name: name, slug: slug, timeZone: timeZone), role: OrgRole.admin));
    return const Result.ok('org-new');
  }

  @override
  Future<Result<String>> acceptInvitation(String token) async {
    calls.add('accept:$token');
    if (token == 'bad') return const Result.err(NotFoundFailure('Invitación inválida, vencida o para otro correo'));
    _memberships.add(const Membership(organization: org, role: OrgRole.agente));
    return const Result.ok('org1');
  }

  @override
  Future<Result<Organization>> updateOrganization(String id, {String? name, String? city, String? country}) async =>
      Result.ok(Organization(id: id, name: name ?? org.name, slug: org.slug, timeZone: org.timeZone));

  Failure? publishFailure;
  var linked = false;

  @override
  Future<Result<void>> publishToMobile(String orgId, {required String identifier, required String password}) async {
    calls.add('publish:$identifier');
    if (publishFailure != null) return Result.err(publishFailure!);
    linked = true;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> unpublishFromMobile(String orgId) async {
    calls.add('unpublish');
    linked = false;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Member>>> members(String orgId) async => const Result.ok([
        Member(userId: 'u1', name: 'Ana Gómez', role: OrgRole.admin, active: true),
        Member(userId: 'u2', name: 'Luis Vera', role: OrgRole.agente, active: true),
      ]);

  @override
  Future<Result<void>> updateMember(String orgId, String userId, {OrgRole? role, bool? active}) async {
    calls.add('updateMember:$userId:${role?.wire}:$active');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> removeMember(String orgId, String userId) async => const Result.ok(null);

  @override
  Future<Result<Invitation>> invite(String orgId, {required String email, required OrgRole role}) async {
    calls.add('invite:$email:${role.wire}');
    final inv = Invitation(id: 'i${invitationsList.length}', email: email, role: role, token: 'tok-${invitationsList.length}', expiresAt: DateTime.now().add(const Duration(days: 7)));
    invitationsList.add(inv);
    return Result.ok(inv);
  }

  @override
  Future<Result<List<Invitation>>> invitations(String orgId) async => Result.ok([...invitationsList]);

  @override
  Future<Result<Map<String, String>>> queuePrefixes(String orgId) async => Result.ok({...prefixes});

  @override
  Future<Result<void>> setQueuePrefix(String orgId, String queueId, String prefix) async {
    prefixes[queueId] = prefix.toUpperCase();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> audit(String orgId, String action, {String? entity, String? entityId, Map<String, Object?> detail = const {}}) async {
    audits.add(action);
    return const Result.ok(null);
  }
}

class MemoryCredentialStore implements CredentialStore {
  final data = <String, QhubCredential>{};
  @override
  Future<QhubCredential?> read(String orgId) async => data[orgId];
  @override
  Future<void> write(String orgId, QhubCredential c) async => data[orgId] = c;
  @override
  Future<void> delete(String orgId) async => data.remove(orgId);
}

class FakeAuthRepository implements AuthRepository {
  Failure? loginFailure;
  final logins = <String>[];
  var loginCount = 0;

  @override
  Future<Result<AuthToken>> login({required String identifier, required String password}) async {
    logins.add(identifier);
    loginCount++;
    if (loginFailure != null) return Result.err(loginFailure!);
    return Result.ok(AuthToken(accessToken: 'tok$loginCount', expiresIn: 3600, issuedAt: DateTime.now()));
  }

  @override
  Future<Result<Registration>> register(RegisterInput input) async => Result.ok(Registration(
        accountType: input.accountType, accountId: 'acc1', username: input.username, email: input.email,
        queueLimit: 6, createdAt: DateTime.now(), companyName: input.companyName));
}

Queue makeQueue(String id, String name, {bool active = true}) => Queue(id: id, ownerName: 'Notaría 12', name: name, active: active);

Ticket makeTicket(String id, int n, TicketStatus s, {String queue = 'q1', int pos = 1, DateTime? slot, DateTime? created, DateTime? called, DateTime? finished, bool scheduled = false}) {
  final base = created ?? DateTime.utc(2026, 10, 20, 14);
  return Ticket(
    id: id, queueId: queue, ownerName: 'Notaría 12', userId: 'cli-$n',
    slotStart: slot ?? DateTime.utc(2026, 10, 20, 14), scheduled: scheduled, number: n, status: s,
    position: pos, createdAt: base, calledAt: called, finishedAt: finished,
  );
}

class FakeQueueRepository implements QueueRepository {
  FakeQueueRepository({List<Queue>? queues, this.limitValue}) : queues = queues ?? [makeQueue('q1', 'Caja 1')];
  final List<Queue> queues;
  QueueLimit? limitValue;
  final calls = <String>[];
  ScheduleInput? lastSchedule;
  CreateQueueInput? lastCreate;
  Failure? createFailure;

  @override
  Future<Result<List<Queue>>> list({bool? active}) async => Result.ok([...queues]);
  @override
  Future<Result<Queue>> get(String id) async => Result.ok(queues.firstWhere((q) => q.id == id));
  @override
  Future<Result<Queue>> create(CreateQueueInput input) async {
    lastCreate = input;
    if (createFailure != null) return Result.err(createFailure!);
    final q = makeQueue('q${queues.length + 1}', input.name);
    queues.add(q);
    return Result.ok(q);
  }

  @override
  Future<Result<Queue>> update(String id, {String? name, String? description, bool? active}) async {
    calls.add('update:$id:$name:$active');
    return Result.ok(queues.firstWhere((q) => q.id == id));
  }

  @override
  Future<Result<void>> delete(String id) async {
    calls.add('delete:$id');
    return const Result.ok(null);
  }

  @override
  Future<Result<QueueLimit>> limit() async =>
      Result.ok(limitValue ?? QueueLimit(accountType: AccountType.empresa, limit: 6, active: queues.where((q) => q.active).length, available: 6 - queues.where((q) => q.active).length));
  @override
  Future<Result<Schedule>> schedule(String id) async => Result.ok(Schedule(
      queueId: id, timeZone: 'America/Guayaquil', opens: '08:00:00', closes: '17:00:00', slotMinutes: 30,
      days: const [1, 2, 3, 4, 5], turnMinutes: 10, stations: 2, dailyCapacity: 0, maxDaysAhead: 7));
  @override
  Future<Result<Schedule>> replaceSchedule(String id, ScheduleInput input) async {
    lastSchedule = input;
    return schedule(id);
  }

  @override
  Future<Result<List<Slot>>> slots(String id, {DateTime? date}) async => const Result.ok([]);
  @override
  Future<Result<QueueState>> state(String id) async => Result.ok(QueueState(queueId: id, waiting: 3, serving: 1));
}

class FakeTicketRepository implements TicketRepository {
  FakeTicketRepository(this.tickets);
  List<Ticket> tickets;
  final calls = <String>[];
  Failure? actionFailure;
  final filters = <TicketFilter>[];

  Ticket _replace(String id, TicketStatus s, {DateTime? called, DateTime? finished}) {
    final i = tickets.indexWhere((t) => t.id == id);
    final old = tickets[i];
    final next = Ticket(
      id: old.id, queueId: old.queueId, ownerName: old.ownerName, userId: old.userId, slotStart: old.slotStart,
      scheduled: old.scheduled, number: old.number, status: s, position: old.position, createdAt: old.createdAt,
      calledAt: called ?? old.calledAt, finishedAt: finished ?? old.finishedAt, agentId: 'u1');
    tickets = [...tickets]..[i] = next;
    return next;
  }

  Future<Result<Ticket>> _do(String name, String id, TicketStatus s) async {
    calls.add('$name:$id');
    if (actionFailure != null) return Result.err(actionFailure!);
    return Result.ok(_replace(id, s, called: s == TicketStatus.atendiendo ? DateTime.now() : null, finished: s == TicketStatus.finalizado ? DateTime.now() : null));
  }

  @override
  Future<Result<Ticket>> create(String queueId, {DateTime? slotStart}) async => Result.ok(tickets.first);
  @override
  Future<Result<List<Ticket>>> mine({int limit = 500, int offset = 0}) async => Result.ok(tickets);
  @override
  Future<Result<List<Ticket>>> list(TicketFilter filter) async {
    filters.add(filter);
    final all = tickets.where((t) => filter.queueId == null || t.queueId == filter.queueId).toList();
    return Result.ok(all.skip(filter.offset).take(filter.limit).toList());
  }

  @override
  Future<Result<Ticket>> get(String id) async => Result.ok(tickets.firstWhere((t) => t.id == id));
  @override
  Future<Result<Ticket>> postpone(String id) => _do('postpone', id, TicketStatus.enEspera);
  @override
  Future<Result<Ticket>> cancel(String id) => _do('cancel', id, TicketStatus.cancelado);
  @override
  Future<Result<Ticket>> call(String id) => _do('call', id, TicketStatus.atendiendo);
  @override
  Future<Result<Ticket>> finish(String id) => _do('finish', id, TicketStatus.finalizado);
  @override
  Future<Result<Ticket>> noShow(String id) => _do('noShow', id, TicketStatus.noShow);
}

class FakeRealtime implements RealtimeRepository {
  final events = StreamController<QueueEvent>.broadcast();
  final statusCtl = StreamController<ConnectionStatus>.broadcast();
  @override
  Stream<QueueEvent> queueEvents(String queueId) => events.stream;
  @override
  Stream<AppNotification> notifications() => const Stream.empty();
  @override
  Stream<ConnectionStatus> get status => statusCtl.stream;
}

class FakeHealth implements HealthRepository {
  @override
  Future<Result<Readiness>> ready() async => const Result.ok(Readiness(supabase: 'ok', rabbitmq: 'ok'));
}

class QueueLimitFake {
  const QueueLimitFake();
  QueueLimit get value => const QueueLimit(accountType: AccountType.empresa, limit: 6, active: 6, available: 0);
}
