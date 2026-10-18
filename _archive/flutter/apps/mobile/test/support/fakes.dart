import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_mobile/app/env.dart';
import 'package:qhub_mobile/app/providers.dart';
import 'package:qhub_mobile/features/auth/domain/user.dart';
import 'package:qhub_mobile/features/gateway/domain/gateway.dart';
import 'package:qhub_mobile/features/history/domain/history.dart';
import 'package:qhub_mobile/features/organizations/domain/organizations.dart';

final testEnv = AppEnv.fromMap({'SUPABASE_URL': 'https://x.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test'});

const notaria = OrganizationSummary(id: 'org1', name: 'Notaría 12', slug: 'notaria-12', address: 'Cra. 13 #54-21', city: 'Bogotá', phone: '601 555 0100');
const banco = OrganizationSummary(id: 'org2', name: 'Banco Cooperativo', slug: 'banco', city: 'Quito');

class FakeUserRepository implements UserRepository {
  FakeUserRepository({AppUser? user}) : userState = user;
  AppUser? userState;
  final _ctl = StreamController<AppUser?>.broadcast();
  Failure? signInFailure;
  final calls = <String>[];

  @override
  AppUser? get currentUser => userState;
  @override
  Stream<AppUser?> authChanges() async* {
    yield userState;
    yield* _ctl.stream;
  }

  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInFailure != null) return Result.err(signInFailure!);
    userState = AppUser(id: 'u1', email: email, displayName: 'Camila Ríos');
    _ctl.add(userState);
    return Result.ok(userState!);
  }

  @override
  Future<Result<AppUser?>> signUp({required String email, required String password, required String firstName, required String lastName}) async {
    calls.add('signUp:$email');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> signOut() async {
    calls.add('signOut');
    userState = null;
    _ctl.add(null);
    return const Result.ok(null);
  }
}

class FakeOrganizationRepository implements OrganizationRepository {
  FakeOrganizationRepository({List<OrganizationSummary>? orgs}) : orgs = orgs ?? [notaria, banco];
  final List<OrganizationSummary> orgs;
  final favorites = <String>{};
  final searches = <String>[];
  Failure? searchFailure;

  @override
  Future<Result<List<OrganizationSummary>>> search(String query) async {
    searches.add(query);
    if (searchFailure != null) return Result.err(searchFailure!);
    final q = query.toLowerCase();
    return Result.ok(orgs.where((o) => q.isEmpty || o.name.toLowerCase().contains(q) || (o.city ?? '').toLowerCase().contains(q)).toList());
  }

  @override
  Future<Result<OrganizationSummary>> get(String id) async => Result.ok(orgs.firstWhere((o) => o.id == id));
  @override
  Future<Result<Map<String, String>>> queuePrefixes(String organizationId) async => const Result.ok({'q1': 'E'});
  @override
  Future<Result<Set<String>>> favoriteIds() async => Result.ok({...favorites});
  @override
  Future<Result<void>> setFavorite(String organizationId, bool favorite) async {
    favorite ? favorites.add(organizationId) : favorites.remove(organizationId);
    return const Result.ok(null);
  }
}

class FakeHistoryRepository implements HistoryRepository {
  FakeHistoryRepository([List<HistoryEntry>? entries]) : entries = entries ?? [];
  List<HistoryEntry> entries;
  @override
  Future<Result<List<HistoryEntry>>> list({int limit = 100}) async => Result.ok([...entries]);
}

HistoryEntry entry(String id, int n, TicketStatus s, {String org = 'org1', String queue = 'q1', DateTime? at, String orgName = 'Notaría 12', String queueName = 'Escrituras'}) => HistoryEntry(
      ticketId: id, organizationId: org, queueId: queue, number: n, status: s, createdAt: at ?? DateTime.now(),
      queueName: queueName, organizationName: orgName,
    );

Ticket ticket(String id, int n, TicketStatus s, {int pos = 1, String queue = 'q1', bool scheduled = false, DateTime? slot}) => Ticket(
      id: id, queueId: queue, ownerName: 'Notaría 12', userId: 'u1', slotStart: slot ?? DateTime.now().toUtc(), scheduled: scheduled,
      number: n, status: s, position: pos, createdAt: DateTime.now().toUtc());

