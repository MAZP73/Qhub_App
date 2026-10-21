import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, Text, TextInput, View, type TextInputProps } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { SvgXml } from 'react-native-svg';
import { bgClass, icons, logos, STATUS_ICON, text, textClass, type ColorName, type IconName, type LogoName } from '@qhub/design';
import { TICKET_STATUS_LABEL, type TicketStatus } from '@qhub/api-client';
import { formatTurnNumber } from '@qhub/core';
import { useTheme } from './theme';

/** Una clase por familia/peso (Tailwind solo genera lo que ve escrito). */
const FAMILY = {
  sans: { 300: 'font-sans-300', 400: 'font-sans-400', 500: 'font-sans-500', 600: 'font-sans-600' },
  mono: { 400: 'font-mono-400', 500: 'font-mono-500' },
} as const;
/** Una clase por estilo de la escala tipográfica del design system. */
const SCALE: Record<keyof typeof text, string> = {
  display: 't-display', h1: 't-h1', h2: 't-h2', h3: 't-h3', h4: 't-h4', body: 't-body', bodyLong: 't-body-long', label: 't-label', caption: 't-caption',
  turnXl: 't-turn-xl', turn: 't-turn', code: 't-code', codeSm: 't-code-sm',
};
export type Variant = keyof typeof text;

export const cx = (...c: Array<string | false | null | undefined>): string => c.filter(Boolean).join(' ');

/** Texto con la tipografía del design system. `color` es un token, nunca un hex. */
export function Txt({ variant = 'body', color = 'textPrimary', weight, className, children, ...rest }: {
  variant?: Variant; color?: ColorName; weight?: 400 | 500 | 600; className?: string; children?: ReactNode; numberOfLines?: number; accessibilityRole?: 'header' | 'text'; testID?: string;
}) {
  const t = text[variant];
  const w = weight ?? t.fontWeight;
  const family = t.family === 'mono' ? FAMILY.mono[w === 500 ? 500 : 400] : FAMILY.sans[(w === 300 || w === 400 || w === 500 || w === 600 ? w : 400) as 300 | 400 | 500 | 600];
  return <Text {...rest} className={cx(SCALE[variant], family, textClass[color], className)}>{children}</Text>;
}

export function Icon({ name, size: s = 16, color = 'textPrimary', label }: { name: IconName; size?: number; color?: ColorName; label?: string }) {
  const { c } = useTheme();
  const xml = icons[name].replace('<svg ', `<svg width="${s}" height="${s}" `);
  return <View accessible={!!label} accessibilityLabel={label} accessibilityRole={label ? 'image' : undefined} importantForAccessibility={label ? 'yes' : 'no-hide-descendants'}><SvgXml xml={xml} color={c[color]} width={s} height={s} /></View>;
}

export function Logo({ name = 'qhub-horizontal', height = 24 }: { name?: LogoName; height?: number }) {
  const m = /viewBox="0 0 (\d+) (\d+)"/.exec(logos[name]);
  const ratio = m ? Number(m[1]) / Number(m[2]) : 1;
  return <View accessibilityLabel="Qhub" accessibilityRole="image"><SvgXml xml={logos[name]} height={height} width={height * ratio} /></View>;
}

export type ButtonKind = 'primary' | 'secondary' | 'tertiary' | 'ghost' | 'danger' | 'accent';
const BTN: Record<ButtonKind, { box: string; fg: ColorName }> = {
  primary: { box: 'bg-interactive', fg: 'textOnColor' },
  secondary: { box: 'bg-layer-02 border border-border-strong', fg: 'textPrimary' },
  tertiary: { box: 'bg-transparent border border-link', fg: 'link' },
  ghost: { box: 'bg-transparent', fg: 'link' },
  danger: { box: 'bg-support-error', fg: 'textOnColor' },
  accent: { box: 'bg-brand-mint', fg: 'textOnAccent' },
};

export function Button({ label, onPress, kind = 'primary', big = true, icon, block, loading, disabled, testID }: {
  label: string; onPress?: () => void; kind?: ButtonKind; big?: boolean; icon?: IconName; block?: boolean; loading?: boolean; disabled?: boolean; testID?: string;
}) {
  const off = disabled || loading || !onPress;
  const k = BTN[kind];
  return (
    <Pressable testID={testID} accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled: off, busy: !!loading }} disabled={off} onPress={onPress}
      className={cx('flex-row items-center justify-center gap-2 rounded-sm px-4 active:opacity-80', big ? 'min-h-control-lg' : 'min-h-control-md', off ? 'bg-layer-selected' : k.box, block ? 'self-stretch' : 'self-start')}>
      <Txt color={off ? 'textDisabled' : k.fg}>{label}</Txt>
      {loading ? <ActivityIndicator /> : icon ? <Icon name={icon} color={off ? 'textDisabled' : k.fg} /> : null}
    </Pressable>
  );
}

