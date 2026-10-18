import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../../auth/presentation/login_page.dart' show validateEmail;
import '../../staff/domain/staff.dart';

final membersProvider = FutureProvider.autoDispose<List<Member>>((ref) async {
  final org = ref.watch(activeMembershipProvider)?.organization.id;
  if (org == null) return const [];
  return (await ref.watch(staffRepositoryProvider).members(org)).getOrThrow();
});

final invitationsProvider = FutureProvider.autoDispose<List<Invitation>>((ref) async {
  final org = ref.watch(activeMembershipProvider)?.organization.id;
  if (org == null) return const [];
  return (await ref.watch(staffRepositoryProvider).invitations(org)).getOrThrow();
});

class TeamPage extends ConsumerStatefulWidget {
  const TeamPage({super.key});
  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> {
  final _email = TextEditingController();
  var _role = OrgRole.agente;
  String? _emailErr;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    setState(() => _emailErr = validateEmail(_email.text));
    if (_emailErr != null) return;
    setState(() => _busy = true);
    final org = ref.read(activeMembershipProvider)!.organization.id;
    final res = await ref.read(staffRepositoryProvider).invite(org, email: _email.text, role: _role);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (inv) {
        _email.clear();
        ref.invalidate(invitationsProvider);
        showToast(context, 'Invitación creada. Comparte el código con ${inv.email}.');
      },
      err: (f) => showToast(context, f.message, error: true),
    );
  }

  Future<void> _change(Member m, {OrgRole? role, bool? active}) async {
    final org = ref.read(activeMembershipProvider)!.organization.id;
    final res = await ref.read(staffRepositoryProvider).updateMember(org, m.userId, role: role, active: active);
    if (!mounted) return;
    res.when(
      ok: (_) => ref.invalidate(membersProvider),
      err: (f) => showToast(context, f.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final members = ref.watch(membersProvider);
    final invitations = ref.watch(invitationsProvider);
    final me = ref.watch(authUserProvider).value?.id;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHead(title: 'Equipo', breadcrumb: 'Administración'),
        Panel(
          title: 'Invitar a alguien',
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: QhTextField(label: 'Correo', controller: _email, errorText: _emailErr, keyboardType: TextInputType.emailAddress)),
            const SizedBox(width: QhSpacing.s05),
            Expanded(child: QhSelect<OrgRole>(label: 'Rol', value: _role, items: {for (final r in OrgRole.values) r: r.label}, onChanged: (v) => setState(() => _role = v ?? _role))),
            const SizedBox(width: QhSpacing.s05),
            Padding(padding: const EdgeInsets.only(top: 20), child: QhButton(label: 'Invitar', icon: QhIcons.plus, loading: _busy, onPressed: _invite)),
          ]),
        ),
        const SizedBox(height: QhSpacing.s05),
        Panel(
          title: 'Miembros',
          child: AsyncBody<List<Member>>(
            value: members,
            onRetry: () => ref.invalidate(membersProvider),
            builder: (list) => Column(children: [
              for (final m in list)
                Container(
                  height: QhSize.rowHeight,
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.borderSubtle))),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text('${m.name}${m.userId == me ? ' (tú)' : ''}', style: QhText.body.copyWith(fontWeight: FontWeight.w600))),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<OrgRole>(
                          value: m.role,
                          isDense: true,
                          items: [for (final r in OrgRole.values) DropdownMenuItem(value: r, child: Text(r.label, style: QhText.body))],
                          onChanged: m.userId == me ? null : (v) => _change(m, role: v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: Row(children: [
                        Switch(value: m.active, onChanged: m.userId == me ? null : (v) => _change(m, active: v)),
                        Text(m.active ? 'Activo' : 'Inactivo', style: QhText.caption),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: QhSpacing.s05),
        Panel(
          title: 'Invitaciones pendientes',
          child: AsyncBody<List<Invitation>>(
            value: invitations,
            onRetry: () => ref.invalidate(invitationsProvider),
            builder: (list) {
              final pending = list.where((i) => i.pending).toList();
              if (pending.isEmpty) return Text('No hay invitaciones pendientes.', style: QhText.body.copyWith(color: c.textSecondary));
              return Column(children: [
                for (final i in pending)
                  Container(
                    height: QhSize.rowHeight,
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.borderSubtle))),
                    child: Row(children: [
                      Expanded(flex: 2, child: Text(i.email)),
                      Expanded(child: Text(i.role.label, style: QhText.body.copyWith(color: c.textSecondary))),
                      Expanded(flex: 2, child: Text(i.token, style: QhText.codeSm, overflow: TextOverflow.ellipsis)),
                      QhIconButton(
                        icon: QhIcons.copy,
                        label: 'Copiar código',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: i.token));
                          if (context.mounted) showToast(context, 'Código copiado.');
                        },
                      ),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
