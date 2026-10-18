import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Text, View } from 'react-native';

/**
 * Última red de seguridad: si algo falla al dibujar una pantalla, se ve un mensaje claro y sin detalles técnicos.
 * El error real solo va a la consola de quien desarrolla.
 */
export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  override state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  override componentDidCatch(error: unknown, info: ErrorInfo) { console.error('[qhub] error de pantalla', error, info.componentStack); }
  override render() {
    if (!this.state.failed) return this.props.children;
    return (
      <View accessibilityRole="alert" className="flex-1 items-center justify-center bg-background p-8">
        <Text className="t-h3 text-text-primary">Algo salió mal</Text>
        <Text className="t-body-long mt-2 text-center text-text-secondary">No pudimos mostrar esta pantalla. Tus datos están a salvo. Cierra la app y vuelve a abrirla; si sigue pasando, inténtalo más tarde.</Text>
      </View>
    );
  }
}
