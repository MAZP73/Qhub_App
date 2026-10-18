import { useMemo } from 'react';
import { View } from 'react-native';
import { citiesOf, COUNTRIES, countryByAny, timeZonesOf } from '@qhub/core';
import { SelectField } from '@/shared/ui/SelectField';

export interface Location { country: string; city: string; timeZone: string }

/** País → ciudad → zona horaria, por selección. Misma lógica que el web, UI con el kit móvil. */
export function LocationFields({ value, onChange, errors = {} }: {
  value: Location; onChange: (next: Location) => void; errors?: Partial<Record<keyof Location, string | null>>;
}) {
  const country = countryByAny(value.country);
  const countryOptions = useMemo(() => COUNTRIES.map((c) => ({ value: c.code, label: c.name })), []);
  const cities = useMemo(() => {
    const list = [...citiesOf(value.country)];
    if (value.city && !list.includes(value.city)) list.unshift(value.city);   // dato antiguo escrito a mano
    return list.map((c) => ({ value: c, label: c }));
  }, [value.country, value.city]);
  const zones = useMemo(() => {
    const list = [...timeZonesOf(value.country)];
    if (value.timeZone && !list.some((z) => z.value === value.timeZone)) list.unshift({ value: value.timeZone, label: value.timeZone });
    return list;
  }, [value.country, value.timeZone]);

  return (
    <View className="gap-4">
      <SelectField label="País" value={country?.code ?? ''} options={countryOptions} error={errors.country}
        onValueChange={(code) => { const c = countryByAny(code); onChange({ country: c ? c.code : '', city: '', timeZone: c?.timeZones[0] ?? value.timeZone }); }} />
      <SelectField label="Ciudad" value={value.city} options={cities} disabled={!country} error={errors.city}
        placeholder={country ? 'Elegir' : 'Elige primero el país'} onValueChange={(city) => onChange({ ...value, city })} />
      <SelectField label="Zona horaria" value={value.timeZone} options={zones} searchable={zones.length > 6}
        onValueChange={(timeZone) => onChange({ ...value, timeZone })} />
    </View>
  );
}
