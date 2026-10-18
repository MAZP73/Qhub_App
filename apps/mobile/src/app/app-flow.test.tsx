import { screen, userEvent, waitFor } from '@testing-library/react-native';
import { conflictFailure, forbiddenFailure, networkFailure, unauthorizedFailure } from '@qhub/core';
import type { AppNotification } from '@qhub/api-client';
import { camila, entry, FakeGateway, FakeEditRequests, FakeHistoryRepository, FakeNotifications, FakeOrganizationRepository, FakeTickets, FakeUserRepository, makeContainer, ticket } from '@/testing/fakes';
import { renderApp } from '@/testing/harness';

const signedIn = (o: Parameters<typeof makeContainer>[0] = {}) => makeContainer({ users: new FakeUserRepository(camila), ...o });

const linkedOrgs = () => Object.assign(new FakeOrganizationRepository(), { linkedSet: new Set(['org1']) });

function setup() {
  const user = userEvent.setup();
  return {
    user,
    press: async (label: string | RegExp, index = 0) => user.press((await screen.findAllByRole('button', { name: label }))[index]!),
    tab: async (name: string) => user.press(await screen.findByRole('tab', { name })),
    text: async (t: string) => user.press(await screen.findByText(t)),
    type: async (label: string, value: string) => user.type(await screen.findByLabelText(label), value),
  };
}

describe('acceso', () => {
  it('sin sesión muestra el acceso y valida', async () => {
    const c = makeContainer();
    const { press, type } = setup();
    await renderApp(c);
    expect(screen.getByText('Tu turno, sin filas.')).toBeTruthy();
    await press('Continuar');
    expect(await screen.findByText('Escribe un correo válido.')).toBeTruthy();
    expect(c.fakes.users.calls).toEqual([]);
  });

  it('error de credenciales', async () => {
    const users = new FakeUserRepository(); users.signInFailure = unauthorizedFailure('Correo o contraseña incorrectos.');
    const { press, type } = setup();
    await renderApp(makeContainer({ users }));
    await type('Correo', 'camila@x.co'); await type('Contraseña', 'secreto123');await press('Continuar');
    expect(await screen.findByText('Correo o contraseña incorrectos.')).toBeTruthy();
  });

  it('iniciar sesión lleva a "Mi turno" vacío', async () => {
    const { press, type } = setup();
    await renderApp(makeContainer());
    await type('Correo', 'camila@x.co'); await type('Contraseña', 'secreto123');await press('Continuar');
    expect(await screen.findByText('Aún no estás vinculado a ninguna organización')).toBeTruthy();
  });

  it('crear cuenta avisa que hay que confirmar el correo', async () => {
    const c = makeContainer();
    const { press, type } = setup();
    await renderApp(c);
    await press('Crear cuenta');
    await type('Nombre', 'Camila'); await type('Apellido', 'Ríos'); await type('Correo', 'camila@x.co'); await type('Contraseña', 'secreto123');await press('Crear cuenta', 0);
    expect(await screen.findByText(/confirmar tu cuenta/)).toBeTruthy();
    expect(c.fakes.users.calls).toEqual(['signUp:camila@x.co']);
  });
});

