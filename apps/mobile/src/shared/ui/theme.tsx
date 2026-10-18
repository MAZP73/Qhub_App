import { colorScheme } from 'nativewind';
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useColorScheme } from 'react-native';
import { colors, type ColorTokens, type ThemeName } from '@qhub/design';

export type ThemeMode = 'system' | 'light' | 'dark';
interface ThemeValue { scheme: ThemeName; c: ColorTokens; mode: ThemeMode; setMode: (m: ThemeMode) => void }
const Ctx = createContext<ThemeValue>({ scheme: 'light', c: colors.light, mode: 'system', setMode: () => {} });

/**
 * El color de los componentes sale de clases de Tailwind (variables CSS de los tokens, claro/oscuro automático).
 * `c` solo se usa donde un color debe ser un valor, p. ej. el relleno de un ícono SVG.
 */
export function ThemeProvider({ children, initialMode = 'system' }: { children: ReactNode; initialMode?: ThemeMode }) {
  const system = useColorScheme();
  const [mode, setMode] = useState<ThemeMode>(initialMode);
  const scheme: ThemeName = mode === 'system' ? (system === 'dark' ? 'dark' : 'light') : mode;
  useEffect(() => { colorScheme.set(mode); }, [mode]);
  const value = useMemo(() => ({ scheme, c: colors[scheme], mode, setMode }), [scheme, mode]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
export const useTheme = () => useContext(Ctx);
