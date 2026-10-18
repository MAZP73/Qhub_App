import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';
import '../mappers.dart';

class QueueRepositoryImpl implements QueueRepository {
  QueueRepositoryImpl(this._dio);
  final Dio _dio;

  List<Map<String, dynamic>> _list(Object? data) => (data as List).cast<Map<String, dynamic>>();

  @override
  Future<Result<List<Queue>>> list({bool? active}) => guard(() async {
        final r = await _dio.get<Object>('/colas', queryParameters: {if (active != null) 'activa': active});
        return _list(r.data).map(queueFromJson).toList();
      });

  @override
  Future<Result<Queue>> get(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/colas/$id');
        return queueFromJson(r.data!);
      });

  @override
  Future<Result<Queue>> create(CreateQueueInput input) => guard(() async {
        final s = input.schedule;
        final r = await _dio.post<Map<String, dynamic>>('/colas', data: {
          'nombre': input.name.trim(),
          if (input.description != null && input.description!.trim().isNotEmpty)
            'descripcion': input.description!.trim(),
          if (s != null) ...{
            'hora_apertura': s.opens.length == 5 ? '${s.opens}:00' : s.opens,
            'hora_cierre': s.closes.length == 5 ? '${s.closes}:00' : s.closes,
            'duracion_franja_minutos': s.slotMinutes,
            'dias_atencion': s.days,
            'duracion_turno_minutos': s.turnMinutes,
            'puestos': s.stations,
            'capacidad_diaria': s.dailyCapacity,
            'dias_anticipacion_maxima': s.maxDaysAhead,
          },
        });
        return queueFromJson(r.data!);
      });

  @override
  Future<Result<Queue>> update(String id, {String? name, String? description, bool? active}) => guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/colas/$id', data: {
          if (name != null) 'nombre': name,
          if (description != null) 'descripcion': description,
          if (active != null) 'activa': active,
        });
        return queueFromJson(r.data!);
      });

  @override
  Future<Result<void>> delete(String id) => guard(() async {
        await _dio.delete<void>('/colas/$id');
      });

  @override
  Future<Result<QueueLimit>> limit() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/colas/limite');
        return queueLimitFromJson(r.data!);
      });

  @override
  Future<Result<Schedule>> schedule(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/colas/$id/horario');
        return scheduleFromJson(r.data!);
      });

  @override
  Future<Result<Schedule>> replaceSchedule(String id, ScheduleInput input) => guard(() async {
        final r = await _dio.put<Map<String, dynamic>>('/colas/$id/horario', data: scheduleToJson(input));
        return scheduleFromJson(r.data!);
      });

  @override
  Future<Result<List<Slot>>> slots(String id, {DateTime? date}) => guard(() async {
        final r = await _dio.get<Object>('/colas/$id/franjas', queryParameters: {
          if (date != null)
            'fecha': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        });
        return _list(r.data).map(slotFromJson).toList();
      });

  @override
  Future<Result<QueueState>> state(String id) => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/colas/$id/estado');
        return queueStateFromJson(r.data!);
      });
}
