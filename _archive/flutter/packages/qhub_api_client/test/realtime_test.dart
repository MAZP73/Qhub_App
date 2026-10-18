import 'dart:async';
import 'dart:convert';

import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in = StreamController<dynamic>();
  int? _closeCode;
  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  late final WebSocketSink sink = _Sink(this);
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => _closeCode;
  @override
  String? get closeReason => null;

  void serverSend(Map<String, dynamic> m) => _in.add(jsonEncode(m));
  Future<void> serverClose(int code) async {
    _closeCode = code;
    await _in.close();
  }
}

class _Sink implements WebSocketSink {
  _Sink(this.c);
  final FakeChannel c;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? st]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {
    c._closeCode ??= closeCode;
  }
  @override
  Future get done => Future.value();
}

void main() {
  late ApiContext ctx;
  late List<Uri> uris;
  late List<FakeChannel> channels;

  RealtimeRepositoryImpl build() => RealtimeRepositoryImpl(
        wsBaseUrl: 'ws://api.test/',
        context: ctx,
        backoff: (_) => const Duration(milliseconds: 5),
        connector: (uri) {
          uris.add(uri);
          final ch = FakeChannel();
          channels.add(ch);
          return ch;
        },
      );

  setUp(() {
    ctx = ApiContext(token: 'tok', actor: const Actor(userId: 'u1', role: ActorRole.agente));
    uris = [];
    channels = [];
  });

  test('arma la URL con token:usuario:rol y entrega eventos tipados', () async {
    final events = <QueueEvent>[];
    final sub = build().queueEvents('q1').listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(uris.single.toString(), 'ws://api.test/ws/turnos/q1?token=tok%3Au1%3Aagente');

    channels.single.serverSend({'tipo': 'ping'});
    channels.single.serverSend({
      'tipo': 'turno_llamado',
      'cola_id': 'q1',
      'payload': {'id': 't1', 'numero': 4, 'estado': 'atendiendo', 'posicion': 0, 'usuario_id': 'cli-1'}
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.single.type, QueueEventType.ticketCalled);
    expect(events.single.ticket?.number, 4);
    expect(events.single.ticket?.status, TicketStatus.atendiendo);
    await sub.cancel();
  });

  test('reconecta si el servidor cierra', () async {
    final sub = build().queueEvents('q1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await channels.first.serverClose(1006);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(channels.length, greaterThanOrEqualTo(2));
    await sub.cancel();
  });

  test('4401 → UnauthorizedFailure, avisa a la app y no reintenta', () async {
    var notified = 0;
    ctx.onUnauthorized = () => notified++;
    final errors = <Object>[];
    final done = Completer<void>();
    build().queueEvents('q1').listen((_) {}, onError: errors.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await channels.single.serverClose(4401);
    await done.future.timeout(const Duration(seconds: 1));
    expect(errors.single, isA<UnauthorizedFailure>());
    expect(notified, 1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(channels.length, 1);
  });

  test('avisos personales', () async {
    final got = <AppNotification>[];
    final sub = build().notifications().listen(got.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    channels.single.serverSend({'tipo': 'conectado', 'usuario_id': 'u1', 'no_leidas': 2});
    channels.single.serverSend({
      'tipo': 'notificacion',
      'notificacion': {
        'id': 'n1', 'mensaje': 'Tu turno #4 está siendo atendido', 'turno_id': 't1',
        'tipo_aviso': 'turno_llamado', 'leida': false, 'creada_en': '2026-10-20T15:01:00Z'
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(got.single.kind, 'turno_llamado');
    await sub.cancel();
  });

  test('sin sesión no abre el socket', () async {
    ctx.clear();
    final errors = <Object>[];
    final done = Completer<void>();
    build().notifications().listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 1));
    expect(errors.single, isA<UnauthorizedFailure>());
    expect(channels, isEmpty);
  });
}
