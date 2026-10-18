import 'package:qhub_core/qhub_core.dart';

import 'entities.dart';

abstract interface class AuthRepository {
  /// `POST /auth/token` con email o nombre de usuario.
  Future<Result<AuthToken>> login({required String identifier, required String password});

  /// `POST /auth/registro`.
  Future<Result<Registration>> register(RegisterInput input);
}

abstract interface class QueueRepository {
  Future<Result<List<Queue>>> list({bool? active});
  Future<Result<Queue>> get(String id);
  Future<Result<Queue>> create(CreateQueueInput input);
  Future<Result<Queue>> update(String id, {String? name, String? description, bool? active});
  Future<Result<void>> delete(String id);
  Future<Result<QueueLimit>> limit();
  Future<Result<Schedule>> schedule(String id);
  Future<Result<Schedule>> replaceSchedule(String id, ScheduleInput input);
  Future<Result<List<Slot>>> slots(String id, {DateTime? date});
  Future<Result<QueueState>> state(String id);
}

abstract interface class TicketRepository {
  /// Sin [slotStart] = en vivo; con él = programado.
  Future<Result<Ticket>> create(String queueId, {DateTime? slotStart});
  Future<Result<List<Ticket>>> mine({int limit = 500, int offset = 0});
  Future<Result<List<Ticket>>> list(TicketFilter filter);
  Future<Result<Ticket>> get(String id);
  Future<Result<Ticket>> postpone(String id);
  Future<Result<Ticket>> cancel(String id);
  Future<Result<Ticket>> call(String id); // atender
  Future<Result<Ticket>> finish(String id);
  Future<Result<Ticket>> noShow(String id);
}

abstract interface class NotificationRepository {
  Future<Result<List<AppNotification>>> list({int limit = 100, int offset = 0});
  Future<Result<AppNotification>> markRead(String id);
  Future<Result<void>> delete(String id);
}

abstract interface class RealtimeRepository {
  /// Eventos de una cola. Reconecta solo; se cancela al cerrar la suscripción.
  Stream<QueueEvent> queueEvents(String queueId);

  /// Avisos personales de la persona actual.
  Stream<AppNotification> notifications();

  Stream<ConnectionStatus> get status;
}

abstract interface class HealthRepository {
  Future<Result<Readiness>> ready();
}
