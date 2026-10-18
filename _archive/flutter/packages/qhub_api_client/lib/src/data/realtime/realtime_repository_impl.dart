import 'dart:async';
import 'dart:convert';

import 'package:qhub_core/qhub_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';
import '../mappers.dart';

typedef WsConnector = WebSocketChannel Function(Uri uri);

/// WebSocket con reconexión exponencial. Código 4401 = token inválido o cola ajena: no reintenta.
class RealtimeRepositoryImpl implements RealtimeRepository {
  RealtimeRepositoryImpl({
    required String wsBaseUrl,
    required ApiContext context,
    WsConnector? connector,
    Duration Function(int attempt)? backoff,
  })  : _base = wsBaseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _context = context,
        _connector = connector ?? WebSocketChannel.connect,
        _backoff = backoff ?? _defaultBackoff;

  final String _base;
  final ApiContext _context;
  final WsConnector _connector;
  final Duration Function(int) _backoff;
  final _status = StreamController<ConnectionStatus>.broadcast();

  static Duration _defaultBackoff(int attempt) {
    final secs = 1 << (attempt.clamp(0, 5));
    return Duration(seconds: secs > 30 ? 30 : secs);
  }

  @override
  Stream<ConnectionStatus> get status => _status.stream;

  @override
  Stream<QueueEvent> queueEvents(String queueId) =>
      _open<QueueEvent>('/ws/turnos/$queueId', queueEventFromJson);

  @override
  Stream<AppNotification> notifications() =>
      _open<AppNotification>('/ws/notificaciones', notificationEventFromJson);

  Uri _uri(String path) {
    final actor = _context.actor;
    final token = _context.token;
    if (token == null || actor == null) throw const UnauthorizedFailure();
    return Uri.parse('$_base$path').replace(queryParameters: {
      'token': '$token:${actor.userId}:${actor.role.wire}',
    });
  }

  Stream<T> _open<T>(String path, T? Function(Map<String, dynamic>) parse) {
    late StreamController<T> controller;
    var cancelled = false;
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    Timer? retry;
    var attempts = 0;

    late Future<void> Function() connect;

    void scheduleRetry() {
      if (cancelled) return;
      _status.add(ConnectionStatus.reconnecting);
      attempts++;
      retry = Timer(_backoff(attempts), () => connect());
    }

    connect = () async {
      if (cancelled) return;
      _status.add(attempts == 0 ? ConnectionStatus.connecting : ConnectionStatus.reconnecting);
      try {
        channel = _connector(_uri(path));
        await channel!.ready;
      } on Failure catch (f) {
        controller.addError(f);
        await controller.close();
        return;
      } catch (_) {
        scheduleRetry();
        return;
      }
      if (cancelled) {
        await channel!.sink.close();
        return;
      }
      attempts = 0;
      _status.add(ConnectionStatus.connected);
      sub = channel!.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String);
            if (decoded is Map<String, dynamic>) {
              final value = parse(decoded);
              if (value != null && !controller.isClosed) controller.add(value);
            }
          } catch (_) {/* mensaje ajeno al contrato: se ignora */}
        },
        onError: (_) {},
        onDone: () async {
          if (cancelled) return;
          if (channel?.closeCode == 4401) {
            controller.addError(const UnauthorizedFailure());
            _context.onUnauthorized?.call();
            await controller.close();
            return;
          }
          scheduleRetry();
        },
        cancelOnError: false,
      );
    };

    controller = StreamController<T>(
      onListen: () => connect(),
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        await sub?.cancel();
        await channel?.sink.close();
        _status.add(ConnectionStatus.closed);
      },
    );
    return controller.stream;
  }
}
