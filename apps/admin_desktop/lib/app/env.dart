/// Variables públicas de `.env` (nunca claves secretas: esas viven en `.env.secret`, fuera de la app).
class AppEnv {
  const AppEnv({
    required this.appEnv,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.supabaseUrl,
    required this.supabaseKey,
  });

  final String appEnv;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String supabaseUrl;
  final String supabaseKey;

  bool get isProduction => appEnv == 'production';

  /// Lanza [StateError] con un mensaje claro si falta algo.
  factory AppEnv.fromMap(Map<String, String> m) {
    String need(String k) {
      final v = m[k]?.trim() ?? '';
      if (v.isEmpty) throw StateError('Falta $k en el archivo .env');
      return v;
    }

    return AppEnv(
      appEnv: m['APP_ENV']?.trim().isNotEmpty == true ? m['APP_ENV']!.trim() : 'development',
      apiBaseUrl: need('QHUB_API_BASE_URL'),
      wsBaseUrl: need('QHUB_WS_BASE_URL'),
      supabaseUrl: need('SUPABASE_URL'),
      supabaseKey: need('SUPABASE_PUBLISHABLE_KEY'),
    );
  }
}
