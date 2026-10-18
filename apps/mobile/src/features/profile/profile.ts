import type { Result } from '@qhub/core';

export { type Profile, EMPTY_PROFILE, isProfileComplete, validateProfile } from '@qhub/core';

/** Campos que gestiona el administrador en una cuenta de empresa: una vez completos, la persona no los edita. */
export const managedFields = ['firstName', 'lastName', 'phone', 'jobTitle'] as const;
export type ManagedField = (typeof managedFields)[number];

import type { Profile } from '@qhub/core';

export interface ProfileRepository {
  get(): Promise<Result<Profile>>;
  update(p: Profile): Promise<Result<Profile>>;
  /** `true` si la cuenta es gestionada (empresa y la persona no es administradora). */
  managementStatus(): Promise<Result<boolean>>;
}
