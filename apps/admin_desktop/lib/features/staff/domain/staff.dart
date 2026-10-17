import 'package:qhub_api_client/qhub_api_client.dart' show ActorRole;
import 'package:qhub_core/qhub_core.dart';

enum OrgRole {
  admin,
  agente;

  static OrgRole parse(String v) => v == 'admin' ? admin : agente;
  String get wire => name;
  String get label => this == admin ? 'Administrador' : 'Agente';
  ActorRole get actorRole => this == admin ? ActorRole.admin : ActorRole.agente;
}

class StaffUser {
  const StaffUser({required this.id, required this.email, this.displayName});
  final String id;
  final String email;
  final String? displayName;

  String get initials {
    final base = (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : email;
    final parts = base.split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.timeZone,
    this.city,
    this.country,
    this.published = false,
  });
  final String id;
  final String name;
  final String slug;
  final String timeZone;
  final String? city;
  final String? country;
  final bool published;
}

class Membership {
  const Membership({required this.organization, required this.role});
  final Organization organization;
  final OrgRole role;
  bool get isAdmin => role == OrgRole.admin;
}

class Member {
  const Member({required this.userId, required this.name, required this.role, required this.active});
  final String userId;
  final String name;
  final OrgRole role;
  final bool active;
}

class Invitation {
  const Invitation({
    required this.id,
    required this.email,
    required this.role,
    required this.token,
    required this.expiresAt,
    this.acceptedAt,
  });
  final String id;
  final String email;
  final OrgRole role;
  final String token;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  bool get pending => acceptedAt == null && expiresAt.isAfter(DateTime.now());
}

/// Identidad y datos propios del escritorio (Supabase). Nunca habla con la API Qhub.
abstract interface class StaffRepository {
  StaffUser? get currentUser;
  Stream<StaffUser?> authChanges();

  Future<Result<StaffUser>> signIn({required String email, required String password});
  Future<Result<StaffUser?>> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });
  Future<Result<void>> signOut();

  Future<Result<List<Membership>>> memberships();
  Future<Result<String>> createOrganization({
    required String name,
    required String slug,
    String? city,
    String? country,
    String timeZone,
  });
  Future<Result<String>> acceptInvitation(String token);
  Future<Result<Organization>> updateOrganization(String id, {String? name, bool? published, String? city, String? country});

  Future<Result<List<Member>>> members(String orgId);
  Future<Result<void>> updateMember(String orgId, String userId, {OrgRole? role, bool? active});
  Future<Result<void>> removeMember(String orgId, String userId);
  Future<Result<Invitation>> invite(String orgId, {required String email, required OrgRole role});
  Future<Result<List<Invitation>>> invitations(String orgId);

  Future<Result<Map<String, String>>> queuePrefixes(String orgId);
  Future<Result<void>> setQueuePrefix(String orgId, String queueId, String prefix);

  Future<Result<void>> audit(String orgId, String action, {String? entity, String? entityId, Map<String, Object?> detail});
}

/// Genera un slug `[a-z0-9-]+` a partir de un nombre.
String slugify(String name) {
  const map = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final lowered = name.toLowerCase().split('').map((c) => map[c] ?? c).join();
  final slug = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'organizacion' : slug;
}
