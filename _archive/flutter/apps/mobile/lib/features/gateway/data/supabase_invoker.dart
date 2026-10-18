import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'proxy_adapter.dart';

/// Invoca la Edge Function `qhub-proxy`. Los errores de la API vienen en el sobre (status 4xx/5xx);
/// un error de la función misma (401 sin sesión, red) se traduce a [Failure].
ProxyInvoker supabaseProxyInvoker(SupabaseClient client) => (orgId, request) async {
      try {
        final res = await client.functions.invoke('qhub-proxy', body: request.toJson(orgId));
        final data = res.data;
        if (data is Map && data['status'] is int) return ProxyResult(data['status'] as int, data['body']);
        throw const ServerFailure();
      } on FunctionException catch (e) {
        if (e.status == 401) throw const UnauthorizedFailure();
        if (e.status == 404) throw const NotFoundFailure();
        if (e.status == 429) throw const RateLimitedFailure();
        throw const ServerFailure();
      }
    };
