import { useEffect, useMemo, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { countryByAny, friendlyError, unwrap } from '@qhub/core';
import type { Profile } from '@qhub/core';
import { EMPTY_PROFILE, validateProfile } from './profile';
import { useContainer } from '@/app/container';
import { useToast } from '@/shared/ui/kit';

/** Formulario del perfil móvil: carga, valida y guarda, con los límites de cuenta gestionada. */
export function useProfileForm() {
  const { profiles } = useContainer();
  const toast = useToast();
  const qc = useQueryClient();
  const q = useQuery({ queryKey: ['profile'], queryFn: async () => unwrap(await profiles.get()) });
  const managedQ = useQuery({ queryKey: ['profile-managed'], queryFn: async () => unwrap(await profiles.managementStatus()) });
  const [form, setForm] = useState<Profile>(EMPTY_PROFILE);
  const [saved, setSaved] = useState<Profile>(EMPTY_PROFILE);
  const [errs, setErrs] = useState<Partial<Record<keyof Profile, string>>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!q.data) return;
    const c = countryByAny(q.data.country);
    const p = { ...q.data, country: c?.code ?? q.data.country };
    setForm(p); setSaved(p);
  }, [q.data]);

  const dirty = useMemo(() => JSON.stringify(form) !== JSON.stringify(saved), [form, saved]);
  const set = <K extends keyof Profile>(k: K, v: Profile[K]) => { setForm((f) => ({ ...f, [k]: v })); setErrs((e) => ({ ...e, [k]: undefined })); };

  async function save() {
    const e = validateProfile(form);
    setErrs(e);
    if (Object.keys(e).length) return;
    setBusy(true);
    const r = await profiles.update(form);
    setBusy(false);
    if (r.ok) { setSaved(form); void qc.invalidateQueries({ queryKey: ['profile'] }); toast.show('Perfil actualizado.'); }
    else toast.show(friendlyError(r.failure), { error: true });
  }

  return {
    form, set, save, errs, busy, dirty,
    managed: managedQ.data ?? false,
    isLoading: q.isLoading,
    isError: q.isError,
    error: q.error,
    discard: () => { setForm(saved); setErrs({}); },
    saved,
  };
}
