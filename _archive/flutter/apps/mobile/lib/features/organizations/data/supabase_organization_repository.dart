import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/organizations.dart';

class SupabaseOrganizationRepository implements OrganizationRepository {
  SupabaseOrganizationRepository(this._client);
  final sb.SupabaseClient _client;

  Failure _map(Object e) {
    if (e is Failure) return e;
    if (e is sb.PostgrestException) return e.code == '42501' ? const ForbiddenFailure() : const ServerFailure();
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

  OrganizationSummary _row(Map<String, dynamic> j) => OrganizationSummary(
        id: j['id'] as String,
        name: j['nombre'] as String,
        slug: j['slug'] as String,
        description: j['descripcion'] as String?,
        address: j['direccion'] as String?,
        city: j['ciudad'] as String?,
        country: j['pais'] as String?,
        phone: j['telefono'] as String?,
        latitude: (j['latitud'] as num?)?.toDouble(),
        longitude: (j['longitud'] as num?)?.toDouble(),
      );

  @override
  Future<Result<List<OrganizationSummary>>> search(String query) => _guard(() async {
        var req = _client.from('organizaciones').select().eq('publica', true).eq('activa', true);
        final q = query.trim().replaceAll(RegExp(r'[%,()]'), ' ');
        if (q.isNotEmpty) req = req.or('nombre.ilike.%$q%,ciudad.ilike.%$q%,direccion.ilike.%$q%');
        final rows = await req.order('nombre').limit(100);
        return rows.map(_row).toList();
      });

  @override
  Future<Result<OrganizationSummary>> get(String id) => _guard(() async {
        final row = await _client.from('organizaciones').select().eq('id', id).single();
        return _row(row);
      });

  @override
  Future<Result<Map<String, String>>> queuePrefixes(String organizationId) => _guard(() async {
        final rows = await _client.from('cola_prefijos').select('qhub_cola_id, prefijo').eq('organizacion_id', organizationId);
        return {for (final r in rows) r['qhub_cola_id'] as String: r['prefijo'] as String};
      });

  @override
  Future<Result<Set<String>>> favoriteIds() => _guard(() async {
        final rows = await _client.from('favoritos').select('organizacion_id');
        return {for (final r in rows) r['organizacion_id'] as String};
      });

  @override
  Future<Result<void>> setFavorite(String organizationId, bool favorite) => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) throw const UnauthorizedFailure();
        if (favorite) {
          await _client.from('favoritos').upsert({'usuario_id': uid, 'organizacion_id': organizationId}, ignoreDuplicates: true);
        } else {
          await _client.from('favoritos').delete().eq('organizacion_id', organizationId).isFilter('qhub_cola_id', null);
        }
      });
}