export function IconButton({ icon, label, onPress }: { icon: IconName; label: string; onPress?: () => void }) {
  return <Pressable accessibilityRole="button" accessibilityLabel={label} onPress={onPress} className="h-control-md w-control-md items-center justify-center"><Icon name={icon} size={20} /></Pressable>;
}

export function TextField({ label, error, helper, secure, ...rest }: { label: string; error?: string | null; helper?: string; secure?: boolean } & Omit<TextInputProps, 'secureTextEntry'>) {
  const [focus, setFocus] = useState(false);
  const [shown, setShown] = useState(false);
  const { c } = useTheme();
  return (
    <View className="gap-1">
      <Txt variant="label" color="textSecondary">{label}</Txt>
      <View className={cx('flex-row items-center bg-field', error ? 'border-2 border-support-error' : focus ? 'border-2 border-focus' : 'border-b border-border-strong')}>
        <TextInput {...rest} accessibilityLabel={label} secureTextEntry={secure && !shown} onFocus={() => setFocus(true)} onBlur={() => setFocus(false)} placeholderTextColor={c.textPlaceholder} cursorColor={c.interactive}
          className="min-h-control-lg flex-1 px-4 font-sans-400 text-text-primary" />
        {secure && <Pressable accessibilityRole="button" accessibilityLabel={shown ? 'Ocultar contraseña' : 'Mostrar contraseña'} onPress={() => setShown((v) => !v)} className="px-3"><Txt variant="label" color="link">{shown ? 'Ocultar' : 'Mostrar'}</Txt></Pressable>}
        {error ? <View className="pr-3"><Icon name="warning" color="supportError" /></View> : null}
      </View>
      {(error || helper) ? <Txt variant="caption" color={error ? 'supportError' : 'textSecondary'}>{error ?? helper}</Txt> : null}
    </View>
  );
}

export type NoticeKind = 'info' | 'success' | 'warning' | 'error';
const NOTICE: Record<NoticeKind, { icon: IconName; color: ColorName; border: string }> = {
  info: { icon: 'info', color: 'supportInfo', border: 'border-l-support-info' }, success: { icon: 'check', color: 'supportSuccess', border: 'border-l-support-success' },
  warning: { icon: 'warning', color: 'supportWarning', border: 'border-l-support-warning' }, error: { icon: 'error', color: 'supportError', border: 'border-l-support-error' },
};
export function Notice({ kind = 'info', title, message }: { kind?: NoticeKind; title: string; message?: string }) {
  const n = NOTICE[kind];
  return (
    <View accessibilityLiveRegion="polite" accessibilityRole={kind === 'error' ? 'alert' : undefined} className={cx('flex-row gap-3 border border-l-[3px] border-border-subtle bg-layer-01 p-3', n.border)}>
      <Icon name={n.icon} size={20} color={n.color} />
      <View className="flex-1"><Txt weight={600}>{title}</Txt>{message ? <Txt color="textSecondary">{message}</Txt> : null}</View>
    </View>
  );
}

const STATUS_BG: Record<TicketStatus, string> = { en_espera: 'bg-state-waiting', atendiendo: 'bg-state-serving', finalizado: 'bg-state-done', cancelado: 'bg-state-cancelled', no_show: 'bg-state-noshow' };
/** Estado del turno: color + ícono + palabra, nunca solo color. */
export function TurnBadge({ status }: { status: TicketStatus }) {
  return (
    <View accessibilityLabel={`Estado: ${TICKET_STATUS_LABEL[status]}`} className={cx('flex-row items-center gap-1 self-start rounded-sm px-2 py-[3px]', STATUS_BG[status])}>
      <Icon name={STATUS_ICON[status]} size={14} color="textOnAccent" />
      <Txt variant="label" color="textOnAccent">{TICKET_STATUS_LABEL[status]}</Txt>
    </View>
  );
}

export const TurnNumber = ({ number, prefix = 'A', xl, color = 'textPrimary' }: { number: number; prefix?: string; xl?: boolean; color?: ColorName }) => <Txt variant={xl ? 'turnXl' : 'turn'} color={color}>{formatTurnNumber(number, prefix)}</Txt>;

