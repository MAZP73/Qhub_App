import { useMemo } from 'react';
import { View } from 'react-native';
import { COUNTRIES } from '@qhub/core';
import { TextField } from '@/shared/ui/kit';
import { SelectField } from '@/shared/ui/SelectField';

const DIALS = [...new Set(COUNTRIES.map((c) => c.dial))].sort((a, b) => b.length - a.length);

/** Separa "+57 3001112233" en prefijo y número. */
export function splitPhone(v: string, fallbackDial: string): { dial: string; number: string } {
  const t = v.trim();
  const dial = DIALS.find((d) => t.startsWith(d));
  return dial ? { dial, number: t.slice(dial.length).trim() } : { dial: fallbackDial, number: t };
}

/** Teléfono: prefijo de país elegido de una lista + número (solo dígitos). */
export function PhoneField({ label = 'Teléfono', value, onChange, defaultCountry = 'EC', error, disabled }: {
  label?: string; value: string; onChange: (v: string) => void; defaultCountry?: string; error?: string | null; disabled?: boolean;
}) {
  const options = useMemo(() => COUNTRIES.map((c) => ({ value: `${c.code}|${c.dial}`, label: `${c.code} ${c.dial}`, hint: c.name })), []);
  const fallback = COUNTRIES.find((c) => c.code === defaultCountry)?.dial ?? '+593';
  const { dial, number } = splitPhone(value, fallback);
  const selected = options.find((o) => o.value.endsWith(`|${dial}`))?.value ?? '';
  const emit = (d: string, n: string) => onChange(n.trim() ? `${d} ${n.trim()}` : '');
  return (
    <View className="flex-row items-start gap-2">
      <View className="w-32"><SelectField label="Prefijo" value={selected} options={options} disabled={disabled} onValueChange={(v) => emit(v.split('|')[1] ?? fallback, number)} /></View>
      <View className="flex-1"><TextField label={label} value={number} editable={!disabled} keyboardType="phone-pad" error={error} placeholder="3001112233"
        onChangeText={(t) => emit(dial, t.replace(/[^0-9 ()-]/g, ''))} /></View>
    </View>
  );
}
