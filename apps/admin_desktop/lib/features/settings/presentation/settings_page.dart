import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';

final readinessProvider = FutureProvider.autoDispose<Readiness>((ref) async {
  return (await ref.watch(healthRepositoryProvider).ready()).getOrThrow();
});

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _name = TextEditingController();
  var _inited = false;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save({bool? published}) async {
    final m = ref.read(activeMembershipProvider)!;
    setState(() => _busy = true);
    final res = await ref.read(staffRepositoryProvider).updateOrganization(m.organization.id,
        name: published == null ? _name.text.trim() : null, published: published);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.invalidate(membershipsProvider);
        showToast(context, 'Cambios guardados.');
      },
      err: (f) => showToast(context, f.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const SizedBox.shrink();
    if (!_inited) {
      _name.text = m.organization.name;
      _inited = true;
    }
    final ready = ref.watch(readinessProvider);
    final mode = ref.watch(themeModeProvider);

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead(title: 'Ajustes', breadcrumb: 'Administración'),
        Panel(
          title: 'Organización',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            QhTextField(label: 'Nombre', controller: _name),
            const SizedBox(height: QhSpacing.s05),
            QhButton(label: 'Guardar', icon: QhIcons.check, loading: _busy, onPressed: () => _save()),
            const SizedBox(height: QhSpacing.s06),
            Row(children: [
              Switch(value: m.organization.published, onChanged: _busy ? null : (v) => _save(published: v)),
              const SizedBox(width: QhSpacing.s03),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visible en la app móvil', style: QhText.body.copyWith(fontWeight: FontWeight.w600)),
                  Text('El público podrá encontrar tu organización. Requiere que el equipo de Qhub conecte tus colas.',
                      style: QhText.caption.copyWith(color: c.textSecondary)),
                ]),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: QhSpacing.s05),
        Panel(
          title: 'Apariencia',
          child: QhSelect<ThemeMode>(
            label: 'Tema',
            value: mode,
            items: const {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
            onChanged: (v) => ref.read(themeModeProvider.notifier).set(v ?? mode),
          ),
        ),
        const SizedBox(height: QhSpacing.s05),
        Panel(
          title: 'Conexión con Qhub',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ready.when(
              data: (r) => QhNotice(
                kind: r.isReady ? QhNoticeKind.success : QhNoticeKind.warning,
                title: r.isReady ? 'La API responde con normalidad.' : 'La API está degradada.',
                message: 'Base de datos: ${r.supabase} · Mensajería: ${r.rabbitmq}',
              ),
              error: (e, _) => QhNotice(kind: QhNoticeKind.error, title: 'No pudimos consultar la API.'),
              loading: () => const Skeleton(height: 48),
            ),
            const SizedBox(height: QhSpacing.s05),
            Row(children: [
              QhButton(label: 'Probar de nuevo', kind: QhButtonKind.tertiary, onPressed: () => ref.invalidate(readinessProvider)),
              const SizedBox(width: QhSpacing.s03),
              QhButton(
                label: 'Desconectar cuenta Qhub',
                kind: QhButtonKind.secondary,
                onPressed: () async {
                  final n = ref.read(qhubConnectionProvider.notifier);
                  await n.forgetStoredCredential();
                  n.disconnect();
                },
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
