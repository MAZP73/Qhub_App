import 'package:equatable/equatable.dart';

enum AccountType {
  empresa,
  usuario;

  static AccountType parse(String v) => v == 'usuario' ? usuario : empresa;
}

/// Rol que el sistema integrador informa en `X-Usuario-Rol`.
enum ActorRole {
  admin,
  agente,
  cliente;

  String get wire => name;
}

enum TicketStatus {
  enEspera('en_espera'),
  atendiendo('atendiendo'),
  finalizado('finalizado'),
  cancelado('cancelado'),
  noShow('no_show');

  const TicketStatus(this.wire);
  final String wire;

  static TicketStatus parse(String v) =>
      TicketStatus.values.firstWhere((s) => s.wire == v, orElse: () => TicketStatus.enEspera);

  /// Solo cancelado y no-show liberan el cupo de la franja.
  bool get releasesSlot => this == cancelado || this == noShow;
  bool get isActive => this == enEspera || this == atendiendo;
}

class AuthToken extends Equatable {
  const AuthToken({required this.accessToken, required this.expiresIn, required this.issuedAt});
  final String accessToken;
  final int expiresIn;
  final DateTime issuedAt;

  DateTime get expiresAt => issuedAt.add(Duration(seconds: expiresIn));
  bool isExpired(DateTime now, {Duration skew = const Duration(seconds: 30)}) =>
      now.isAfter(expiresAt.subtract(skew));

  @override
  List<Object?> get props => [accessToken, expiresIn, issuedAt];
}

/// Persona que actúa: la API la cree por header, no la gestiona.
class Actor extends Equatable {
  const Actor({required this.userId, required this.role});
  final String userId;
  final ActorRole role;

  @override
  List<Object?> get props => [userId, role];
}

class Registration extends Equatable {
  const Registration({
    required this.accountType,
    required this.accountId,
    required this.username,
    required this.email,
    required this.queueLimit,
    required this.createdAt,
    this.companyName,
  });
  final AccountType accountType;
  final String accountId;
  final String username;
  final String email;
  final String? companyName;
  final int queueLimit;
  final DateTime createdAt;

  @override
  List<Object?> get props => [accountType, accountId, username, email, companyName, queueLimit, createdAt];
}

class RegisterInput extends Equatable {
  const RegisterInput({
    required this.accountType,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    required this.password,
    required this.country,
    required this.city,
    required this.acceptedTerms,
    this.companyName,
  });
  final AccountType accountType;
  final String? companyName;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String password;
  final String country;
  final String city;
  final bool acceptedTerms;

  @override
  List<Object?> get props =>
      [accountType, companyName, firstName, lastName, username, email, country, city, acceptedTerms];
}

class Queue extends Equatable {
  const Queue({
    required this.id,
    required this.ownerName,
    required this.name,
    required this.active,
    this.description,
  });
  final String id;
  final String ownerName;
  final String name;
  final String? description;
  final bool active;

  @override
  List<Object?> get props => [id, ownerName, name, description, active];
}

/// Horario con valores derivados que calcula la API (franjas y cupos).
class Schedule extends Equatable {
  const Schedule({
    required this.queueId,
    required this.timeZone,
    required this.opens,
    required this.closes,
    required this.slotMinutes,
    required this.days,
    required this.turnMinutes,
    required this.stations,
    required this.dailyCapacity,
    required this.maxDaysAhead,
    this.slotsPerDay = 0,
    this.capacityPerSlot = 0,
    this.turnsPerDay = 0,
  });
  final String queueId;
  final String timeZone;
  final String opens; // HH:mm:ss
  final String closes;
  final int slotMinutes;
  final List<int> days; // ISO 1=lunes … 7=domingo
  final int turnMinutes;
  final int stations;
  final int dailyCapacity; // 0 = sin tope
  final int maxDaysAhead;
  final int slotsPerDay;
  final int capacityPerSlot;
  final int turnsPerDay;

  @override
  List<Object?> get props => [queueId, timeZone, opens, closes, slotMinutes, days, turnMinutes, stations,
        dailyCapacity, maxDaysAhead, slotsPerDay, capacityPerSlot, turnsPerDay];
}

/// Datos para `PUT /colas/{id}/horario` (se reemplaza completo).
class ScheduleInput extends Equatable {
  const ScheduleInput({
    required this.opens,
    required this.closes,
    required this.slotMinutes,
    required this.days,
    required this.turnMinutes,
    required this.maxDaysAhead,
    this.stations = 1,
    this.dailyCapacity = 0,
    this.timeZone,
  });
  final String opens;
  final String closes;
  final int slotMinutes;
  final List<int> days;
  final int turnMinutes;
  final int stations;
  final int dailyCapacity;
  final int maxDaysAhead;
  final String? timeZone;

