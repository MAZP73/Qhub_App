import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/app/providers.dart';
import 'package:qhub_admin/features/qhub/domain/qhub_connection.dart';
import 'package:qhub_admin/features/staff/domain/staff.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import 'support/fakes.dart';

void main() {
  late FakeStaffRepository staff;
  late FakeAuthRepository auth;
  late MemoryCredentialStore store;
  late ProviderContainer container;

  setUp(() async {
    staff = FakeStaffRepository(
      user: const StaffUser(id: 'u1', email: 'ana@x.co'),
      memberships: const [Membership(organization: org, role: OrgRole.agente)],
    );
    auth = FakeAuthRepository();
    store = MemoryCredentialStore();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        envProvider.overrideWithValue(testEnv),
        staffRepositoryProvider.overrideWithValue(staff),
        authRepositoryProvider.overrideWithValue(auth),
        credentialStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authUserProvider.future);
    await container.read(membershipsProvider.future);
  });

  test('connect deja el token y el actor con el rol del staff', () async {
    final res = await container.read(qhubConnectionProvider.notifier).connect(identifier: 'notaria12', password: 'pw', remember: false);
    expect(res.isOk, isTrue);
    expect(container.read(qhubConnectionProvider), isA<QhubConnected>());
    final ctx = container.read(apiContextProvider);
    expect(ctx.token, 'tok1');
    expect(ctx.actor, const Actor(userId: 'u1', role: ActorRole.agente));
    expect(store.data, isEmpty);
  });

  test('remember guarda la credencial por organización', () async {
    await container.read(qhubConnectionProvider.notifier).connect(identifier: 'notaria12', password: 'pw', remember: true);
    expect(store.data['org1']?.identifier, 'notaria12');
  });

  test('credenciales inválidas → Disconnected con el motivo', () async {
    auth.loginFailure = const UnauthorizedFailure('Credenciales inválidas');
    final res = await container.read(qhubConnectionProvider.notifier).connect(identifier: 'x', password: 'y');
    expect(res.failureOrNull, isA<UnauthorizedFailure>());
    final s = container.read(qhubConnectionProvider) as QhubDisconnected;
    expect(s.reason?.message, 'Credenciales inválidas');
    expect(container.read(apiContextProvider).isAuthenticated, isFalse);
  });

  test('restore reconecta con la credencial guardada', () async {
    store.data['org1'] = const QhubCredential('notaria12', 'pw');
    expect(await container.read(qhubConnectionProvider.notifier).restore(), isTrue);
    expect(container.read(qhubConnectionProvider), isA<QhubConnected>());
  });

  test('restore sin credencial guardada devuelve false', () async {
    expect(await container.read(qhubConnectionProvider.notifier).restore(), isFalse);
  });

  test('401 con credencial guardada reconecta en silencio (no hay refresh)', () async {
    store.data['org1'] = const QhubCredential('notaria12', 'pw');
    await container.read(qhubConnectionProvider.notifier).connect(identifier: 'notaria12', password: 'pw', remember: true);
    expect(auth.loginCount, 1);
    container.read(apiContextProvider).onUnauthorized!.call();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(auth.loginCount, 2);
    expect(container.read(qhubConnectionProvider), isA<QhubConnected>());
    expect(container.read(apiContextProvider).token, 'tok2');
  });

  test('401 sin credencial guardada desconecta y pide login', () async {
    await container.read(qhubConnectionProvider.notifier).connect(identifier: 'notaria12', password: 'pw');
    container.read(apiContextProvider).onUnauthorized!.call();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(qhubConnectionProvider), isA<QhubDisconnected>());
    expect(container.read(apiContextProvider).token, isNull);
  });

  test('cerrar sesión del staff desconecta la API', () async {
    await container.read(qhubConnectionProvider.notifier).connect(identifier: 'notaria12', password: 'pw');
    await staff.signOut();
    await container.read(authUserProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(qhubConnectionProvider), isA<QhubDisconnected>());
  });
}
