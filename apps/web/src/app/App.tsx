import { useEffect, useState } from 'react';
import { AppRoutes } from './routing';
import { applyPreferences, loadPreferences } from '@/features/preferences/domain/preferences';

export { applyTheme, loadTheme, type ThemeMode } from '@/features/preferences/domain/preferences';

export function App() {
  const [ready, setReady] = useState(false);
  useEffect(() => { applyPreferences(loadPreferences()); setReady(true); }, []);
  return ready ? <AppRoutes /> : null;
}