export function EmptyState({ title, message, action }: { title: string; message?: string; action?: ReactNode }) {
  return (
    <View className="flex-1 items-center justify-center gap-2 p-8">
      <Logo name="qhub-simbolo" height={48} />
      <Txt variant="h3" className="text-center">{title}</Txt>
      {message ? <Txt color="textSecondary" className="text-center">{message}</Txt> : null}
      {action ? <View className="items-center pt-2">{action}</View> : null}
    </View>
  );
}

export const Skeleton = ({ height = 16 }: { height?: number }) => <View accessibilityElementsHidden className="bg-skeleton-bg" style={{ height }} />;

export function LiveIndicator({ onInk, label = 'En vivo' }: { onInk?: boolean; label?: string }) {
  return <View accessibilityLabel={label} className="flex-row items-center gap-1"><View className="size-2 rounded-full bg-brand-mint" /><Txt variant="caption" color={onInk ? 'sidebarText' : 'textSecondary'}>{label}</Txt></View>;
}

export function OrgMark({ text: t, sizePx = 40 }: { text: string; sizePx?: number }) {
  return <View className="items-center justify-center bg-brand-ink" style={{ width: sizePx, height: sizePx }}><Txt variant="codeSm" weight={500} color="sidebarTextActive">{t}</Txt></View>;
}

/** Barra superior móvil (título + acciones). Respeta el área segura. */
export function AppBar({ title, left, right }: { title: string; left?: ReactNode; right?: ReactNode }) {
  const insets = useSafeAreaInsets();
  return (
    <View className="border-b border-border-subtle bg-layer-01" style={{ paddingTop: insets.top }}>
      <View className="h-14 flex-row items-center px-2">
        {left ?? <View className="w-2" />}
        <View className="flex-1"><Txt variant="h3" accessibilityRole="header" numberOfLines={1}>{title}</Txt></View>
        {right}
      </View>
    </View>
  );
}

export function ListRow({ leading, title, subtitles = [], trailing, onPress, highlighted }: { leading?: ReactNode; title: ReactNode; subtitles?: string[]; trailing?: ReactNode; onPress?: () => void; highlighted?: boolean }) {
  const body = (
    <View className={cx('min-h-16 flex-row items-center gap-3 border-b border-border-subtle px-4 py-3', highlighted ? 'bg-layer-hover' : 'bg-layer-01')}>
      {leading}
      <View className="flex-1">{typeof title === 'string' ? <Txt weight={600}>{title}</Txt> : title}{subtitles.map((s) => <Txt key={s} variant="caption" color="textSecondary">{s}</Txt>)}</View>
      {trailing}
    </View>
  );
  return onPress ? <Pressable accessibilityRole="button" onPress={onPress}>{body}</Pressable> : body;
}

/** Contenedor de tarjeta: superficie layer-01 con borde sutil y el radio máximo permitido. No interactivo. */
export function Card({ children }: { children?: ReactNode }) {
  return <View className="rounded-md border border-border-subtle bg-layer-01 p-4">{children}</View>;
}

/** Filtro en forma de píldoras (una activa). */
export function Chips({ labels, index, onChange }: { labels: readonly string[]; index: number; onChange: (i: number) => void }) {
  return (
    <View className="flex-row flex-wrap gap-2">
      {labels.map((l, i) => (
        <Pressable key={l} accessibilityRole="button" accessibilityLabel={l} accessibilityState={{ selected: i === index }} onPress={() => onChange(i)}
          className={cx('h-control-md justify-center rounded-full border px-4', i === index ? 'border-interactive bg-interactive' : 'border-border-strong bg-layer-01')}>
          <Txt variant="label" weight={i === index ? 600 : 400} color={i === index ? 'textOnColor' : 'textPrimary'}>{l}</Txt>
        </Pressable>
      ))}
    </View>
  );
}

/** Etiqueta pequeña (p. ej. «Empresa», «Persona»). */
export function Tag({ label, icon }: { label: string; icon?: IconName }) {
  return (
    <View className="flex-row items-center gap-1 self-start rounded-full bg-layer-02 px-2 py-[2px]">
      {icon ? <Icon name={icon} size={12} color="textSecondary" /> : null}
      <Txt variant="caption" color="textSecondary">{label}</Txt>
    </View>
  );
}

/** Barra de avance (0–1) para la espera: cuanto más llena, más cerca el turno. */
export function ProgressBar({ value, label }: { value: number; label: string }) {
  const pct = Math.round(Math.min(1, Math.max(0, value)) * 100);
  return (
    <View accessibilityRole="progressbar" accessibilityLabel={label} accessibilityValue={{ min: 0, max: 100, now: pct }} className="h-1.5 overflow-hidden rounded-full bg-layer-selected">
      <View className="h-full rounded-full bg-brand-mint" style={{ width: `${pct}%` }} />
    </View>
  );
}

