import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../gateway/domain/gateway.dart';
import '../../history/domain/history.dart';
import '../../organizations/domain/organizations.dart';

/// Un turno vigente del usuario con todo lo que necesita la tarjeta "Mi turno".
class ActiveTicket {
  const ActiveTicket({
    required this.entry,
    required this.ticket,
    required this.prefix,
    this.schedule,
    this.peopleAhead = 0,
    this.estimateMinutes,
  });
  final HistoryEntry entry;
  final Ticket ticket;
  final String prefix;
  final Schedule? schedule;
  final int peopleAhead;
  final int? estimateMinutes;

  String get organizationId => entry.organizationId;
  String get label => formatTurnNumber(ticket.number, prefix: prefix);
  bool get isMyTurn => ticket.status == TicketStatus.atendiendo;
}

/// Personas delante en la misma franja: `posición - 1` (0 cuando ya lo están atendiendo).
int aheadOf(Ticket t) => t.status == TicketStatus.enEspera ? (t.position - 1).clamp(0, 1 << 30) : 0;

/// Carga los turnos vigentes: los activos del historial, refrescados contra la API de su organización.
class LoadActiveTickets {
  LoadActiveTickets({required this.history, required this.gateway, required this.organizations});
  final HistoryRepository history;
  final QhubGateway gateway;
  final OrganizationRepository organizations;

  Future<Result<List<ActiveTicket>>> call() async {
    final hist = await history.list();
    if (hist.isErr) return Result.err(hist.failureOrNull!);
    final active = hist.valueOrNull!.where((e) => e.isActive).toList();
    if (active.isEmpty) return const Result.ok([]);

    final prefixCache = <String, Future<Map<String, String>>>{};
    Future<Map<String, String>> prefixesOf(String org) =>
        prefixCache.putIfAbsent(org, () async => (await organizations.queuePrefixes(org)).valueOrNull ?? const {});

    Failure? firstFailure;
    final results = await Future.wait(active.map((e) async {
      final fresh = await gateway.tickets(e.organizationId).get(e.ticketId);
      if (fresh.isErr) {
        final f = fresh.failureOrNull!;
        if (f is! NotFoundFailure) firstFailure ??= f;
        return null;
      }
      final ticket = fresh.valueOrNull!;
      if (!ticket.status.isActive) return null; // ya se resolvió: sale de "Mi turno"
      final schedule = (await gateway.queues(e.organizationId).schedule(e.queueId)).valueOrNull;
      final prefixes = await prefixesOf(e.organizationId);
      final ahead = aheadOf(ticket);
      return ActiveTicket(
        entry: e,
        ticket: ticket,
        prefix: prefixes[e.queueId] ?? defaultQueuePrefix(e.queueName ?? ''),
        schedule: schedule,
        peopleAhead: ahead,
        estimateMinutes: schedule == null ? null : estimateWaitMinutes(peopleAhead: ahead, turnMinutes: schedule.turnMinutes, slots: schedule.stations),
      );
    }));

    final list = results.whereType<ActiveTicket>().toList()
      ..sort((a, b) => a.ticket.slotStart.compareTo(b.ticket.slotStart));
    if (list.isEmpty && firstFailure != null) return Result.err(firstFailure!);
    return Result.ok(list);
  }
}
