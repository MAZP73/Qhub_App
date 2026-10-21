import { useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, View } from 'react-native';
import type { Failure } from '@qhub/core';
import { Button, Logo, Notice, Screen, TextField, Txt } from '@/shared/ui/kit';
import { useContainer, useLinkNotice } from '@/app/container';
import { validateEmail, validatePassword } from '@qhub/core';

export function AuthScreen() {
  const { users, session } = useContainer();
  const linkNotice = useLinkNotice();
  const [register, setRegister] = useState(false);
  const [forgot, setForgot] = useState(false);
  const [busy, setBusy] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [first, setFirst] = useState('');
  const [last, setLast] = useState('');
  const [errs, setErrs] = useState<Record<string, string | null>>({});
  const [error, setError] = useState<Failure | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  async function sendReset() {
    const next = { email: validateEmail(email) };
    setErrs(next); setError(null); setInfo(null);
    if (next.email) return;
    setBusy(true);
    const r = await users.requestPasswordReset(email);
    setBusy(false);
    if (!r.ok) { setError(r.failure); return; }
    setInfo('Si el correo está registrado, te enviamos un enlace para elegir una contraseña nueva. Ábrelo desde este teléfono.');
  }

  function mode(next: 'login' | 'register' | 'forgot') {
    setRegister(next === 'register'); setForgot(next === 'forgot');
    setError(null); setInfo(null); setErrs({}); session.clearNotice();
  }

  async function submit() {
    if (forgot) return sendReset();
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
      if (!r.ok) {
        setError(r.failure);
        if (r.failure.kind === 'validation' && r.failure.fields) setErrs((e) => ({ ...e, ...r.failure.fields }));
      } else if (r.value === null) { setInfo('Te enviamos un correo para confirmar tu cuenta. Ábrelo desde este teléfono y volverás a la app con la sesión iniciada.'); setRegister(false); }
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
            <Txt variant="bodyLong" color="textSecondary">{forgot ? 'Te enviaremos un enlace para elegir una contraseña nueva.' : register ? 'Crea tu cuenta para sacar y seguir turnos.' : 'Inicia sesión para ver tus turnos.'}</Txt>
          </View>
          {linkNotice ? <Notice kind={linkNotice.kind} title={linkNotice.text} /> : null}
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
            {!forgot && <TextField label="Contraseña" value={password} onChangeText={setPassword} error={errs.password} secure helper={register ? 'Mínimo 8 caracteres.' : undefined} autoComplete={register ? 'new-password' : 'current-password'} />}
          </View>
          <View className="gap-2 pt-2">
            <Button label={forgot ? 'Enviar enlace' : register ? 'Crear cuenta' : 'Continuar'} icon="arrow-right" block loading={busy} onPress={() => void submit()} />
            {!register && !forgot && <Button label="¿Olvidaste tu contraseña?" kind="tertiary" block onPress={busy ? undefined : () => mode('forgot')} />}
            <Button label={forgot ? 'Volver a iniciar sesión' : register ? 'Ya tengo cuenta' : 'Crear cuenta'} kind="tertiary" block onPress={busy ? undefined : () => mode(forgot || register ? 'login' : 'register')} />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}