describe('con sesión', () => {
  it('explorar lista organizaciones y busca', async () => {
    const c = signedIn();
    const { tab, user } = setup();
    await renderApp(c);
    await tab('Explorar');
    expect(await screen.findByText('Notaría 12')).toBeTruthy();
    expect(screen.getByText('Banco Cooperativo')).toBeTruthy();
    await user.type(screen.getByLabelText('Buscar'), 'banco');
    // Mientras llega el resultado la lista puede estar en carga (ninguna visible): se espera al estado final completo.
    await waitFor(() => { expect(screen.queryByText('Notaría 12')).toBeNull(); expect(screen.getByText('Banco Cooperativo')).toBeTruthy(); }, { timeout: 5000 });
    expect(c.fakes.orgs.searches).toEqual(expect.arrayContaining(['', 'banco']));
  });

  it('sin resultados', async () => {
    const { tab } = setup();
    await renderApp(signedIn({ orgs: new FakeOrganizationRepository([]) }));
    await tab('Explorar');
    expect(await screen.findByText('Aún no hay organizaciones')).toBeTruthy();
  });

  it('error de red con reintento', async () => {
    const orgs = new FakeOrganizationRepository(); orgs.searchFailure = networkFailure();
    const { tab } = setup();
    await renderApp(signedIn({ orgs }));
    await tab('Explorar');
    expect(await screen.findByText('No pudimos cargar esto')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeTruthy();
  });

  it('sacar un turno ahora: organización → cola → turno', async () => {
    const gw = new FakeGateway();
    const { tab, text, press } = setup();
    await renderApp(signedIn({ gateway: gw, orgs: linkedOrgs() }));
    await tab('Explorar');
    await screen.findByText('Notaría 12');
    await text('Notaría 12');
    expect(await screen.findByText('Colas abiertas')).toBeTruthy();
    expect(await screen.findByText('Escrituras')).toBeTruthy();
    expect(screen.queryByText('Archivo')).toBeNull(); // las archivadas no se ofrecen
    expect(await screen.findByText(/5 en espera · 1 atendiendo/)).toBeTruthy();
    await text('Escrituras');
    await screen.findByRole('button', { name: 'Sacar turno ahora' });
    await press('Sacar turno ahora');
    await waitFor(() => expect(gw.ticketRepo.created).toEqual([{ queue: 'q1', slot: undefined }]));
  });

  it('reservar una franja: llena deshabilitada, la elegida viaja en UTC y se muestra en hora de la cola', async () => {
    const gw = new FakeGateway();
    const { tab, text, press, user } = setup();
    await renderApp(signedIn({ gateway: gw, orgs: linkedOrgs() }));
    await tab('Explorar');
    await user.press(await screen.findByText('Notaría 12'));
    await user.press(await screen.findByText('Escrituras'));
    await user.press(await screen.findByRole('button', { name: 'Reservar franja' }));
    expect(await screen.findByText('Elige día y franja')).toBeTruthy();

    await user.press(screen.getAllByRole('button', { name: new RegExp(`^${new Date().getDate()} de `) })[0]!);
    expect(await screen.findByText('Llena')).toBeTruthy();
    expect(screen.getByText('08:30')).toBeTruthy(); // 13:30Z con apertura 08:00 → UTC-5, no la zona del dispositivo
    expect(screen.getByRole('button', { name: '08:00, llena' }).props.accessibilityState.disabled).toBe(true);

    await user.press(screen.getByRole('button', { name: '08:30, 2 cupos' }));
    await user.press(await screen.findByRole('button', { name: /^Reservar \S+ \d+, 08:30/ }));
    await waitFor(() => expect(gw.ticketRepo.created).toHaveLength(1));
    const slot = gw.ticketRepo.created[0]!.slot!;
    expect([slot.getUTCHours(), slot.getUTCMinutes()]).toEqual([13, 30]);
    void press;
  });

  it('franja llena (409) se explica y se puede reintentar', async () => {
    const gw = new FakeGateway(undefined, Object.assign(new FakeTickets(), { createFailure: conflictFailure('Esa franja ya no tiene cupos. Elige otra.') }));
    const { tab, user } = setup();
    await renderApp(signedIn({ gateway: gw, orgs: linkedOrgs() }));
    await tab('Explorar');
    await user.press(await screen.findByText('Notaría 12'));
    await user.press(await screen.findByText('Escrituras'));
    await user.press(await screen.findByRole('button', { name: 'Sacar turno ahora' }));
    expect(await screen.findByText('Esa franja ya no tiene cupos. Elige otra.')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Sacar turno ahora' })).toBeTruthy(); // sigue en la pantalla
  });

  it('buscar por ID encuentra la organización y se puede vincular desde la lista', async () => {
    const orgs = new FakeOrganizationRepository();
    const { tab, user, press } = setup();
    await renderApp(signedIn({ orgs }));
    await tab('Explorar');
    expect(await screen.findByText('ID QH-N12ABC')).toBeTruthy();
    await user.type(screen.getByLabelText('Buscar'), 'qh-n12abc');
    await waitFor(() => { expect(screen.queryByText('Banco Cooperativo')).toBeNull(); expect(screen.getByText('Notaría 12')).toBeTruthy(); }, { timeout: 5000 });
    await press('Vincular');
    await waitFor(() => expect(orgs.linkedSet.has('org1')).toBe(true));
    expect(await screen.findByText('Vinculada')).toBeTruthy();
  });

  it('sin vincular no se ven las colas: se pide vincular; ya vinculado aparecen', async () => {
    const orgs = new FakeOrganizationRepository();
    const { tab, text, press } = setup();
    await renderApp(signedIn({ orgs, gateway: new FakeGateway() }));
    await tab('Explorar');
    await text('Notaría 12');
    expect(await screen.findByText('Vincúlate para continuar')).toBeTruthy();
    expect(screen.queryByText('Colas abiertas')).toBeNull();
    expect(screen.queryByText('Escrituras')).toBeNull();
    await press('Vincular');
    expect(await screen.findByText('Colas abiertas')).toBeTruthy();
    expect(await screen.findByText('Escrituras')).toBeTruthy();
  });

  it('desvincular pide confirmación y vuelve a ocultar las colas; se puede estar vinculado a varias', async () => {
    const orgs = Object.assign(new FakeOrganizationRepository(), { linkedSet: new Set(['org1', 'org2']) });
    const { text, press } = setup();
    await renderApp(signedIn({ orgs, gateway: new FakeGateway() }));
    // Mi turno lista las dos organizaciones vinculadas
    expect(await screen.findByText('Mis organizaciones')).toBeTruthy();
    expect(screen.getByText('Banco Cooperativo')).toBeTruthy();
    await text('Notaría 12');
    await screen.findByText('Colas abiertas');
    await press('Desvincular');
    expect(await screen.findByText(/Dejarás de ver las colas de Notaría 12/)).toBeTruthy();
    expect(orgs.linkedSet.has('org1')).toBe(true);
    await press('Desvincular', 1);
    await waitFor(() => expect(orgs.linkedSet.has('org1')).toBe(false));
    expect(orgs.linkedSet.has('org2')).toBe(true);
    expect(await screen.findByText('Vincúlate para continuar')).toBeTruthy();
  });

  it('sin organizaciones vinculadas Mi turno invita a buscar la tuya', async () => {
    await renderApp(signedIn());
    expect(await screen.findByText('Aún no estás vinculado a ninguna organización')).toBeTruthy();
  });

  it('un bloqueo se explica al intentar vincularse', async () => {
    const orgs = new FakeOrganizationRepository(); orgs.linkFailure = forbiddenFailure('No puedes vincularte a esta organización.');
    const { tab, press } = setup();
    await renderApp(signedIn({ orgs }));
    await tab('Explorar');
    await screen.findByText('Notaría 12');
    await press('Vincular');
    expect(await screen.findByText('No puedes vincularte a esta organización.')).toBeTruthy();
  });

  it('una organización pide permiso para editar mis datos: se ve en Avisos y se aprueba o rechaza', async () => {
    const editRequests = new FakeEditRequests([{ id: 'r1', organization: 'Notaría 12', reason: 'Corregir apellido', expiresAt: new Date(Date.now() + 5 * 3600000) }]);
    const { tab, press } = setup();
    await renderApp(signedIn({ editRequests }));
    await tab('Avisos');
    expect(await screen.findByText('Notaría 12 quiere cambiar tus datos')).toBeTruthy();
    expect(screen.getByText('Motivo: “Corregir apellido”')).toBeTruthy();
    expect(screen.getByText('Vence en 5 h')).toBeTruthy();
    await press('Aprobar');
    await waitFor(() => expect(editRequests.calls).toEqual(['approve:r1']));
    await waitFor(() => expect(screen.queryByText('Notaría 12 quiere cambiar tus datos')).toBeNull());
  });

  it('Mi turno muestra posición, estimado y permite cancelar con confirmación', async () => {
    const gw = new FakeGateway();
    gw.ticketRepo.stored.set('t1', ticket('t1', 7, 'en_espera', { position: 4 }));
    const { press, type } = setup();
    await renderApp(signedIn({ gateway: gw, history: new FakeHistoryRepository([entry('t1', 7, 'en_espera')]) }));
    expect(await screen.findByText('E-007')).toBeTruthy();
    expect(screen.getByText('Personas delante')).toBeTruthy();
    expect(screen.getByText('3')).toBeTruthy();
    expect(screen.getByText('~20 min')).toBeTruthy();

    await press('Cancelar');
    expect(await screen.findByText('Se libera tu lugar en Escrituras. Esta acción no se puede deshacer.')).toBeTruthy();
    await press('Volver');
    expect(gw.ticketRepo.calls).toEqual([]);

    await press('Cancelar');
    await press('Cancelar turno', 0);
    await waitFor(() => expect(gw.ticketRepo.calls).toEqual(['cancel:t1']));
  });

  it('posponer', async () => {
    const gw = new FakeGateway();
    gw.ticketRepo.stored.set('t1', ticket('t1', 7, 'en_espera', { position: 2 }));
    const { press, type } = setup();
    await renderApp(signedIn({ gateway: gw, history: new FakeHistoryRepository([entry('t1', 7, 'en_espera')]) }));
    await screen.findByText('E-007');
    await press('Posponer');
    await waitFor(() => expect(gw.ticketRepo.calls).toEqual(['postpone:t1']));
  });

  it('cuando lo atienden se avisa "Es tu turno"', async () => {
    const gw = new FakeGateway();
    gw.ticketRepo.stored.set('t1', ticket('t1', 7, 'atendiendo', { position: 0 }));
    await renderApp(signedIn({ gateway: gw, history: new FakeHistoryRepository([entry('t1', 7, 'en_espera')]) }));
    expect(await screen.findByText('Es tu turno')).toBeTruthy();
    expect(screen.getAllByText('Atendiendo').length).toBeGreaterThan(0);
  });

  it('avisos: sin leer, marcar como leído', async () => {
    const notes = new FakeNotifications([
      { id: 'n1', userId: 'u1', ticketId: 't1', message: 'Tu turno E-007 está siendo atendido', read: false, createdAt: new Date(), kind: 'turno_llamado' },
      { id: 'n2', userId: 'u1', ticketId: 't1', message: 'Recordatorio: tu turno empieza en 45 minutos', read: true, createdAt: new Date(Date.now() - 3_600_000), kind: 'recordatorio' },
    ] satisfies AppNotification[]);
    const gw = new FakeGateway(undefined, undefined, notes);
    const { tab, text } = setup();
    await renderApp(signedIn({ gateway: gw, history: new FakeHistoryRepository([entry('t1', 7, 'finalizado')]) }));
    await tab('Avisos');
    expect(await screen.findByText('Sin leer (1)')).toBeTruthy();
    expect(screen.getByText('Hoy')).toBeTruthy();
    await text('Sin leer (1)');
    expect(screen.getByText('Tu turno E-007 está siendo atendido')).toBeTruthy();
    expect(screen.queryByText(/Recordatorio/)).toBeNull();
    await text('Tu turno E-007 está siendo atendido');
    await waitFor(() => expect(notes.read).toEqual(['n1']));
    expect(await screen.findByText('Estás al día')).toBeTruthy();
  });

  it('historial agrupa por día y muestra el estado con palabra', async () => {
    const { tab } = setup();
    await renderApp(signedIn({ history: new FakeHistoryRepository([entry('a', 5, 'finalizado'), entry('b', 4, 'no_show', { createdAt: new Date(Date.now() - 864e5) })]) }));
    await tab('Historial');
    expect(await screen.findByText('Finalizado')).toBeTruthy();
    expect(screen.getByText('Hoy')).toBeTruthy();
    expect(screen.getByText('Ayer')).toBeTruthy();
    expect(screen.getByText('No-show')).toBeTruthy();
  });

  it('cerrar sesión desde el perfil vuelve al acceso', async () => {
    const c = signedIn();
    const { press, type } = setup();
    await renderApp(c);
    await press('Perfil');
    expect(await screen.findByText('camila@x.co')).toBeTruthy();
    await press('Cerrar sesión');
    await press('Cerrar sesión', 1);
    await waitFor(() => expect(c.fakes.users.calls).toEqual(['signOut']));
    expect(await screen.findByText('Tu turno, sin filas.')).toBeTruthy();
  });
});
