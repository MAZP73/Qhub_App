import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { AppBar, Button, ConfirmModal, cx, IconButton, Screen, Txt } from '@/shared/ui/kit';
import { useTheme, type ThemeMode } from '@/shared/ui/theme';
import { useAuth, useContainer } from '@/app/container';
import type { Nav } from '@/app/navigation';

const MODES: ReadonlyArray<{ value: ThemeMode; label: string }> = [{ value: 'system', label: 'Sistema' }, { value: 'light', label: 'Claro' }, { value: 'dark', label: 'Oscuro' }];

export function ProfileScreen() {
  const nav = useNavigation<Nav>();
  const { users } = useContainer();
  const auth = useAuth();
  const { c, mode, setMode } = useTheme();
  const [confirm, setConfirm] = useState(false);
  const user = auth.status === 'ready' ? auth.value : null;
  return (
    <Screen>
      <AppBar title="Perfil" left={<IconButton icon="chevron-left" label="Atrás" onPress={() => nav.goBack()} />} />
      <ScrollView contentContainerClassName="gap-4 p-4">
        <View><Txt variant="h3">{user?.displayName ?? 'Tu cuenta'}</Txt><Txt color="textSecondary">{user?.email}</Txt></View>
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