class FakeQueues implements QueueRepository {
  final slotRequests = <String>[];
  @override
  Future<Result<List<Queue>>> list({bool? active}) async => const Result.ok([
        Queue(id: 'q1', ownerName: 'Notaría 12', name: 'Escrituras', active: true, description: 'Con cita'),
        Queue(id: 'q2', ownerName: 'Notaría 12', name: 'Archivo', active: false),
      ]);
  @override
  Future<Result<Queue>> get(String id) async => const Result.ok(Queue(id: 'q1', ownerName: 'Notaría 12', name: 'Escrituras', active: true));
  @override
  Future<Result<Queue>> create(CreateQueueInput input) => throw UnimplementedError();
  @override
  Future<Result<Queue>> update(String id, {String? name, String? description, bool? active}) => throw UnimplementedError();
  @override
  Future<Result<void>> delete(String id) => throw UnimplementedError();
  @override
  Future<Result<QueueLimit>> limit() => throw UnimplementedError();
  @override
  Future<Result<Schedule>> schedule(String id) async => const Result.ok(Schedule(
      queueId: 'q1', timeZone: 'America/Bogota', opens: '08:00:00', closes: '17:00:00', slotMinutes: 30,
      days: [1, 2, 3, 4, 5, 6, 7], turnMinutes: 10, stations: 2, dailyCapacity: 0, maxDaysAhead: 7));
  @override
  Future<Result<Schedule>> replaceSchedule(String id, ScheduleInput input) => throw UnimplementedError();
  @override
  Future<Result<List<Slot>>> slots(String id, {DateTime? date}) async {
    slotRequests.add('${date?.day}');
    final d = date ?? DateTime.now();
    return Result.ok([
      Slot(start: DateTime.utc(d.year, d.month, d.day, 13), end: DateTime.utc(d.year, d.month, d.day, 13, 30), capacity: 6, taken: 6, available: 0),
      Slot(start: DateTime.utc(d.year, d.month, d.day, 13, 30), end: DateTime.utc(d.year, d.month, d.day, 14), capacity: 6, taken: 4, available: 2),
    ]);
  }

  @override
  Future<Result<QueueState>> state(String id) async => Result.ok(QueueState(queueId: id, waiting: 5, serving: 1));
}

class FakeTickets implements TicketRepository {
  final created = <({String queue, DateTime? slot})>[];
  Failure? createFailure;
  final calls = <String>[];
  final stored = <String, Ticket>{};
  Failure? getFailure;

  @override
  Future<Result<Ticket>> create(String queueId, {DateTime? slotStart}) async {
    created.add((queue: queueId, slot: slotStart));
    if (createFailure != null) return Result.err(createFailure!);
    return Result.ok(ticket('t-new', 23, TicketStatus.enEspera, scheduled: slotStart != null));
  }

  @override
  Future<Result<List<Ticket>>> mine({int limit = 500, int offset = 0}) async => Result.ok(stored.values.toList());
  @override
  Future<Result<List<Ticket>>> list(TicketFilter filter) => throw UnimplementedError();
  @override
  Future<Result<Ticket>> get(String id) async {
    if (getFailure != null) return Result.err(getFailure!);
    final t = stored[id];
    return t == null ? const Result.err(NotFoundFailure()) : Result.ok(t);
  }

  Future<Result<Ticket>> _do(String name, String id, TicketStatus s) async {
    calls.add('$name:$id');
    final old = stored[id]!;
    final next = Ticket(
      id: old.id, queueId: old.queueId, ownerName: old.ownerName, userId: old.userId, slotStart: old.slotStart, scheduled: old.scheduled,
      number: old.number, status: s, position: old.position, createdAt: old.createdAt);
    stored[id] = next;
    return Result.ok(next);
  }

  @override
  Future<Result<Ticket>> postpone(String id) => _do('postpone', id, TicketStatus.enEspera);
  @override
  Future<Result<Ticket>> cancel(String id) => _do('cancel', id, TicketStatus.cancelado);
  @override
  Future<Result<Ticket>> call(String id) => throw UnimplementedError();
  @override
  Future<Result<Ticket>> finish(String id) => throw UnimplementedError();
  @override
  Future<Result<Ticket>> noShow(String id) => throw UnimplementedError();
}

class FakeNotifications implements NotificationRepository {
  FakeNotifications(this.items);
  List<AppNotification> items;
  final read = <String>[];
  @override
  Future<Result<List<AppNotification>>> list({int limit = 100, int offset = 0}) async => Result.ok([...items]);
  @override
  Future<Result<AppNotification>> markRead(String id) async {
    read.add(id);
    return Result.ok(items.firstWhere((n) => n.id == id).copyWith(read: true));
  }

  @override
  Future<Result<void>> delete(String id) async => const Result.ok(null);
}

class FakeGateway implements QhubGateway {
  FakeGateway({FakeQueues? queues, FakeTickets? tickets, FakeNotifications? notifications})
      : queueRepo = queues ?? FakeQueues(),
        ticketRepo = tickets ?? FakeTickets(),
        notificationRepo = notifications ?? FakeNotifications(const []);
  final FakeQueues queueRepo;
  final FakeTickets ticketRepo;
  final FakeNotifications notificationRepo;
  @override
  QueueRepository queues(String organizationId) => queueRepo;
  @override
  TicketRepository tickets(String organizationId) => ticketRepo;
  @override
  NotificationRepository notifications(String organizationId) => notificationRepo;
}

class Env {
  Env({FakeUserRepository? user, FakeOrganizationRepository? orgs, FakeHistoryRepository? history, FakeGateway? gateway})
      : user = user ?? FakeUserRepository(),
        orgs = orgs ?? FakeOrganizationRepository(),
        history = history ?? FakeHistoryRepository(),
        gateway = gateway ?? FakeGateway();
  final FakeUserRepository user;
  final FakeOrganizationRepository orgs;
  final FakeHistoryRepository history;
  final FakeGateway gateway;

  List<Override> get overrides => [
        envProvider.overrideWithValue(testEnv),
        userRepositoryProvider.overrideWithValue(user),
        organizationRepositoryProvider.overrideWithValue(orgs),
        historyRepositoryProvider.overrideWithValue(history),
        gatewayProvider.overrideWithValue(gateway),
      ];
}
