import type { NotificationRepository, QueueRepository, TicketRepository } from '@qhub/api-client';

/** Acceso a la API Qhub *en nombre de una organización*. El móvil nunca ve la credencial: el servidor la usa. */
export interface QhubGateway {
  queues(organizationId: string): QueueRepository;
  tickets(organizationId: string): TicketRepository;
  notifications(organizationId: string): NotificationRepository;
}
