import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:qhub_core/qhub_core.dart';

import '../../../app/providers.dart';
import '../../organizations/domain/organizations.dart';
import '../domain/active_tickets.dart';

final loadActiveTicketsProvider = Provider<LoadActiveTickets>((ref) => LoadActiveTickets(
      history: ref.watch(historyRepositoryProvider),
      gateway: ref.watch(gatewayProvider),
      organizations: ref.watch(organizationRepositoryProvider),
    ));

/// Mis turnos vigentes. Se refresca cada 15 s (el proxy no expone WebSocket).
class ActiveTicketsController extends AsyncNotifier<List<ActiveTicket>> {
  @override
  Future<List<ActiveTicket>> build() async {
    final timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    ref.onDispose(timer.cancel);
    return (await ref.read(loadActiveTicketsProvider)()).getOrThrow();
  }

  Future<void> refresh() async {
    final res = await ref.read(loadActiveTicketsProvider)();
    // Si el refresco falla se conserva lo que ya se mostraba.
    res.when(ok: (v) => state = AsyncData(v), err: (f) {
      if (!state.hasValue) state = AsyncError(f, StackTrace.empty);
    });
  }

  Future<Result<Ticket>> cancel(ActiveTicket t) async {
    final res = await ref.read(gatewayProvider).tickets(t.organizationId).cancel(t.ticket.id);
    if (res.isOk) await refresh();
    return res;
  }

  Future<Result<Ticket>> postpone(ActiveTicket t) async {
    final res = await ref.read(gatewayProvider).tickets(t.organizationId).postpone(t.ticket.id);
    if (res.isOk) await refresh();
    return res;
  }
}

final activeTicketsProvider = AsyncNotifierProvider.autoDispose<ActiveTicketsController, List<ActiveTicket>>(ActiveTicketsController.new);

// ───────── Explorar ─────────
final orgSearchProvider = FutureProvider.autoDispose.family<List<OrganizationSummary>, String>((ref, query) async {
  return (await ref.watch(organizationRepositoryProvider).search(query)).getOrThrow();
});

final favoritesProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  return (await ref.watch(organizationRepositoryProvider).favoriteIds()).valueOrNull ?? const {};
});

final orgProvider = FutureProvider.autoDispose.family<OrganizationSummary, String>((ref, id) async {
  return (await ref.watch(organizationRepositoryProvider).get(id)).getOrThrow();
});

final orgPrefixesProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, id) async {
  return (await ref.watch(organizationRepositoryProvider).queuePrefixes(id)).valueOrNull ?? const {};
});

final orgQueuesProvider = FutureProvider.autoDispose.family<List<Queue>, String>((ref, orgId) async {
  final all = (await ref.watch(gatewayProvider).queues(orgId).list(active: true)).getOrThrow();
  return all.where((q) => q.active).toList();
});

final queueStateProvider = FutureProvider.autoDispose.family<QueueState, ({String org, String queue})>((ref, k) async {
  return (await ref.watch(gatewayProvider).queues(k.org).state(k.queue)).getOrThrow();
});

final scheduleProvider = FutureProvider.autoDispose.family<Schedule, ({String org, String queue})>((ref, k) async {
  return (await ref.watch(gatewayProvider).queues(k.org).schedule(k.queue)).getOrThrow();
});

typedef SlotKey = ({String org, String queue, String date});

final slotsProvider = FutureProvider.autoDispose.family<List<Slot>, SlotKey>((ref, k) async {
  final d = DateTime.parse(k.date);
  return (await ref.watch(gatewayProvider).queues(k.org).slots(k.queue, date: d)).getOrThrow();
});

// ───────── Avisos ─────────
class OrgNotification {
  const OrgNotification({required this.organizationId, required this.organizationName, required this.notification});
  final String organizationId;
  final String organizationName;
  final AppNotification notification;
}

class NotificationsController extends AsyncNotifier<List<OrgNotification>> {
  @override
  Future<List<OrgNotification>> build() => _load();

  Future<List<OrgNotification>> _load() async {
    final hist = (await ref.read(historyRepositoryProvider).list()).getOrThrow();
    final orgs = <String, String>{for (final e in hist) e.organizationId: e.organizationName ?? 'Organización'};
    final out = <OrgNotification>[];
    Failure? failure;
    await Future.wait(orgs.entries.map((o) async {
      final res = await ref.read(gatewayProvider).notifications(o.key).list(limit: 50);
      res.when(
        ok: (list) => out.addAll(list.map((n) => OrgNotification(organizationId: o.key, organizationName: o.value, notification: n))),
        err: (f) => failure ??= f,
      );
    }));
    if (out.isEmpty && failure != null) throw failure!;
    out.sort((a, b) => b.notification.createdAt.compareTo(a.notification.createdAt));
    return out;
  }

  Future<void> refresh() async => state = AsyncData(await _load());

  Future<void> markRead(OrgNotification n) async {
    final res = await ref.read(gatewayProvider).notifications(n.organizationId).markRead(n.notification.id);
    if (res.isOk) {
      state = AsyncData([
        for (final x in state.value ?? const <OrgNotification>[])
          x.notification.id == n.notification.id
              ? OrgNotification(organizationId: x.organizationId, organizationName: x.organizationName, notification: x.notification.copyWith(read: true))
              : x,
      ]);
    }
  }

  Future<void> markAllRead() async {
    for (final n in (state.value ?? const <OrgNotification>[]).where((n) => !n.notification.read)) {
      await markRead(n);
    }
  }
}

final notificationsProvider = AsyncNotifierProvider.autoDispose<NotificationsController, List<OrgNotification>>(NotificationsController.new);

final historyEntriesProvider = FutureProvider.autoDispose((ref) async => (await ref.watch(historyRepositoryProvider).list()).getOrThrow());
