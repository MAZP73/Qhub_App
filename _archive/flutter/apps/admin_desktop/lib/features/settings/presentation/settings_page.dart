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

  Future<void> _save() async {
    final m = ref.read(activeMembershipProvider)!;
    setState(() => _busy = true);
    final res = await ref.read(staffRepositoryProvider).updateOrganization(m.organization.id, name: _name.text.trim());
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

  Future<void> _publish() async {
    final creds = await showDialog<({String id, String pw})>(
      context: context,
      barrierColor: context.qh.overlay,
      builder: (_) => const _PublishDialog(),
    );
    if (creds == null || !mounted) return;
    setState(() => _busy = true);
    final m = ref.read(activeMembershipProvider)!;
    final res = await ref.read(staffRepositoryProvider).publishToMobile(m.organization.id, identifier: creds.id, password: creds.pw);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.invalidate(membershipsProvider);
        showToast(context, 'Tu organización ya aparece en la app móvil.');
      },
      err: (f) => showToast(context, f.message, error: true),
    );
  }

  Future<void> _unpublish() async {
    final yes = await qhConfirm(context,
        title: 'Dejar de publicar',
        message: 'El público dejará de ver tu organización. Los turnos ya sacados se conservan.',
        confirmLabel: 'Dejar de publicar',
        danger: false);
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final m = ref.read(activeMembershipProvider)!;
    final res = await ref.read(staffRepositoryProvider).unpublishFromMobile(m.organization.id);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.invalidate(membershipsProvider);
        showToast(context, 'Ya no aparece en la app móvil.');
      },
      err: (f) => showToast(context, f.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            QhButton(label: 'Guardar', icon: QhIcons.check, loading: _busy, onPressed: _save),
          ]),
        ),
        const SizedBox(height: QhSpacing.s05),
        Panel(
          title: 'App móvil',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            QhNotice(
              kind: m.organization.linked ? QhNoticeKind.success : QhNoticeKind.info,
              title: m.organization.linked ? 'Tu organización está publicada en la app móvil.' : 'Tu organización aún no aparece en la app móvil.',
              message: 'El público podrá ver tus colas y sacar turnos. La contraseña de Qhub se guarda solo en el servidor, nunca en la app.',
            ),
            const SizedBox(height: QhSpacing.s05),
            if (m.organization.linked)
              QhButton(label: 'Dejar de publicar', kind: QhButtonKind.secondary, loading: _busy, onPressed: _unpublish)
            else
              QhButton(label: 'Publicar en la app móvil', icon: QhIcons.arrowRight, loading: _busy, onPressed: _publish),
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

/// Diálogo con sus propios controladores: se liberan cuando el diálogo termina de cerrarse.
class _PublishDialog extends StatefulWidget {
  const _PublishDialog();
  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  final _id = TextEditingController();
  final _pw = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Dialog(
      backgroundColor: c.layer01,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(QhSpacing.s06),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Publicar en la app móvil', style: QhText.h3),
            const SizedBox(height: QhSpacing.s03),
            Text('Confirma la cuenta Qhub de tu organización. La validamos y la guardamos en el servidor.',
                style: QhText.body.copyWith(color: c.textSecondary)),
            const SizedBox(height: QhSpacing.s05),
            QhTextField(label: 'Correo o usuario de Qhub', controller: _id),
            const SizedBox(height: QhSpacing.s04),
            QhTextField(label: 'Contraseña', controller: _pw, obscure: true),
            const SizedBox(height: QhSpacing.s06),
            Wrap(alignment: WrapAlignment.end, spacing: QhSpacing.s03, children: [
              QhButton(label: 'Cancelar', kind: QhButtonKind.ghost, onPressed: () => Navigator.of(context).pop()),
              QhButton(label: 'Publicar', onPressed: () => Navigator.of(context).pop((id: _id.text, pw: _pw.text))),
            ]),
          ]),
        ),
      ),
    );
  }
}
