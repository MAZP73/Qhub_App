Map<String, dynamic> ticketJson({
  String id = 't1',
  int numero = 5,
  String estado = 'en_espera',
  int posicion = 1,
  String franja = '2026-10-20T15:00:00Z',
  bool programado = false,
}) =>
    {
      'id': id,
      'cola_id': 'q1',
      'propietario_tipo': 'empresa',
      'propietario_id': 'o1',
      'propietario_nombre': 'Clínica Norte',
      'usuario_id': 'cli-1',
      'franja_inicio': franja,
      'franja_fecha': '2026-10-20',
      'programado': programado,
      'numero': numero,
      'estado': estado,
      'posicion': posicion,
      'hora_creacion': '2026-10-20T14:00:00Z',
      'hora_atencion': null,
      'hora_finalizacion': null,
      'agente_id': null,
    };

Map<String, dynamic> queueJson({String id = 'q1', String nombre = 'Caja 1', bool activa = true}) => {
      'id': id,
      'propietario_tipo': 'empresa',
      'propietario_id': 'o1',
      'propietario_nombre': 'Clínica Norte',
      'nombre': nombre,
      'descripcion': null,
      'activa': activa,
      'rabbitmq_queue_name': 'qhub.empresa.clinica-norte.caja-1',
    };

Map<String, dynamic> scheduleJson() => {
      'cola_id': 'q1',
      'zona_horaria': 'America/Guayaquil',
      'hora_apertura': '08:00:00',
      'hora_cierre': '18:00:00',
      'duracion_franja_minutos': 30,
      'dias_atencion': [1, 2, 3, 4, 5],
      'duracion_turno_minutos': 10,
      'puestos': 2,
      'capacidad_diaria': 0,
      'dias_anticipacion_maxima': 7,
      'franjas_por_dia': 20,
      'cupos_por_franja': 6,
      'turnos_por_dia': 120,
    };
