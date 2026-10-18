import { ApiContext } from '@qhub/api-client';
import { AppSession } from '@/features/session/domain/app-session';
import { ConnectToQhub, type TokenStore } from '@/features/qhub/domain/connection';
import type { AuthRepository } from '@qhub/api-client';
import type { StaffRepository } from '@/features/staff/domain';
import type { SecurityRepository } from '@/features/security/domain/security';
import type { QhubLinkRepository } from '@/features/qhub/domain/link';
import type { CredentialVault } from '@/features/qhub/domain/vault';

export function buildTestSession(staff: StaffRepository, auth: AuthRepository, store: TokenStore, security?: SecurityRepository, link?: QhubLinkRepository, vault?: CredentialVault, context = new ApiContext()) {
  return { context, session: new AppSession(staff, new ConnectToQhub(auth, context, store, link, vault), context, security, link) };
}
