import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, View } from 'react-native';
import type { Failure } from '@qhub/core';
import { Button, Logo, Notice, Screen, TextField, Txt } from '@/shared/ui/kit';
import { useContainer } from '@/app/container';
import { validateEmail, validatePassword } from '@qhub/core';

export function AuthScreen() {
  const { users } = useContainer();
  const [register, setRegister] = useState(false);
  const [busy, setBusy] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [first, setFirst] = useState('');
  const [last, setLast] = useState('');
  const [errs, setErrs] = useState<Record<string, string | null>>({});
  const [error, setError] = useState<Failure | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  async function submit() {
    const next = {
      email: validateEmail(email),
      password: register ? validatePassword(password, { mixed: false }) : password ? null : 'Escribe tu contraseña.',
      first: register && !first.trim() ? 'Escribe tu nombre.' : null,
      last: register && !last.trim() ? 'Escribe tu apellido.' : null,
    };
    setErrs(next); setError(null); setInfo(null);
    if (Object.values(next).some(Boolean)) return;
    setBusy(true);
    if (register) {
      const r = await users.signUp({ email, password, firstName: first, lastName: last });
      setBusy(false);
      if (!r.ok) setError(r.failure);
      else if (r.value === null) { setInfo('Te enviamos un correo para confirmar tu cuenta. Después inicia sesión.'); setRegister(false); }
    } else {
      const r = await users.signIn(email, password);
      setBusy(false);
      if (!r.ok) setError(r.failure);
    }
  }

  return (
    <Screen>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} className="flex-1">
        <ScrollView contentContainerClassName="gap-4 p-4 pt-12" keyboardShouldPersistTaps="handled">
          <View className="gap-2 pb-2">
            <Logo height={32} />
            <Txt variant="h1" accessibilityRole="header" className="pt-4">Tu turno, sin filas.</Txt>
            <Txt variant="bodyLong" color="textSecondary">{register ? 'Crea tu cuenta para sacar y seguir turnos.' : 'Inicia sesión para ver tus turnos.'}</Txt>
          </View>
          {error ? <Notice kind="error" title={error.message} /> : null}
          {info ? <Notice kind="info" title={info} /> : null}
          <View className="gap-4">
            {register && (
              <View className="flex-row gap-2">
                <View className="flex-1"><TextField label="Nombre" value={first} onChangeText={setFirst} error={errs.first} autoComplete="given-name" /></View>
                <View className="flex-1"><TextField label="Apellido" value={last} onChangeText={setLast} error={errs.last} autoComplete="family-name" /></View>
              </View>
            )}
            <TextField label="Correo" value={email} onChangeText={setEmail} error={errs.email} keyboardType="email-address" autoCapitalize="none" autoComplete="email" />
            <TextField label="Contraseña" value={password} onChangeText={setPassword} error={errs.password} secure helper={register ? 'Mínimo 8 caracteres.' : undefined} autoComplete={register ? 'new-password' : 'current-password'} />
          </View>
          <View className="gap-2 pt-2">
            <Button label={register ? 'Crear cuenta' : 'Continuar'} icon="arrow-right" block loading={busy} onPress={() => void submit()} />
            <Button label={register ? 'Ya tengo cuenta' : 'Crear cuenta'} kind="tertiary" block onPress={busy ? undefined : () => { setRegister((r) => !r); setError(null); setInfo(null); }} />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}
