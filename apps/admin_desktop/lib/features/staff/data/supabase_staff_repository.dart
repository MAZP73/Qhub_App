import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/staff.dart';

/// Adaptador Supabase. Traduce errores a [Failure]; la UI no ve excepciones de Supabase.
class SupabaseStaffRepository implements StaffRepository {
  SupabaseStaffRepository(this._client);
  final sb.SupabaseClient _client;

  StaffUser? _user(sb.User? u) => u == null
      ? null
      : StaffUser(
          id: u.id,
          email: u.email ?? '',
          displayName: [u.userMetadata?['nombre'], u.userMetadata?['apellido']]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim()
              .nullIfEmpty,
        );

  @override
  StaffUser? get currentUser => _user(_client.auth.currentUser);

  @override
  Stream<StaffUser?> authChanges() async* {
    yield currentUser;
    yield* _client.auth.onAuthStateChange.map((e) => _user(e.session?.user));
  }

  Failure _map(Object e) {
    if (e is Failure) return e;
    if (e is sb.AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login') || m.contains('invalid credentials')) {
        return const UnauthorizedFailure('Correo o contraseña incorrectos.');
      }
      if (m.contains('already registered') || m.contains('already been registered')) {
        return const ConflictFailure('Ese correo ya está registrado.');
      }
      if (m.contains('email not confirmed')) {
        return const BadRequestFailure('Confirma tu correo antes de entrar. Revisa tu bandeja.');
      }
      if (m.contains('password')) return ValidationFailure(e.message);
      if (m.contains('rate') || e.statusCode == '429') return const RateLimitedFailure();
      return UnauthorizedFailure(e.message);
    }
    if (e is sb.PostgrestException) {
      final code = e.code ?? '';
      if (code == '42501') return const ForbiddenFailure();
      if (code == '23505') return const ConflictFailure('Ya existe un registro con esos datos.');
      if (code == 'P0002') return NotFoundFailure(e.message);
      if (code == '28000') return const UnauthorizedFailure();
      if (code == '23514' || code == '22023') return ValidationFailure(e.message);
      return const ServerFailure();
    }
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
      return const NetworkFailure();
    }
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
  Future<Result<StaffUser>> signIn({required String email, required String password}) => _guard(() async {
        final r = await _client.auth.signInWithPassword(email: email.trim(), password: password);
        return _user(r.user)!;
      });

  @override
  Future<Result<StaffUser?>> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) =>
      _guard(() async {
        final r = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'nombre': firstName.trim(), 'apellido': lastName.trim()},
        );
        // Sin sesión = el proyecto exige confirmar el correo.
        return r.session == null ? null : _user(r.user);
      });

  @override
  Future<Result<void>> signOut() => _guard(() => _client.auth.signOut());

  Organization _org(Map<String, dynamic> j) => Organization(
        id: j['id'] as String,
        name: j['nombre'] as String,
        slug: j['slug'] as String,
        timeZone: (j['zona_horaria'] ?? 'America/Guayaquil') as String,
        city: j['ciudad'] as String?,
        country: j['pais'] as String?,
        published: (j['publica'] ?? false) as bool,
      );

  @override
  Future<Result<List<Membership>>> memberships() => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) throw const UnauthorizedFailure();
        final rows = await _client
            .from('miembros')
            .select('rol, activo, organizaciones(*)')
            .eq('usuario_id', uid)
            .eq('activo', true);
        return [
          for (final r in rows)
            if (r['organizaciones'] is Map<String, dynamic>)
              Membership(
                organization: _org(r['organizaciones'] as Map<String, dynamic>),
                role: OrgRole.parse(r['rol'] as String),
              ),
        ];
      });

  @override
  Future<Result<String>> createOrganization({
    required String name,
    required String slug,
    String? city,
    String? country,
    String timeZone = 'America/Guayaquil',
  }) =>
      _guard(() async {
        final id = await _client.rpc('crear_organizacion', params: {
          'p_nombre': name.trim(),
          'p_slug': slug,
          'p_ciudad': city,
          'p_pais': country,
          'p_zona_horaria': timeZone,
        });
        return id as String;
      });

  @override
  Future<Result<String>> acceptInvitation(String token) => _guard(() async {
        final id = await _client.rpc('aceptar_invitacion', params: {'p_token': token.trim()});
        return id as String;
      });

  @override
  Future<Result<Organization>> updateOrganization(String id, {String? name, bool? published, String? city, String? country}) =>
      _guard(() async {
        final row = await _client
            .from('organizaciones')
            .update({
              'nombre': ?name,
              'publica': ?published,
              'ciudad': ?city,
              'pais': ?country,
            })
            .eq('id', id)
            .select()
            .single();
        return _org(row);
      });

  @override
  Future<Result<List<Member>>> members(String orgId) => _guard(() async {
        final rows = await _client
            .from('miembros')
            .select('usuario_id, rol, activo, perfiles(nombre, apellido)')
            .eq('organizacion_id', orgId)
            .order('creado_en');
        return [
          for (final r in rows)
            Member(
              userId: r['usuario_id'] as String,
              name: _fullName(r['perfiles']),
              role: OrgRole.parse(r['rol'] as String),
              active: r['activo'] as bool,
            ),
        ];
      });

  String _fullName(Object? p) {
    if (p is! Map) return 'Sin nombre';
    final s = '${p['nombre'] ?? ''} ${p['apellido'] ?? ''}'.trim();
    return s.isEmpty ? 'Sin nombre' : s;
  }

  @override
  Future<Result<void>> updateMember(String orgId, String userId, {OrgRole? role, bool? active}) => _guard(() async {
        await _client
            .from('miembros')
            .update({'rol': ?role?.wire, 'activo': ?active})
            .eq('organizacion_id', orgId)
            .eq('usuario_id', userId);
      });

  @override
  Future<Result<void>> removeMember(String orgId, String userId) => _guard(() async {
        await _client.from('miembros').delete().eq('organizacion_id', orgId).eq('usuario_id', userId);
      });

  Invitation _inv(Map<String, dynamic> j) => Invitation(
        id: j['id'] as String,
        email: j['email'] as String,
        role: OrgRole.parse(j['rol'] as String),
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expira_en'] as String),
        acceptedAt: j['aceptada_en'] == null ? null : DateTime.parse(j['aceptada_en'] as String),
      );

  @override
  Future<Result<Invitation>> invite(String orgId, {required String email, required OrgRole role}) => _guard(() async {
        final row = await _client
            .from('invitaciones')
            .insert({
              'organizacion_id': orgId,
              'email': email.trim().toLowerCase(),
              'rol': role.wire,
              'invitada_por': _client.auth.currentUser?.id,
            })
            .select()
            .single();
        return _inv(row);
      });

  @override
  Future<Result<List<Invitation>>> invitations(String orgId) => _guard(() async {
        final rows = await _client
            .from('invitaciones')
            .select()
            .eq('organizacion_id', orgId)
            .isFilter('aceptada_en', null)
            .order('creada_en', ascending: false);
        return rows.map(_inv).toList();
      });

  @override
  Future<Result<Map<String, String>>> queuePrefixes(String orgId) => _guard(() async {
        final rows = await _client.from('cola_prefijos').select('qhub_cola_id, prefijo').eq('organizacion_id', orgId);
        return {for (final r in rows) r['qhub_cola_id'] as String: r['prefijo'] as String};
      });

  @override
  Future<Result<void>> setQueuePrefix(String orgId, String queueId, String prefix) => _guard(() async {
        await _client.from('cola_prefijos').upsert({
          'organizacion_id': orgId,
          'qhub_cola_id': queueId,
          'prefijo': prefix.toUpperCase(),
        });
      });

  @override
  Future<Result<void>> audit(String orgId, String action,
          {String? entity, String? entityId, Map<String, Object?> detail = const {}}) =>
      _guard(() async {
        await _client.from('auditoria').insert({
          'organizacion_id': orgId,
          'usuario_id': _client.auth.currentUser?.id,
          'accion': action,
          'entidad': entity,
          'entidad_id': entityId,
          'detalle': detail,
        });
      });
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