  /// Cupos por franja: `floor(franja / trámite) × puestos`. Misma regla que la API.
  int get capacityPerSlot => turnMinutes <= 0 ? 0 : (slotMinutes ~/ turnMinutes) * stations;

  @override
  List<Object?> get props =>
      [opens, closes, slotMinutes, days, turnMinutes, stations, dailyCapacity, maxDaysAhead, timeZone];
}

class CreateQueueInput extends Equatable {
  const CreateQueueInput({required this.name, this.description, this.schedule});
  final String name;
  final String? description;
  final ScheduleInput? schedule;

  @override
  List<Object?> get props => [name, description, schedule];
}

class Slot extends Equatable {
  const Slot({
    required this.start,
    required this.end,
    required this.capacity,
    required this.taken,
    required this.available,
  });
  final DateTime start;
  final DateTime end;
  final int capacity;
  final int taken;
  final int available;

  bool get isFull => available <= 0;
  bool get isLow => available > 0 && available <= 2;

  @override
  List<Object?> get props => [start, end, capacity, taken, available];
}

class QueueState extends Equatable {
  const QueueState({required this.queueId, required this.waiting, required this.serving});
  final String queueId;
  final int waiting;
  final int serving;

  @override
  List<Object?> get props => [queueId, waiting, serving];
}

class QueueLimit extends Equatable {
  const QueueLimit({required this.accountType, required this.limit, required this.active, required this.available});
  final AccountType accountType;
  final int limit;
  final int active;
  final int available;

  @override
  List<Object?> get props => [accountType, limit, active, available];
}

class Ticket extends Equatable {
  const Ticket({
    required this.id,
    required this.queueId,
    required this.ownerName,
    required this.userId,
    required this.slotStart,
    required this.scheduled,
    required this.number,
    required this.status,
    required this.position,
    required this.createdAt,
    this.calledAt,
    this.finishedAt,
    this.agentId,
  });
  final String id;
  final String queueId;
  final String ownerName;
  final String userId;
  final DateTime slotStart;
  final bool scheduled;
  final int number;
  final TicketStatus status;
  final int position;
  final DateTime createdAt;
  final DateTime? calledAt;
  final DateTime? finishedAt;
  final String? agentId;

  @override
  List<Object?> get props => [id, queueId, ownerName, userId, slotStart, scheduled, number, status, position,
        createdAt, calledAt, finishedAt, agentId];
}

class TicketFilter extends Equatable {
  const TicketFilter({this.queueId, this.status, this.date, this.limit = 500, this.offset = 0});
  final String? queueId;
  final TicketStatus? status;
  final DateTime? date;
  final int limit;
  final int offset;

  @override
  List<Object?> get props => [queueId, status, date, limit, offset];
}

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.message,
    required this.read,
    required this.createdAt,
    this.ticketId,
    this.kind,
  });
  final String id;
  final String userId;
  final String? ticketId;
  final String message;
  final bool read;
  final DateTime createdAt;
  final String? kind; // turno_llamado · turno_pospuesto · turno_no_show · recordatorio

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        userId: userId,
        message: message,
        read: read ?? this.read,
        createdAt: createdAt,
        ticketId: ticketId,
        kind: kind,
      );

  @override
  List<Object?> get props => [id, userId, ticketId, message, read, createdAt, kind];
}

enum QueueEventType {
  ticketCreated('turno_creado'),
  ticketCalled('turno_llamado'),
  ticketPostponed('turno_pospuesto'),
  ticketCancelled('turno_cancelado'),
  ticketNoShow('turno_no_show'),
  queueUpdated('cola_actualizada'),
  unknown('');

  const QueueEventType(this.wire);
  final String wire;

  static QueueEventType parse(String v) =>
      QueueEventType.values.firstWhere((e) => e.wire == v && e != unknown, orElse: () => unknown);
}

class QueueEvent extends Equatable {
  const QueueEvent({required this.type, required this.queueId, this.ticket});
  final QueueEventType type;
  final String queueId;
  final Ticket? ticket;

  @override
  List<Object?> get props => [type, queueId, ticket];
}

enum ConnectionStatus { connecting, connected, reconnecting, closed }

/// Salud de la API (`GET /listo`).
class Readiness extends Equatable {
  const Readiness({required this.supabase, required this.rabbitmq});
  final String supabase;
  final String rabbitmq;
  bool get isReady => supabase == 'ok';

  @override
  List<Object?> get props => [supabase, rabbitmq];
}
