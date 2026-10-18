import { EMPTY_PROFILE, managedFields, validateProfile } from './profile';

describe('perfil móvil (dominio)', () => {
  it('los campos gestionados son identidad y contacto, no ubicación', () => {
    expect([...managedFields]).toEqual(['firstName', 'lastName', 'phone', 'jobTitle']);
    expect(managedFields).not.toContain('country');
    expect(managedFields).not.toContain('city');
  });
  it('reutiliza la validación compartida de @qhub/core', () => {
    expect(validateProfile({ ...EMPTY_PROFILE, firstName: 'Ana', lastName: 'Gómez' })).toEqual({});
    expect(validateProfile({ ...EMPTY_PROFILE, firstName: 'Ana', lastName: 'Gómez', city: 'Quito' }).country).toBeDefined();
  });
});
