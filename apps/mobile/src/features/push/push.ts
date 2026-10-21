/** Notificaciones push del teléfono: registra el dispositivo para recibir los avisos de turno aunque la app esté cerrada. */
export interface PushService {
  /** Pide permiso y registra este teléfono para la persona con sesión. Nunca falla: sin permiso o sin push (Expo Go, emulador) no hace nada. */
  enable(): Promise<void>;
  /** Quita este teléfono de la persona (al cerrar sesión). */
  disable(): Promise<void>;
}
