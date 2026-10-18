import '../domain/entities.dart';

DateTime _dt(Object? v) => DateTime.parse(v as String);
DateTime? _dtOrNull(Object? v) => v == null ? null : DateTime.parse(v as String);

Queue queueFromJson(Map<String, dynamic> j) => Queue(
      id: j['id'] as String,
      ownerName: (j['propietario_nombre'] ?? '') as String,
      name: j['nombre'] as String,
      description: j['descripcion'] as String?,
      active: j['activa'] as bool,
    );

Schedule scheduleFromJson(Map<String, dynamic> j) => Schedule(
      queueId: j['cola_id'] as String,
      timeZone: j['zona_horaria'] as String,
      opens: j['hora_apertura'] as String,
      closes: j['hora_cierre'] as String,
      slotMinutes: j['duracion_franja_minutos'] as int,
      days: (j['dias_atencion'] as List).cast<int>(),
      turnMinutes: j['duracion_turno_minutos'] as int,
      stations: j['puestos'] as int,
      dailyCapacity: j['capacidad_diaria'] as int,
      maxDaysAhead: j['dias_anticipacion_maxima'] as int,
      slotsPerDay: (j['franjas_por_dia'] ?? 0) as int,
      capacityPerSlot: (j['cupos_por_franja'] ?? 0) as int,
      turnsPerDay: (j['turnos_por_dia'] ?? 0) as int,
    );

Map<String, dynamic> scheduleToJson(ScheduleInput s) => {
      'hora_apertura': s.opens.length == 5 ? '${s.opens}:00' : s.opens,
      'hora_cierre': s.closes.length == 5 ? '${s.closes}:00' : s.closes,
      'duracion_franja_minutos': s.slotMinutes,
      'dias_atencion': s.days,
      'duracion_turno_minutos': s.turnMinutes,
      'puestos': s.stations,
      'capacidad_diaria': s.dailyCapacity,
      'dias_anticipacion_maxima': s.maxDaysAhead,
      if (s.timeZone != null) 'zona_horaria': s.timeZone,
    };

Slot slotFromJson(Map<String, dynamic> j) => Slot(
      start: _dt(j['inicio']),
      end: _dt(j['fin']),
      capacity: j['cupos'] as int,
      taken: j['ocupados'] as int,
      available: j['disponibles'] as int,
    );

QueueState queueStateFromJson(Map<String, dynamic> j) => QueueState(
      queueId: j['cola_id'] as String,
      waiting: j['turnos_en_espera'] as int,
      serving: j['turnos_atendiendo'] as int,
    );

QueueLimit queueLimitFromJson(Map<String, dynamic> j) => QueueLimit(
      accountType: AccountType.parse(j['propietario_tipo'] as String),
      limit: j['limite'] as int,
      active: j['activas'] as int,
      available: j['disponibles'] as int,
    );

Ticket ticketFromJson(Map<String, dynamic> j) => Ticket(
      id: j['id'] as String,
      queueId: j['cola_id'] as String,
      ownerName: (j['propietario_nombre'] ?? '') as String,
      userId: j['usuario_id'] as String,
      slotStart: _dt(j['franja_inicio']),
      scheduled: (j['programado'] ?? false) as bool,
      number: j['numero'] as int,
      status: TicketStatus.parse(j['estado'] as String),
      position: (j['posicion'] ?? 0) as int,
      createdAt: _dt(j['hora_creacion']),
      calledAt: _dtOrNull(j['hora_atencion']),
      finishedAt: _dtOrNull(j['hora_finalizacion']),
      agentId: j['agente_id'] as String?,
    );

AppNotification notificationFromJson(Map<String, dynamic> j) => AppNotification(
      id: j['id'] as String,
      userId: (j['usuario_id'] ?? '') as String,
      ticketId: (j['turno_id']) as String?,
      message: j['mensaje'] as String,
      read: (j['leida'] ?? false) as bool,
      createdAt: _dt(j['creada_en']),
      kind: j['tipo_aviso'] as String?,
    );

Registration registrationFromJson(Map<String, dynamic> j) => Registration(
      accountType: AccountType.parse(j['propietario_tipo'] as String),
      accountId: j['propietario_id'] as String,
      username: j['nombre_usuario'] as String,
      email: j['email'] as String,
      companyName: j['nombre_empresa'] as String?,
      queueLimit: j['limite_colas'] as int,
      createdAt: _dt(j['creada_en']),
    );

Map<String, dynamic> registerToJson(RegisterInput i) => {
      'tipo_cuenta': i.accountType.name,
      if (i.companyName != null) 'nombre_empresa': i.companyName,
      'nombre': i.firstName,
      'apellido': i.lastName,
      'nombre_usuario': i.username,
      'email': i.email,
      'password': i.password,
      'pais': i.country,
      'ciudad': i.city,
      'acepto_terminos': i.acceptedTerms,
    };

/// Evento de `/ws/turnos/{cola}`. Devuelve `null` para pings y mensajes de control.
QueueEvent? queueEventFromJson(Map<String, dynamic> j) {
  final type = j['tipo'] as String?;
  if (type == null || type == 'ping' || type == 'conectado') return null;
  final payload = j['payload'];
  Ticket? ticket;
  if (payload is Map<String, dynamic> && payload['id'] != null && payload['numero'] != null) {
    try {
      ticket = ticketFromJson({
        'cola_id': j['cola_id'],
        'propietario_nombre': '',
        'usuario_id': '',
        'franja_inicio': payload['franja_inicio'] ?? DateTime.now().toUtc().toIso8601String(),
        'hora_creacion': payload['hora_creacion'] ?? DateTime.now().toUtc().toIso8601String(),
        ...payload,
      });
    } catch (_) {
      ticket = null;
    }
  }
  return QueueEvent(
    type: QueueEventType.parse(type),
    queueId: (j['cola_id'] ?? '') as String,
    ticket: ticket,
  );
}

/// Aviso de `/ws/notificaciones`: `{"tipo":"notificacion","notificacion":{…}}`.
AppNotification? notificationEventFromJson(Map<String, dynamic> j) {
  if (j['tipo'] != 'notificacion') return null;
  final n = j['notificacion'];
  if (n is! Map<String, dynamic>) return null;
  return notificationFromJson({'usuario_id': '', ...n});
}
