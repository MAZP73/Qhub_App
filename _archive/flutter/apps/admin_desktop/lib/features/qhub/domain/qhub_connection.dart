import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

/// Credencial de la cuenta Qhub de la organización (email/usuario + contraseña).
class QhubCredential {
  const QhubCredential(this.identifier, this.password);
  final String identifier;
  final String password;
}

/// Almacén seguro (por organización) para "Mantener sesión".
abstract interface class CredentialStore {
  Future<QhubCredential?> read(String orgId);
  Future<void> write(String orgId, QhubCredential credential);
  Future<void> delete(String orgId);
}

sealed class QhubConnection {
  const QhubConnection();
}

final class QhubDisconnected extends QhubConnection {
  const QhubDisconnected({this.reason});
  final Failure? reason;
}

final class QhubConnecting extends QhubConnection {
  const QhubConnecting();
}

final class QhubConnected extends QhubConnection {
  const QhubConnected(this.expiresAt);
  final DateTime expiresAt;
}

/// Caso de uso: iniciar sesión en la API Qhub y dejar el contexto listo para los repositorios.
class ConnectToQhub {
  ConnectToQhub({
    required this.auth,
    required this.context,
    required this.store,
  });

  final AuthRepository auth;
  final ApiContext context;
  final CredentialStore store;

  Future<Result<DateTime>> call({
    required String orgId,
    required Actor actor,
    required String identifier,
    required String password,
    bool remember = false,
  }) async {
    final res = await auth.login(identifier: identifier.trim(), password: password);
    return res.when(
      ok: (token) async {
        context
          ..token = token.accessToken
          ..actor = actor;
        if (remember) {
          await store.write(orgId, QhubCredential(identifier.trim(), password));
        } else {
          await store.delete(orgId);
        }
        return Result.ok(token.expiresAt);
      },
      err: (f) async => Result.err(f),
    );
  }
}
