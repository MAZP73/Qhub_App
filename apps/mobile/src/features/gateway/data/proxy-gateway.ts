import { isFailure, networkFailure } from '@qhub/core';
import { NotificationRepositoryImpl, QueueRepositoryImpl, TicketRepositoryImpl, type HttpRequest, type HttpResponse, type HttpTransport } from '@qhub/api-client';
import type { QhubGateway } from '../domain/gateway';

export interface ProxyRequest { method: string; path: string; query: Record<string, string>; body?: unknown }
/** Envía la petición a la Edge Function y devuelve el sobre `{status, body}` con la respuesta de la API. */
export type ProxyInvoker = (organizationId: string, request: ProxyRequest) => Promise<HttpResponse>;

/** Cuerpo que recibe `qhub-proxy`. Ningún header de identidad sale del móvil: la función pone la identidad. */
export const toProxyPayload = (organizationId: string, r: ProxyRequest) => ({
  organizacion_id: organizationId, method: r.method, path: r.path, query: r.query, ...(r.body !== undefined ? { body: r.body } : {}),
});

/** Hace que los repositorios de `@qhub/api-client` funcionen igual a través del proxy. */
export class ProxyTransport implements HttpTransport {
  constructor(private readonly organizationId: string, private readonly invoke: ProxyInvoker) {}
  async send(req: HttpRequest): Promise<HttpResponse> {
    const query: Record<string, string> = {};
    for (const [k, v] of Object.entries(req.query ?? {})) if (v !== undefined) query[k] = String(v);
    try {
      return await this.invoke(this.organizationId, { method: req.method, path: req.path, query, body: req.body });
    } catch (e) {
      throw isFailure(e) ? e : networkFailure();
    }
  }
}

export class ProxyQhubGateway implements QhubGateway {
  private readonly transports = new Map<string, ProxyTransport>();
  constructor(private readonly invoke: ProxyInvoker) {}
  private t(org: string) { let t = this.transports.get(org); if (!t) { t = new ProxyTransport(org, this.invoke); this.transports.set(org, t); } return t; }
  queues(org: string) { return new QueueRepositoryImpl(this.t(org)); }
  tickets(org: string) { return new TicketRepositoryImpl(this.t(org)); }
  notifications(org: string) { return new NotificationRepositoryImpl(this.t(org)); }
}
