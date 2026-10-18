import { NavigationContainer } from '@react-navigation/native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, userEvent, waitFor } from '@testing-library/react-native';
import type { ReactElement } from 'react';
import { ToastProvider } from '@/shared/ui/kit';
import { ThemeProvider } from '@/shared/ui/theme';
import { ContainerProvider } from '@/app/container';
import { RootNavigator } from '@/app/navigation';
import type { TestContainer } from './fakes';

const tick = () => new Promise<void>((r) => setTimeout(() => r(), 0));

export function wrap(ui: ReactElement, c: TestContainer) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0, staleTime: 0 } } });
  return (
    <ContainerProvider value={c}><QueryClientProvider client={client}><ThemeProvider><ToastProvider><NavigationContainer>{ui}</NavigationContainer></ToastProvider></ThemeProvider></QueryClientProvider></ContainerProvider>
  );
}

/** Renderiza la app completa con fakes y la sesión ya resuelta. */
export async function renderApp(c: TestContainer) {
  c.session.start();
  const utils = render(wrap(<RootNavigator />, c));
  await waitFor(() => expect(c.session.getSnapshot().status).toBe('ready'));
  return utils;
}

export const settle = () => act(async () => { await tick(); await tick(); });

export { screen, userEvent, waitFor };
