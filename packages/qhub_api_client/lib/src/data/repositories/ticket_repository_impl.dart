import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../api_client.dart';
import '../mappers.dart';

class TicketRepositoryImpl implements TicketRepository {
  TicketRepositoryImpl(this._dio);
  final Dio _dio;

  Ticket _one(Response<Map<String, dynamic>> r) => ticketFromJson(r.data!);
  List<Ticket> _many(Response<Object> r) =>
      (r.data as List).cast<Map<String, dynamic>>().map(ticketFromJson).toList();

  @override
  Future<Result<Ticket>> create(String queueId, {DateTime? slotStart}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/turnos', data: {
          'cola_id': queueId,
          if (slotStart != null) 'franja_inicio': slotStart.toUtc().toIso8601String(),
        });
        return _one(r);
      });

  @override
  Future<Result<List<Ticket>>> mine({int limit = 500, int offset = 0}) => guard(() async {
        final r = await _dio.get<Object>('/turnos/mios', queryParameters: {'limite': limit, 'desde': offset});
        return _many(r);
      });

  @override
  Future<Result<List<Ticket>>> list(TicketFilter f) => guard(() async {
        final d = f.date;
        final r = await _dio.get<Object>('/turnos', queryParameters: {
          if (f.queueId != null) 'cola_id': f.queueId,
          if (f.status != null) 'estado': f.status!.wire,
          if (d != null)
            'fecha': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          'limite': f.limit,
          'desde': f.offset,
        });
        return _many(r);
      });

  @override
  Future<Result<Ticket>> get(String id) => guard(() async => _one(await _dio.get('/turnos/$id')));

  @override
  Future<Result<Ticket>> postpone(String id) => guard(() async => _one(await _dio.patch('/turnos/$id/posponer')));

  @override
  Future<Result<Ticket>> cancel(String id) => guard(() async => _one(await _dio.patch('/turnos/$id/cancelar')));

  @override
  Future<Result<Ticket>> call(String id) => guard(() async => _one(await _dio.patch('/turnos/$id/atender')));

  @override
  Future<Result<Ticket>> finish(String id) => guard(() async => _one(await _dio.patch('/turnos/$id/finalizar')));

  @override
  Future<Result<Ticket>> noShow(String id) => guard(() async => _one(await _dio.patch('/turnos/$id/no-show')));
}
