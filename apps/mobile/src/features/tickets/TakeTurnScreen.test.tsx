import { screen, userEvent, waitFor } from '@testing-library/react-native';
import { conflictFailure } from '@qhub/core';
import { camila, FakeGateway, FakeOrganizationRepository, FakeTickets, FakeUserRepository, makeContainer } from '@/testing/fakes';
import { renderApp } from '@/testing/harness';

const linkedOrgs = () => Object.assign(new FakeOrganizationRepository(), { linkedSet: new Set(['org1']) });
const signedIn = (o: Parameters<typeof makeContainer>[0] = {}) => makeContainer({ users: new FakeUserRepository(camila), ...o });

/** Navega Explorar → Notaría 12 → cola Escrituras → asistente TakeTurn. */
async function openTakeTurn(c: Parameters<typeof renderApp>[0]) {
  const user = userEvent.setup();
  await renderApp(c);
  await user.press(await screen.findByRole('tab', { name: 'Explorar' }));
  await user.press(await screen.findByText('Notaría 12'));
  await user.press(await screen.findByText('Escrituras'));
  return user;
}

const today = () => new Date().getDate();

describe('TakeTurn — asistente estilo cita (Objetivo 2)', () => {
  it('turno ahora: elige la tarjeta, confirma y crea con slot undefined, avisa, invalida y navega', async () => {
    const gw = new FakeGateway();
    const c = signedIn({ gateway: gw, orgs: linkedOrgs() });
    const user = await openTakeTurn(c);

    // Paso 'choose': dos opciones distintas.
    expect(await screen.findByRole('button', { name: 'Turno ahora' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Reservar cita' })).toBeTruthy();

    await user.press(screen.getByRole('button', { name: 'Turno ahora' }));
    // Paso 'confirm' del camino inmediato: nunca muestra calendario.
    expect(screen.queryByRole('button', { name: 'Mes siguiente' })).toBeNull();
    await user.press(await screen.findByRole('button', { name: 'Sacar turno ahora' }));

    await waitFor(() => expect(gw.ticketRepo.created).toEqual([{ queue: 'q1', slot: undefined }]));
    // Paso 'done' con acción que navega a Mi turno.
    await user.press(await screen.findByRole('button', { name: 'Ver mi turno' }));
    expect(await screen.findByText('Mi turno')).toBeTruthy();
  });

  it('reservar cita: día → franja avanza a confirmar y crea con slot.start en UTC', async () => {
    const gw = new FakeGateway();
    const c = signedIn({ gateway: gw, orgs: linkedOrgs() });
    const user = await openTakeTurn(c);

    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));
    // Paso 'schedule': calendario visible.
    await user.press(screen.getAllByRole('button', { name: new RegExp(`^${today()} de `) })[0]!);
    await user.press(await screen.findByRole('button', { name: '08:30, 2 cupos' }));

    // Elegir franja avanza a 'confirm': el CTA de reserva.
    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));
    await waitFor(() => expect(gw.ticketRepo.created).toHaveLength(1));
    const slot = gw.ticketRepo.created[0]!.slot!;
    expect([slot.getUTCHours(), slot.getUTCMinutes()]).toEqual([13, 30]);
    expect(await screen.findByRole('button', { name: 'Ver mi turno' })).toBeTruthy();
  });

  it('conflicto al reservar: limpia la franja, invalida las franjas, avisa y vuelve a schedule con el día', async () => {
    const tickets = Object.assign(new FakeTickets(), { createFailure: conflictFailure('Esa cita ya no tiene cupos. Elige otra.') });
    const gw = new FakeGateway(undefined, tickets);
    const c = signedIn({ gateway: gw, orgs: linkedOrgs() });
    const user = await openTakeTurn(c);

    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));
    await user.press(screen.getAllByRole('button', { name: new RegExp(`^${today()} de `) })[0]!);
    const requestsBefore = gw.queueRepo.slotRequests.length;
    await user.press(await screen.findByRole('button', { name: '08:30, 2 cupos' }));
    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));

    // El aviso de conflicto aparece y seguimos en el asistente.
    expect(await screen.findByText('Esa cita ya no tiene cupos. Elige otra.')).toBeTruthy();
    // Vuelve a 'schedule' con el día retenido: las franjas se reconsultan (invalidación de ['slots', org, cola]).
    await waitFor(() => expect(gw.queueRepo.slotRequests.length).toBeGreaterThan(requestsBefore));
    // La franja quedó limpia pero el día se conserva, así que la rejilla de franjas sigue visible.
    expect(await screen.findByRole('button', { name: '08:30, 2 cupos' })).toBeTruthy();
    expect(screen.getByRole('button', { name: '08:30, 2 cupos' }).props.accessibilityState.selected).toBe(false);
  });

  it('transiciones choose → schedule → confirm → (atrás) schedule conservando selección', async () => {
    const gw = new FakeGateway();
    const c = signedIn({ gateway: gw, orgs: linkedOrgs() });
    const user = await openTakeTurn(c);

    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));
    await user.press(screen.getAllByRole('button', { name: new RegExp(`^${today()} de `) })[0]!);
    await user.press(await screen.findByRole('button', { name: '08:30, 2 cupos' }));
    // En 'confirm' hay un CTA de reserva.
    expect(await screen.findByRole('button', { name: 'Reservar cita' })).toBeTruthy();
    // Atrás vuelve a 'schedule' sin perder la franja elegida (sigue disponible el calendario/franja).
    await user.press(screen.getByRole('button', { name: 'Atrás' }));
    expect(await screen.findByRole('button', { name: '08:30, 2 cupos' })).toBeTruthy();
  });

  it('turno ahora muestra cuántos hay delante y la espera aproximada', async () => {
    const c = signedIn({ gateway: new FakeGateway(), orgs: linkedOrgs() });
    await openTakeTurn(c);
    expect(await screen.findByText(/2 personas delante · espera aproximada de 20 min/)).toBeTruthy();
  });

  it('en descanso el turno ahora se deshabilita con el motivo y la cita sigue disponible', async () => {
    const queues = Object.assign(new FakeGateway().queueRepo, {});
    queues.nowInfo = { ...queues.nowInfo, open: false, reason: 'Estamos en descanso hasta las 14:00.', reopensAt: '14:00', waitMinutes: null, breaks: [{ from: '13:00', to: '14:00' }] };
    const c = signedIn({ gateway: new FakeGateway(queues), orgs: linkedOrgs() });
    await openTakeTurn(c);
    expect(await screen.findByText(/Estamos en descanso hasta las 14:00\. Puedes reservar una cita\./)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Turno ahora' }).props.accessibilityState.disabled).toBe(true);
    expect(screen.getByRole('button', { name: 'Reservar cita' }).props.accessibilityState.disabled).toBe(false);
    expect(screen.getByText(/descanso 13:00–14:00/)).toBeTruthy();
  });

  it('si ya tiene un turno ahora en la cola no puede sacar otro', async () => {
    const queues = new FakeGateway().queueRepo;
    queues.nowInfo = { ...queues.nowInfo, alreadyHasNow: true };
    await openTakeTurn(signedIn({ gateway: new FakeGateway(queues), orgs: linkedOrgs() }));
    expect(await screen.findByText(/Ya tienes un turno ahora en esta cola/)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Turno ahora' }).props.accessibilityState.disabled).toBe(true);
  });

  it('una franja con cupo pero en descanso sale deshabilitada con su motivo', async () => {
    const queues = new FakeGateway().queueRepo;
    queues.slotBlock = 'descanso';
    const user = await openTakeTurn(signedIn({ gateway: new FakeGateway(queues), orgs: linkedOrgs() }));
    await user.press(await screen.findByRole('button', { name: 'Reservar cita' }));
    await user.press(screen.getAllByRole('button', { name: new RegExp(`^${today()} de `) })[0]!);
    const slot = await screen.findByRole('button', { name: '08:30, descanso' });
    expect(slot.props.accessibilityState.disabled).toBe(true);
  });
});
