import 'package:qhub_core/qhub_core.dart';

class OrganizationSummary {
  const OrganizationSummary({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.address,
    this.city,
    this.country,
    this.phone,
    this.latitude,
    this.longitude,
  });
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? address;
  final String? city;
  final String? country;
  final String? phone;
  final double? latitude;
  final double? longitude;

  /// Iniciales para la marca (`Notaría 12` → `N12`).
  String get mark {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 3)).toUpperCase();
    final letters = words.take(3).map((w) => w[0]).join().toUpperCase();
    return letters;
  }

  String get location => [address, city].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

abstract interface class OrganizationRepository {
  /// Organizaciones visibles al público (publicadas y activas), filtradas por nombre/ciudad.
  Future<Result<List<OrganizationSummary>>> search(String query);
  Future<Result<OrganizationSummary>> get(String id);
  /// Prefijo visible de cada cola (`C` → `C-023`); el público también puede leerlo.
  Future<Result<Map<String, String>>> queuePrefixes(String organizationId);
  Future<Result<Set<String>>> favoriteIds();
  Future<Result<void>> setFavorite(String organizationId, bool favorite);
}
