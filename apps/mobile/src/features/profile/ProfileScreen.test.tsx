import { screen, userEvent, waitFor } from '@testing-library/react-native';
import { EMPTY_PROFILE } from '@qhub/core';
import { camila, FakeProfileRepository, FakeUserRepository, makeContainer } from '@/testing/fakes';
import { renderApp } from '@/testing/harness';

const signedIn = (o: Parameters<typeof makeContainer>[0] = {}) => makeContainer({ users: new FakeUserRepository(camila), ...o });

describe('perfil móvil (pantalla)', () => {
  it('carga el perfil, edita la ciudad y guarda', async () => {
    const profiles = new FakeProfileRepository({ ...EMPTY_PROFILE, firstName: 'Camila', lastName: 'Ríos', country: 'CO', city: 'Bogotá', timeZone: 'America/Bogota' });
    const c = signedIn({ profiles });
    const user = userEvent.setup();
    await renderApp(c);
    await user.press(await screen.findByRole('button', { name: 'Perfil' }));
    expect(await screen.findByText('Datos personales')).toBeTruthy();
    // Editar la ciudad por el selector (permitido aunque sea gestionada).
    await user.press(await screen.findByRole('button', { name: 'Ciudad' }));
    await user.press(await screen.findByRole('button', { name: 'Cali' }));
    await user.press(await screen.findByRole('button', { name: 'Guardar' }));
    await waitFor(() => expect(profiles.calls).toContain('update:Camila:Cali'));
  });

  it('en cuenta gestionada, los campos gestionados ya completos no se editan', async () => {
    const profiles = new FakeProfileRepository({ ...EMPTY_PROFILE, firstName: 'Camila', lastName: 'Ríos', phone: '+57 3001112233', country: 'CO', city: 'Bogotá', timeZone: 'America/Bogota' }, true);
    const c = signedIn({ profiles });
    const user = userEvent.setup();
    await renderApp(c);
    await user.press(await screen.findByRole('button', { name: 'Perfil' }));
    expect(await screen.findByText('Tu administrador gestiona tu nombre, apellido, cargo y teléfono.')).toBeTruthy();
    const nombre = await screen.findByLabelText('Nombre');
    expect(nombre.props.editable).toBe(false);
  });
});
