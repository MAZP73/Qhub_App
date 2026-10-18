/** Lo que una persona del equipo le pide a su administrador. */
export type RequestType = 'contrasena' | 'datos';
export const REQUEST_LABEL: Record<RequestType, string> = { contrasena: 'Cambiar su contraseña', datos: 'Cambiar sus datos' };
export interface MemberRequest { id: string; userId: string; name: string; type: RequestType; reason: string | null; createdAt: Date }
/** Estado del permiso propio. `vencida`: pasaron 24 h desde que se aprobó. */
export type PermissionStatus = 'pendiente' | 'aprobada' | 'rechazada' | 'usada' | 'vencida';
export interface MyPermission { status: PermissionStatus; expiresAt: Date | null }
export const canAskAgain = (p: MyPermission | null) => !p || p.status === 'rechazada' || p.status === 'usada' || p.status === 'vencida';
