import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';
import '../mappers.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<Result<List<AppNotification>>> list({int limit = 100, int offset = 0}) => guard(() async {
        final r = await _dio.get<Object>('/notificaciones', queryParameters: {'limite': limit, 'desde': offset});
        return (r.data as List).cast<Map<String, dynamic>>().map(notificationFromJson).toList();
      });

  @override
  Future<Result<AppNotification>> markRead(String id) => guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/notificaciones/$id/leida');
        return notificationFromJson(r.data!);
      });

  @override
  Future<Result<void>> delete(String id) => guard(() async {
        await _dio.delete<void>('/notificaciones/$id');
      });
}
