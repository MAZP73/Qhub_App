/// Variables públicas de `.env`. El móvil NO guarda credenciales de la API Qhub: habla con ella
/// a través de la Edge Function `qhub-proxy` (ver docs/arquitectura).
class AppEnv {
  const AppEnv({required this.appEnv, required this.supabaseUrl, required this.supabaseKey});
  final String appEnv;
  final String supabaseUrl;
  final String supabaseKey;

  factory AppEnv.fromMap(Map<String, String> m) {
    String need(String k) {
      final v = m[k]?.trim() ?? '';
      if (v.isEmpty) throw StateError('Falta $k en el archivo .env');
      return v;
    }

    return AppEnv(
      appEnv: m['APP_ENV']?.trim().isNotEmpty == true ? m['APP_ENV']!.trim() : 'development',
      supabaseUrl: need('SUPABASE_URL'),
      supabaseKey: need('SUPABASE_PUBLISHABLE_KEY'),
    );
  }
}
