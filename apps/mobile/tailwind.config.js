const plugin = require('tailwindcss/plugin');
const t = require('./tailwind.tokens.generated');

/** Los tokens del design system (generados de tokens.json) como tema de Tailwind. Nunca hex sueltos en componentes. */
module.exports = {
  content: ['./src/**/*.{ts,tsx}', '../../packages/design/src/**/*.ts'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: t.colors,
      borderRadius: { sm: `${t.radius.sm}px`, md: `${t.radius.md}px` },
      fontFamily: {
        'sans-300': ['IBMPlexSans_300Light'], 'sans-400': ['IBMPlexSans_400Regular'], 'sans-500': ['IBMPlexSans_500Medium'], 'sans-600': ['IBMPlexSans_600SemiBold'],
        'mono-400': ['IBMPlexMono_400Regular'], 'mono-500': ['IBMPlexMono_500Medium'],
      },
      height: { 'control-sm': `${t.size.controlSm}px`, 'control-md': `${t.size.controlMd}px`, 'control-lg': `${t.size.controlLg}px` },
      minHeight: { 'control-sm': `${t.size.controlSm}px`, 'control-md': `${t.size.controlMd}px`, 'control-lg': `${t.size.controlLg}px` },
      width: { 'control-md': `${t.size.controlMd}px` },
    },
  },
  plugins: [
    // Escala tipográfica del design system: tamaño, interlineado y espaciado de letras (la familia va aparte: font-sans-* / font-mono-*).
    plugin(({ addUtilities }) => addUtilities(Object.fromEntries(Object.entries(t.text).map(([name, s]) => [
      `.t-${name}`, { fontSize: `${s.fontSize}px`, lineHeight: `${s.lineHeight}px`, letterSpacing: `${s.letterSpacing}px` },
    ])))),
  ],
};
