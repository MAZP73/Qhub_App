import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, View } from 'react-native';
import { friendlyError, validatePassword } from '@qhub/core';
import { Button, Logo, Notice, Screen, TextField, Txt } from '@/shared/ui/kit';
import { useAuth, useContainer } from '@/app/container';

/** Se muestra tras abrir el enlace de recuperación del correo: la sesión ya está abierta, solo falta elegir la contraseña nueva. */
export function ResetPasswordScreen() {
  const { users, session } = useContainer();
  const auth = useAuth();
  const email = auth.status === 'ready' ? auth.value?.email : undefined;
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [errs, setErrs] = useState<{ password?: string | null; confirm?: string | null }>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    const next = { password: validatePassword(password, { mixed: false }), confirm: password === confirm ? null : 'Las contraseñas no coinciden.' };
    setErrs(next); setError(null);
    if (next.password || next.confirm) return;
    setBusy(true);
    const r = await users.updatePassword(password);
    setBusy(false);
    if (!r.ok) { setError(friendlyError(r.failure)); return; }
    session.finishRecovery();
  }

  return (
    <Screen>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} className="flex-1">
        <ScrollView contentContainerClassName="gap-4 p-4 pt-12" keyboardShouldPersistTaps="handled">
          <View className="gap-2 pb-2">
            <Logo height={32} />
            <Txt variant="h1" accessibilityRole="header" className="pt-4">Elige tu nueva contraseña</Txt>
            <Txt variant="bodyLong" color="textSecondary">{email ? `Para la cuenta ${email}.` : 'Escríbela dos veces para confirmarla.'}</Txt>
          </View>
          {error ? <Notice kind="error" title={error} /> : null}
          <View className="gap-4">
            <TextField label="Contraseña nueva" value={password} onChangeText={setPassword} error={errs.password} secure helper="Mínimo 8 caracteres." autoComplete="new-password" />
            <TextField label="Repite la contraseña" value={confirm} onChangeText={setConfirm} error={errs.confirm} secure autoComplete="new-password" />
          </View>
          <View className="gap-2 pt-2">
            <Button label="Guardar contraseña" icon="arrow-right" block loading={busy} onPress={() => void save()} />
            <Button label="Cancelar" kind="tertiary" block onPress={busy ? undefined : () => void session.cancelRecovery()} />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}
