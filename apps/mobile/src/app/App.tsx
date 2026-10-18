import '../../global.css';
import { useEffect, useMemo } from 'react';
import { StatusBar } from 'expo-status-bar';
import { NavigationContainer, DarkTheme, DefaultTheme } from '@react-navigation/native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { Text } from 'react-native';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
// Solo los pesos del design system (300/400/500/600 y mono 400/500): importar el índice empaquetaría todos.
import { IBMPlexSans_300Light } from '@expo-google-fonts/ibm-plex-sans/300Light';
import { IBMPlexSans_400Regular } from '@expo-google-fonts/ibm-plex-sans/400Regular';
import { IBMPlexSans_500Medium } from '@expo-google-fonts/ibm-plex-sans/500Medium';
import { IBMPlexSans_600SemiBold } from '@expo-google-fonts/ibm-plex-sans/600SemiBold';
import { IBMPlexMono_400Regular } from '@expo-google-fonts/ibm-plex-mono/400Regular';
import { IBMPlexMono_500Medium } from '@expo-google-fonts/ibm-plex-mono/500Medium';
import { ThemeProvider, useTheme } from '@/shared/ui/theme';
import { ToastProvider } from '@/shared/ui/kit';
import { buildContainer, ContainerProvider, type Container } from './container';
import { parseEnv } from './env';
import { RootNavigator } from './navigation';
import { ErrorBoundary } from '@/shared/ui/ErrorBoundary';

void SplashScreen.preventAutoHideAsync();

function Themed() {
  const { c, scheme } = useTheme();
  const base = scheme === 'dark' ? DarkTheme : DefaultTheme;
  const theme = useMemo(() => ({ ...base, colors: { ...base.colors, background: c.background, card: c.layer01, text: c.textPrimary, border: c.borderSubtle, primary: c.interactive } }), [base, c]);
  return (
    <NavigationContainer theme={theme}>
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
      <RootNavigator />
    </NavigationContainer>
  );
}

export default function App() {
  const [fontsLoaded] = useFonts({ IBMPlexSans_300Light, IBMPlexSans_400Regular, IBMPlexSans_500Medium, IBMPlexSans_600SemiBold, IBMPlexMono_400Regular, IBMPlexMono_500Medium });
  const boot = useMemo<{ container: Container } | { error: string }>(() => {
    try {
      return { container: buildContainer(parseEnv({
        EXPO_PUBLIC_APP_ENV: process.env.EXPO_PUBLIC_APP_ENV,
        EXPO_PUBLIC_SUPABASE_URL: process.env.EXPO_PUBLIC_SUPABASE_URL,
        EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      })) };
    } catch (e) { return { error: (e as Error).message }; }
  }, []);
  const client = useMemo(() => new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 5_000 } } }), []);

  useEffect(() => { if ('container' in boot) boot.container.session.start(); return () => { if ('container' in boot) boot.container.session.dispose(); }; }, [boot]);
  useEffect(() => { if (fontsLoaded) void SplashScreen.hideAsync(); }, [fontsLoaded]);

  if (!fontsLoaded) return null;
  // El detalle (p. ej. qué variable falta) es para quien desarrolla: va a la consola, no a la pantalla.
  if ('error' in boot) { console.error('[qhub] no se pudo iniciar', boot.error); return <Text style={{ padding: 32 }}>No pudimos iniciar la aplicación. Inténtalo de nuevo en un momento.</Text>; }
  return (
    <ErrorBoundary><SafeAreaProvider>
      <ContainerProvider value={boot.container}>
        <QueryClientProvider client={client}>
          <ThemeProvider><ToastProvider><Themed /></ToastProvider></ThemeProvider>
        </QueryClientProvider>
      </ContainerProvider>
    </SafeAreaProvider></ErrorBoundary>
  );
}
