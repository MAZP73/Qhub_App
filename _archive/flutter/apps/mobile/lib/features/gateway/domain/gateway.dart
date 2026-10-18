import 'package:qhub_api_client/qhub_api_client.dart';

/// Acceso a la API Qhub *en nombre de una organización*. El móvil nunca ve la credencial:
/// una implementación (Edge Function) la usa del lado del servidor.
abstract interface class QhubGateway {
  QueueRepository queues(String organizationId);
  TicketRepository tickets(String organizationId);
  NotificationRepository notifications(String organizationId);
}
