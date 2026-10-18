import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';

class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<Result<Readiness>> ready() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/listo',
            options: Options(validateStatus: (s) => s == 200 || s == 503));
        final j = r.data ?? const {};
        return Readiness(
          supabase: '${j['supabase'] ?? 'desconocido'}',
          rabbitmq: '${j['rabbitmq'] ?? 'desconocido'}',
        );
      });
}
