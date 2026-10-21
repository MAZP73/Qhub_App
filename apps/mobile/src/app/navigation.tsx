import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import type { NavigatorScreenParams, NavigationProp } from '@react-navigation/native';
import { Pressable, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { IconName } from '@qhub/design';
import { Icon, Logo, Txt } from '@/shared/ui/kit';
import { AuthScreen } from '@/features/auth/AuthScreen';
import { ResetPasswordScreen } from '@/features/auth/ResetPasswordScreen';
import { HomeScreen } from '@/features/home/HomeScreen';
import { NotificationsScreen } from '@/features/notifications/NotificationsScreen';
import { ExploreScreen } from '@/features/organizations/ExploreScreen';
import { OrgScreen } from '@/features/organizations/OrgScreen';
import { ProfileScreen } from '@/features/profile/ProfileScreen';
import { TurnsScreen } from '@/features/tickets/TurnsScreen';
import { TakeTurnScreen } from '@/features/tickets/TakeTurnScreen';
import { useEffect } from 'react';
import { useAuth, useContainer, useRecovering } from './container';

export type TabParamList = { Home: undefined; Turns: undefined; Orgs: undefined; Notifications: undefined };
export type RootStackParamList = {
  Auth: undefined; ResetPassword: undefined; Tabs: NavigatorScreenParams<TabParamList> | undefined; Org: { organizationId: string }; TakeTurn: { organizationId: string; queueId: string }; Profile: undefined;
};
export type Nav = NavigationProp<RootStackParamList>;

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator<TabParamList>();

const TABS: ReadonlyArray<{ name: keyof TabParamList; label: string; icon: IconName }> = [
  { name: 'Home', label: 'Inicio', icon: 'dashboard' }, { name: 'Turns', label: 'Turnos', icon: 'ticket' },
  { name: 'Orgs', label: 'Organizaciones', icon: 'building' }, { name: 'Notifications', label: 'Avisos', icon: 'bell' },
];

/** Barra de pestañas inferior de 4 ítems (design: móvil). */
function TabBar({ state, navigation }: { state: { index: number; routes: Array<{ key: string; name: string }> }; navigation: { navigate: (n: string) => void } }) {
  return (
    <SafeAreaView edges={['bottom']} className="border-t border-border-subtle bg-layer-01">
      <View className="flex-row h-[56px]">
        {state.routes.map((r, i) => {
          const t = TABS.find((x) => x.name === r.name)!;
          const on = state.index === i;
          return (
            <Pressable key={r.key} accessibilityRole="tab" accessibilityLabel={t.label} accessibilityState={{ selected: on }} onPress={() => navigation.navigate(r.name)} className="flex-1 items-center justify-center gap-0.5">
              <Icon name={t.icon} size={20} color={on ? 'link' : 'textSecondary'} />
              <Txt variant="caption" weight={on ? 600 : 400} color={on ? 'link' : 'textSecondary'}>{t.label}</Txt>
            </Pressable>
          );
        })}
      </View>
    </SafeAreaView>
  );
}

function Tabs() {
  const { push } = useContainer();
  useEffect(() => { void push.enable(); }, [push]);   // con la sesión ya dentro de la app: pide permiso y registra el teléfono
  return (
    <Tab.Navigator tabBar={(p) => <TabBar {...(p as unknown as Parameters<typeof TabBar>[0])} />} screenOptions={{ headerShown: false }}>
      <Tab.Screen name="Home" component={HomeScreen} />
      <Tab.Screen name="Turns" component={TurnsScreen} />
      <Tab.Screen name="Orgs" component={ExploreScreen} />
      <Tab.Screen name="Notifications" component={NotificationsScreen} />
    </Tab.Navigator>
  );
}

function Splash() { return <View className="flex-1 items-center justify-center"><Logo height={32} /></View>; }

/** Según la sesión: cargando → logo, sin sesión → acceso, con sesión → la app. */
export function RootNavigator() {
  const auth = useAuth();
  const recovering = useRecovering();
  if (auth.status === 'loading') return <Splash />;
  const signedIn = auth.value !== null;
  return (
    <Stack.Navigator screenOptions={{ headerShown: false }}>
      {signedIn && recovering ? <Stack.Screen name="ResetPassword" component={ResetPasswordScreen} /> : signedIn ? (
        <>
          <Stack.Screen name="Tabs" component={Tabs} />
          <Stack.Screen name="Org" component={OrgScreen} />
          <Stack.Screen name="TakeTurn" component={TakeTurnScreen} />
          <Stack.Screen name="Profile" component={ProfileScreen} />
        </>
      ) : <Stack.Screen name="Auth" component={AuthScreen} />}
    </Stack.Navigator>
  );
}
