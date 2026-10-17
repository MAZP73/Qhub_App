import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

class HistoryStats {
  const HistoryStats({
    required this.total,
    required this.attended,
    required this.noShow,
    required this.cancelled,
    required this.waiting,
    this.avgWait,
    this.avgService,
  });
  final int total;
  final int attended;
  final int noShow;
  final int cancelled;
  final int waiting;
  final Duration? avgWait;
  final Duration? avgService;

  /// No-show sobre los turnos que ya se resolvieron (atendidos + no-show).
  double get noShowRate {
    final resolved = attended + noShow;
    return resolved == 0 ? 0 : noShow / resolved;
  }
}

HistoryStats computeStats(Iterable<Ticket> tickets) {
  var attended = 0, noShow = 0, cancelled = 0, waiting = 0, total = 0;
  final waits = <Duration>[];
  final services = <Duration>[];
  for (final t in tickets) {
    total++;
    switch (t.status) {
      case TicketStatus.finalizado:
        attended++;
      case TicketStatus.noShow:
        noShow++;
      case TicketStatus.cancelado:
        cancelled++;
      case TicketStatus.enEspera:
      case TicketStatus.atendiendo:
        waiting++;
    }
    final called = t.calledAt;
    if (called != null) {
      final since = t.scheduled ? t.slotStart : t.createdAt;
      final w = called.difference(since);
      waits.add(w.isNegative ? Duration.zero : w);
      final done = t.finishedAt;
      if (done != null) services.add(done.difference(called));
    }
  }
  Duration? avg(List<Duration> l) => l.isEmpty ? null : Duration(microseconds: l.fold<int>(0, (a, d) => a + d.inMicroseconds) ~/ l.length);
  return HistoryStats(
    total: total, attended: attended, noShow: noShow, cancelled: cancelled, waiting: waiting,
    avgWait: avg(waits), avgService: avg(services),
  );
}

/// `m:ss` (`7:12`) o `—`.
String formatDuration(Duration? d) {
  if (d == null) return '—';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatPercent(double v) => '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

String _csv(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String ticketsToCsv(Iterable<Ticket> tickets, {Map<String, String> queueNames = const {}, Map<String, String> prefixes = const {}}) {
  final b = StringBuffer('turno,cola,cliente,franja,estado,llegada,atencion,finalizacion,agente\n');
  for (final t in tickets) {
    b.writeln([
      formatTurnNumber(t.number, prefix: prefixes[t.queueId] ?? 'A'),
      queueNames[t.queueId] ?? t.queueId,
      t.userId,
      t.slotStart.toUtc().toIso8601String(),
      t.status.wire,
      t.createdAt.toUtc().toIso8601String(),
      t.calledAt?.toUtc().toIso8601String(),
      t.finishedAt?.toUtc().toIso8601String(),
      t.agentId,
    ].map(_csv).join(','));
  }
  return b.toString();
}

/// Carga todos los turnos de [days] días (hoy incluido) paginando de a 1000.
Future<Result<List<Ticket>>> loadHistory(TicketRepository repo, {required int days, required DateTime today}) async {
  final out = <Ticket>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
    var offset = 0;
    while (true) {
      final res = await repo.list(TicketFilter(date: day, limit: 1000, offset: offset));
      if (res.isErr) return Result.err(res.failureOrNull!);
      final page = res.valueOrNull!;
      out.addAll(page);
      if (page.length < 1000) break;
      offset += page.length;
    }
  }
  return Result.ok(out);
}
