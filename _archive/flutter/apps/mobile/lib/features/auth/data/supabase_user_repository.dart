import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/user.dart';

class SupabaseUserRepository implements UserRepository {
  SupabaseUserRepository(this._client);
  final sb.SupabaseClient _client;

  AppUser? _user(sb.User? u) {
    if (u == null) return null;
    final name = [u.userMetadata?['nombre'], u.userMetadata?['apellido']].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim();
    return AppUser(id: u.id, email: u.email ?? '', displayName: name.isEmpty ? null : name);
  }

  @override
  AppUser? get currentUser => _user(_client.auth.currentUser);

  @override
  Stream<AppUser?> authChanges() async* {
    yield currentUser;
    yield* _client.auth.onAuthStateChange.map((e) => _user(e.session?.user));
  }

  Failure _map(Object e) {
    if (e is Failure) return e;
    if (e is sb.AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login') || m.contains('invalid credentials')) return const UnauthorizedFailure('Correo o contraseña incorrectos.');
      if (m.contains('already registered') || m.contains('already been registered')) return const ConflictFailure('Ese correo ya está registrado.');
      if (m.contains('email not confirmed')) return const BadRequestFailure('Confirma tu correo antes de entrar. Revisa tu bandeja.');
      if (m.contains('password')) return ValidationFailure(e.message);
      if (e.statusCode == '429' || m.contains('rate')) return const RateLimitedFailure();
      return UnauthorizedFailure(e.message);
    }
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) return const NetworkFailure();
    return const UnknownFailure();
  }

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Result.ok(await body());
    } catch (e) {
      return Result.err(_map(e));
    }
  }

  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) => _guard(() async {
        final r = await _client.auth.signInWithPassword(email: email.trim(), password: password);
        return _user(r.user)!;
      });

  @override
  Future<Result<AppUser?>> signUp({required String email, required String password, required String firstName, required String lastName}) =>
      _guard(() async {
        final r = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'nombre': firstName.trim(), 'apellido': lastName.trim()},
        );
        return r.session == null ? null : _user(r.user);
      });

  @override
  Future<Result<void>> signOut() => _guard(() => _client.auth.signOut());
}
