import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { countryByAny } from '@qhub/core';
import { AppBar, Button, ConfirmModal, cx, IconButton, Notice, Screen, Skeleton, TextField, Txt } from '@/shared/ui/kit';
import { useTheme, type ThemeMode } from '@/shared/ui/theme';
import { useAuth, useContainer } from '@/app/container';
import type { Nav } from '@/app/navigation';
import { managedFields } from './profile';
import { useProfileForm } from './useProfileForm';
import { LocationFields } from './LocationFields';
import { PhoneField } from './PhoneField';

const MODES: ReadonlyArray<{ value: ThemeMode; label: string }> = [{ value: 'system', label: 'Sistema' }, { value: 'light', label: 'Claro' }, { value: 'dark', label: 'Oscuro' }];

export function ProfileScreen() {
  const nav = useNavigation<Nav>();
  const { users } = useContainer();
  const auth = useAuth();
  const { c, mode, setMode } = useTheme();
  const [confirm, setConfirm] = useState(false);
  const user = auth.status === 'ready' ? auth.value : null;
  const p = useProfileForm();
  // Un campo gestionado ya completo no se edita (el administrador lo gestiona), igual que el web.
  const locked = (f: (typeof managedFields)[number]) => p.managed && !!p.saved[f];

  return (
    <Screen>
      <AppBar title="Perfil" left={<IconButton icon="chevron-left" label="Atrás" onPress={() => nav.goBack()} />} />
      <ScrollView contentContainerClassName="gap-6 p-4">
        <View><Txt variant="h3">{user?.displayName ?? 'Tu cuenta'}</Txt><Txt color="textSecondary">{user?.email}</Txt></View>

        <View className="gap-3" accessibilityLabel="Datos personales">
          <Txt variant="h4" accessibilityRole="header">Datos personales</Txt>
          {p.isLoading ? <Skeleton height={240} />
            : p.isError ? <Notice kind="error" title="No pudimos cargar tu perfil." message="Inténtalo de nuevo en un momento." />
            : <View className="gap-3">
                {p.managed && <Notice kind="info" title="Tu administrador gestiona tu nombre, apellido, cargo y teléfono." message="Si algo está mal, pídele el cambio." />}
                <TextField label="Nombre" value={p.form.firstName} editable={!locked('firstName')} onChangeText={(v) => p.set('firstName', v)} error={p.errs.firstName} maxLength={60} />
                <TextField label="Apellido" value={p.form.lastName} editable={!locked('lastName')} onChangeText={(v) => p.set('lastName', v)} error={p.errs.lastName} maxLength={60} />
                <TextField label="Cargo" value={p.form.jobTitle} editable={!locked('jobTitle')} onChangeText={(v) => p.set('jobTitle', v)} error={p.errs.jobTitle} maxLength={80} helper="Opcional." />
                <PhoneField value={p.form.phone} disabled={locked('phone')} onChange={(v) => p.set('phone', v)} error={p.errs.phone} defaultCountry={countryByAny(p.form.country)?.code ?? 'EC'} />
                <LocationFields value={{ country: p.form.country, city: p.form.city, timeZone: p.form.timeZone }} errors={{ country: p.errs.country }}
                  onChange={(l) => { p.set('country', l.country); p.set('city', l.city); p.set('timeZone', l.timeZone); }} />
                <View className="pt-1"><Button label="Guardar" icon="check" block loading={p.busy} disabled={!p.dirty} onPress={() => void p.save()} /></View>
              </View>}
        </View>

        <View className="gap-2">
          <Txt variant="label" color="textSecondary">Tema</Txt>
          <View className="flex-row gap-2">
            {MODES.map((m) => (
              <Pressable key={m.value} accessibilityRole="button" accessibilityLabel={m.label} accessibilityState={{ selected: mode === m.value }} onPress={() => setMode(m.value)}
                className={cx('h-10 flex-1 items-center justify-center', mode === m.value ? 'bg-interactive' : 'bg-layer-02')}>
                <Txt color={mode === m.value ? 'textOnColor' : 'textPrimary'} weight={600}>{m.label}</Txt>
              </Pressable>
            ))}
          </View>
        </View>
        <Button label="Cerrar sesión" icon="logout" kind="secondary" block onPress={() => setConfirm(true)} />
      </ScrollView>
      <ConfirmModal visible={confirm} title="Cerrar sesión" message="Tendrás que volver a iniciar sesión para ver tus turnos." confirmLabel="Cerrar sesión" danger={false}
        onCancel={() => setConfirm(false)} onConfirm={() => { setConfirm(false); void users.signOut(); }} />
    </Screen>
  );
}
