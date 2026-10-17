import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../features/qhub/data/secure_credential_store.dart';
import '../features/qhub/domain/qhub_connection.dart';
import '../features/staff/data/supabase_staff_repository.dart';
import '../features/staff/domain/staff.dart';
import 'env.dart';

// ───────── Infraestructura (overrides en main/tests) ─────────
final envProvider = Provider<AppEnv>((_) => throw UnimplementedError('envProvider sin override'));
final supabaseClientProvider = Provider<SupabaseClient>((_) => throw UnimplementedError('supabaseClientProvider sin override'));

final staffRepositoryProvider = Provider<StaffRepository>((ref) => SupabaseStaffRepository(ref.watch(supabaseClientProvider)));
final credentialStoreProvider = Provider<CredentialStore>((_) => SecureCredentialStore());

final apiContextProvider = Provider<ApiContext>((_) => ApiContext());
final dioProvider = Provider<Dio>((ref) => createQhubDio(baseUrl: ref.watch(envProvider).apiBaseUrl, context: ref.watch(apiContextProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepositoryImpl(ref.watch(dioProvider)));
final queueRepositoryProvider = Provider<QueueRepository>((ref) => QueueRepositoryImpl(ref.watch(dioProvider)));
final ticketRepositoryProvider = Provider<TicketRepository>((ref) => TicketRepositoryImpl(ref.watch(dioProvider)));
final healthRepositoryProvider = Provider<HealthRepository>((ref) => HealthRepositoryImpl(ref.watch(dioProvider)));
final realtimeRepositoryProvider = Provider<RealtimeRepository>(
  (ref) => RealtimeRepositoryImpl(wsBaseUrl: ref.watch(envProvider).wsBaseUrl, context: ref.watch(apiContextProvider)),
);

// ───────── Sesión del staff (Supabase) ─────────
final authUserProvider = StreamProvider<StaffUser?>((ref) => ref.watch(staffRepositoryProvider).authChanges());

final membershipsProvider = FutureProvider<List<Membership>>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return const [];
  final res = await ref.watch(staffRepositoryProvider).memberships();
  return res.getOrThrow();
});

/// Organización activa del staff (por ahora la primera; el selector multi-organización es futuro).
final activeMembershipProvider = Provider<Membership?>((ref) {
  final list = ref.watch(membershipsProvider).value;
  return (list == null || list.isEmpty) ? null : list.first;
});

// ───────── Conexión a la API Qhub ─────────
final connectToQhubProvider = Provider<ConnectToQhub>(
  (ref) => ConnectToQhub(
    auth: ref.watch(authRepositoryProvider),
    context: ref.watch(apiContextProvider),
    store: ref.watch(credentialStoreProvider),
  ),
);

class QhubConnectionController extends Notifier<QhubConnection> {
  var _recovering = false;

  @override
  QhubConnection build() {
    final ctx = ref.watch(apiContextProvider);
    ctx.onUnauthorized = _onUnauthorized;
    ref.listen(authUserProvider, (prev, next) {
      if (next.value == null && prev?.value != null) disconnect();
    });
    return const QhubDisconnected();
  }

  Future<Result<void>> connect({required String identifier, required String password, bool remember = false}) async {
    final membership = ref.read(activeMembershipProvider);
    final user = ref.read(authUserProvider).value;
    if (membership == null || user == null) return const Result.err(UnauthorizedFailure());
    state = const QhubConnecting();
    final res = await ref.read(connectToQhubProvider)(
      orgId: membership.organization.id,
      actor: Actor(userId: user.id, role: membership.role.actorRole),
      identifier: identifier,
      password: password,
      remember: remember,
    );
    return res.when(
      ok: (expires) {
        state = QhubConnected(expires);
        return const Result<void>.ok(null);
      },
      err: (f) {
        state = QhubDisconnected(reason: f);
        return Result<void>.err(f);
      },
    );
  }

  /// Reconecta en silencio con la credencial guardada ("Mantener sesión").
  Future<bool> restore() async {
    final membership = ref.read(activeMembershipProvider);
    if (membership == null) return false;
    final stored = await ref.read(credentialStoreProvider).read(membership.organization.id);
    if (stored == null) return false;
    final res = await connect(identifier: stored.identifier, password: stored.password, remember: true);
    return res.isOk;
  }

  void disconnect() {
    ref.read(apiContextProvider).clear();
    state = const QhubDisconnected();
  }

  Future<void> forgetStoredCredential() async {
    final membership = ref.read(activeMembershipProvider);
    if (membership != null) await ref.read(credentialStoreProvider).delete(membership.organization.id);
  }

  /// 401 en un endpoint de negocio: no hay refresh, así que se re-loguea o se pide login.
  Future<void> _onUnauthorized() async {
    if (_recovering || state is! QhubConnected) return;
    _recovering = true;
    try {
      final ok = await restore();
      if (!ok) {
        ref.read(apiContextProvider).clear();
        state = const QhubDisconnected(reason: UnauthorizedFailure());
      }
    } finally {
      _recovering = false;
    }
  }
}

final qhubConnectionProvider = NotifierProvider<QhubConnectionController, QhubConnection>(QhubConnectionController.new);

// ───────── Preferencias ─────────
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode m) => state = m;
}