/** Acceso rápido grande: ícono en un círculo, título y una línea de contexto. */
export function Tile({ icon, title, caption, onPress }: { icon: IconName; title: string; caption?: string; onPress: () => void }) {
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={title} onPress={onPress} className="flex-1 gap-3 rounded-md border border-border-subtle bg-layer-01 p-4 active:opacity-80">
      <View className="size-11 items-center justify-center rounded-full bg-layer-02"><Icon name={icon} size={22} color="link" /></View>
      <View><Txt weight={600}>{title}</Txt>{caption ? <Txt variant="caption" color="textSecondary">{caption}</Txt> : null}</View>
    </Pressable>
  );
}

/** Título de sección con acción opcional a la derecha («Ver todas»). */
export function SectionHeader({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <View className="flex-row items-center justify-between">
      <Txt variant="h4" accessibilityRole="header">{title}</Txt>
      {action && onAction ? <Pressable accessibilityRole="button" accessibilityLabel={action} onPress={onAction} hitSlop={8}><Txt variant="label" color="link">{action}</Txt></Pressable> : null}
    </View>
  );
}

export function Tabs({ labels, index, onChange }: { labels: readonly string[]; index: number; onChange: (i: number) => void }) {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} className="grow-0 border-b border-border-subtle">
      {labels.map((l, i) => (
        <Pressable key={l} accessibilityRole="tab" accessibilityState={{ selected: i === index }} onPress={() => onChange(i)} className={cx('h-control-lg justify-center border-b-[3px] px-4', i === index ? 'border-b-interactive' : 'border-b-transparent')}>
          <Txt weight={i === index ? 600 : 400} color={i === index ? 'textPrimary' : 'textSecondary'}>{l}</Txt>
        </Pressable>
      ))}
    </ScrollView>
  );
}

export function ConfirmModal({ visible, title, message, confirmLabel, cancelLabel = 'Cancelar', danger = true, onConfirm, onCancel }: {
  visible: boolean; title: string; message: string; confirmLabel: string; cancelLabel?: string; danger?: boolean; onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel}>
      <View className="flex-1 justify-center bg-overlay p-4">
        <View accessibilityViewIsModal className="gap-3 bg-layer-01 p-6">
          <Txt variant="h3" accessibilityRole="header">{title}</Txt>
          <Txt color="textSecondary">{message}</Txt>
          <View className="flex-row flex-wrap justify-end gap-2">
            <Button label={cancelLabel} kind="ghost" onPress={onCancel} />
            <Button label={confirmLabel} kind={danger ? 'danger' : 'primary'} onPress={onConfirm} />
          </View>
        </View>
      </View>
    </Modal>
  );
}

interface ToastApi { show(message: string, opts?: { error?: boolean }): void }
const ToastCtx = createContext<ToastApi>({ show() {} });
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children, durationMs = 5000 }: { children: ReactNode; durationMs?: number }) {
  const insets = useSafeAreaInsets();
  const [item, setItem] = useState<{ message: string; error: boolean } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const show = useCallback((message: string, opts?: { error?: boolean }) => {
    if (timer.current) clearTimeout(timer.current);
    setItem({ message, error: !!opts?.error });
    if (!opts?.error) timer.current = setTimeout(() => setItem(null), durationMs);
  }, [durationMs]);
  const api = useMemo(() => ({ show }), [show]);
  return (
    <ToastCtx.Provider value={api}>
      {children}
      {item ? (
        <View pointerEvents="box-none" className="absolute inset-x-4" style={{ top: insets.top + 8 }}>
          <Pressable accessibilityRole="alert" onPress={() => setItem(null)} className={cx('flex-row items-center gap-2 border-l-[3px] bg-brand-ink p-3', item.error ? 'border-l-error-on-ink' : 'border-l-brand-mint')}>
            <Icon name={item.error ? 'error' : 'check'} size={20} color={item.error ? 'errorOnInk' : 'brandMint'} />
            <Txt color="sidebarTextActive" className="flex-1">{item.message}</Txt>
          </Pressable>
        </View>
      ) : null}
    </ToastCtx.Provider>
  );
}

export const Screen = ({ children }: { children: ReactNode }) => <SafeAreaView edges={[]} className="flex-1 bg-background">{children}</SafeAreaView>;
export { bgClass };
