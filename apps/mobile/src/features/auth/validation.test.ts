import { validateEmail, validatePassword } from '@qhub/core';

describe('validaciones', () => {
  it('correo y contraseña', () => {
    expect(validateEmail('a@b.co')).toBeNull(); expect(validateEmail('a@b')).not.toBeNull();
    expect(validatePassword('1234567', { mixed: false })).not.toBeNull(); expect(validatePassword('12345678', { mixed: false })).toBeNull();
  });
});
