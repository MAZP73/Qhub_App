import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../../app/providers.dart';

class LiveBoardState {
  const LiveBoardState({
    this.tickets = const [],
    this.loading = true,
    this.error,
    this.connection = ConnectionStatus.connecting,
    this.busyTicketId,
  });
  final List<Ticket> tickets;
  final bool loading;
  final Failure? error;
  final ConnectionStatus connection;
  final String? busyTicketId;

  List<Ticket> get queue => sortWaitingRoom(tickets);
  List<Ticket> get serving => queue.where((t) => t.status == TicketStatus.atendiendo).toList();
  List<Ticket> get waiting => queue.where((t) => t.status == TicketStatus.enEspera).toList();
  Ticket? get next => nextToCall(tickets);
  bool get isLive => connection == ConnectionStatus.connected;

  LiveBoardState copyWith({
    List<Ticket>? tickets,
    bool? loading,
    Object? error = _keep,
    ConnectionStatus? connection,
    Object? busyTicketId = _keep,
  }) =>
      LiveBoardState(
        tickets: tickets ?? this.tickets,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as Failure?,
        connection: connection ?? this.connection,
        busyTicketId: identical(busyTicketId, _keep) ? this.busyTicketId : busyTicketId as String?,
      );
}

const _keep = Object();

/// Fila de una cola en vivo: carga el día, escucha el WebSocket y ejecuta las acciones del operador.
class LiveBoardController extends Notifier<LiveBoardState> {
  LiveBoardController(this.queueId);
  final String queueId;

  @override
  LiveBoardState build() {
    final realtime = ref.watch(realtimeRepositoryProvider);
    final events = realtime.queueEvents(queueId).listen(_onEvent, onError: _onError);
    final status = realtime.status.listen((s) => state = state.copyWith(connection: s));
    final refresh = Timer.periodic(const Duration(seconds: 60), (_) => load(silent: true));
    ref.onDispose(() {
      events.cancel();
      status.cancel();
      refresh.cancel();
    });
    Future.microtask(load);
    return const LiveBoardState();
  }

  void _onEvent(QueueEvent e) {
    if (e.queueId.isNotEmpty && e.queueId != queueId) return;
    if (e.ticket == null) {
      // cola_actualizada (finalizar / no-show manual): la fila cambió, se recarga.
      load(silent: true);
      return;
    }
    state = state.copyWith(tickets: applyQueueEvent(state.tickets, e));
  }

  void _onError(Object e) {
    if (e is Failure) state = state.copyWith(error: e, connection: ConnectionStatus.closed);
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true, error: null);
    final today = DateTime.now();
    final all = <Ticket>[];
    var offset = 0;
    while (true) {
      final res = await ref.read(ticketRepositoryProvider).list(TicketFilter(queueId: queueId, date: today, limit: 500, offset: offset));
      if (res.isErr) {
        state = state.copyWith(loading: false, error: res.failureOrNull);
        return;
      }
      final page = res.valueOrNull!;
      all.addAll(page);
      if (page.length < 500) break;
      offset += page.length;
    }
    state = state.copyWith(tickets: all, loading: false, error: null);
  }

  Future<Result<Ticket>> _act(Ticket t, Future<Result<Ticket>> Function(TicketRepository r) fn) async {
    state = state.copyWith(busyTicketId: t.id);
    final res = await fn(ref.read(ticketRepositoryProvider));
    res.when(
      ok: (updated) => state = state.copyWith(
        tickets: applyQueueEvent(state.tickets, QueueEvent(type: QueueEventType.queueUpdated, queueId: queueId, ticket: updated)),
        busyTicketId: null,
      ),
      err: (_) => state = state.copyWith(busyTicketId: null),
    );
    return res;
  }

  Future<Result<Ticket>> call(Ticket t) => _act(t, (r) => r.call(t.id));
  Future<Result<Ticket>> finish(Ticket t) => _act(t, (r) => r.finish(t.id));
  Future<Result<Ticket>> noShow(Ticket t) => _act(t, (r) => r.noShow(t.id));

  /// "Llamar siguiente": el primero en espera de la franja más próxima.
  Future<Result<Ticket>?> callNext() async {
    final next = state.next;
    if (next == null) return null;
    return call(next);
  }
}

final liveBoardProvider = NotifierProvider.autoDispose.family<LiveBoardController, LiveBoardState, String>(
  LiveBoardController.new,
);
