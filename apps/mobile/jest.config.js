module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/src/testing/setup.ts'],
  moduleNameMapper: { '^@/(.*)$': '<rootDir>/src/$1' },
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|react-native-svg|nativewind|react-native-css-interop|react-native-screens|react-native-safe-area-context|@qhub/.*))',
  ],
  forceExit: true,
  // Las pruebas de interacción con userEvent (ProfileScreen, TakeTurnScreen, app-flow) tardan
  // bastante más que el default de 5s bajo carga paralela; se sube el límite para que no sean flaky.
  testTimeout: 30000,
  testMatch: ['<rootDir>/src/**/*.test.ts?(x)'],
};
