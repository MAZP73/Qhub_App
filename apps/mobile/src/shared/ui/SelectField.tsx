import { useMemo, useState } from 'react';
import { FlatList, Modal, Pressable, TextInput, View } from 'react-native';
import { cx, Icon, Txt } from './kit';
import { useTheme } from './theme';

export interface Option { value: string; label: string; hint?: string }

/** Selector tipo lista buscable (país, ciudad, zona horaria, prefijo). Solo tokens del design system. */
export function SelectField({ label, value, options, onValueChange, placeholder = 'Elegir', error, disabled, searchable = true }: {
  label: string; value: string; options: readonly Option[]; onValueChange: (value: string) => void;
  placeholder?: string; error?: string | null; disabled?: boolean; searchable?: boolean;
}) {
  const { c } = useTheme();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const selected = options.find((o) => o.value === value);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return options;
    return options.filter((o) => o.label.toLowerCase().includes(q) || (o.hint ?? '').toLowerCase().includes(q));
  }, [options, query]);

  const close = () => { setOpen(false); setQuery(''); };

  return (
    <View className="gap-1">
      <Txt variant="label" color="textSecondary">{label}</Txt>
      <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled: !!disabled }} disabled={disabled} onPress={() => setOpen(true)}
        className={cx('min-h-control-lg flex-row items-center bg-field px-4', error ? 'border-2 border-support-error' : 'border-b border-border-strong', disabled && 'opacity-60')}>
        <Txt className="flex-1" color={selected ? 'textPrimary' : 'textPlaceholder'} numberOfLines={1}>{selected?.label ?? placeholder}</Txt>
        {error ? <Icon name="warning" color="supportError" /> : <Icon name="chevron-down" color="textSecondary" />}
      </Pressable>
      {error ? <Txt variant="caption" color="supportError">{error}</Txt> : null}

      <Modal visible={open} transparent animationType="fade" onRequestClose={close}>
        <Pressable accessibilityRole="button" accessibilityLabel="Cerrar" className="flex-1 bg-overlay" onPress={close} />
        <View className="absolute inset-x-4 top-[12%] bottom-[12%] bg-layer-01">
          <View className="flex-row items-center justify-between border-b border-border-subtle p-4">
            <Txt variant="h4" accessibilityRole="header">{label}</Txt>
            <Pressable accessibilityRole="button" accessibilityLabel="Cerrar" onPress={close} className="h-control-md w-control-md items-center justify-center"><Icon name="close" size={20} /></Pressable>
          </View>
          {searchable && (
            <View className="flex-row items-center gap-2 border-b border-border-subtle bg-field px-4">
              <Icon name="search" color="textSecondary" />
              <TextInput accessibilityLabel="Buscar" value={query} onChangeText={setQuery} placeholder="Buscar" placeholderTextColor={c.textPlaceholder} cursorColor={c.interactive}
                className="min-h-control-lg flex-1 font-sans-400 text-text-primary" />
            </View>
          )}
          <FlatList
            data={filtered}
            keyExtractor={(o) => o.value}
            keyboardShouldPersistTaps="handled"
            ListEmptyComponent={<Txt color="textSecondary" className="p-4">Sin resultados.</Txt>}
            renderItem={({ item }) => {
              const on = item.value === value;
              return (
                <Pressable accessibilityRole="button" accessibilityLabel={item.label} accessibilityState={{ selected: on }} onPress={() => { onValueChange(item.value); close(); }}
                  className={cx('min-h-control-lg flex-row items-center gap-3 border-b border-border-subtle px-4 py-3', on ? 'bg-layer-hover' : 'bg-layer-01')}>
                  <View className="flex-1"><Txt weight={on ? 600 : 400}>{item.label}</Txt>{item.hint ? <Txt variant="caption" color="textSecondary">{item.hint}</Txt> : null}</View>
                  {on ? <Icon name="check" color="link" /> : null}
                </Pressable>
              );
            }}
          />
        </View>
      </Modal>
    </View>
  );
}
