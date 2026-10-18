import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../domain/qhub_connection.dart';

/// Conecta la organización con su cuenta Qhub (API). Se pide una vez; luego "Mantener sesión".
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});
  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _user = TextEditingController();
  final _mail = TextEditingController();
  final _country = TextEditingController(text: 'Ecuador');
  final _city = TextEditingController();
  var _tab = 0;
  var _remember = true;
  var _restoring = true;
  var _busy = false;
  var _terms = false;
  Failure? _error;
  final _errs = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(qhubConnectionProvider.notifier).restore();
      if (mounted) setState(() => _restoring = false);
    });
  }

  @override
  void dispose() {
    for (final c in [_id, _pw, _first, _last, _user, _mail, _country, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _errs.clear();
      _error = null;
      if (_id.text.trim().isEmpty) _errs['id'] = 'Escribe tu correo o usuario de Qhub.';
      if (_pw.text.isEmpty) _errs['pw'] = 'Escribe la contraseña.';
    });
    if (_errs.isNotEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(qhubConnectionProvider.notifier).connect(identifier: _id.text, password: _pw.text, remember: _remember);
    if (mounted) setState(() { _busy = false; _error = res.failureOrNull; });
  }

  Future<void> _register() async {
    final membership = ref.read(activeMembershipProvider);
    setState(() {
      _errs.clear();
      _error = null;
      if (_first.text.trim().isEmpty) _errs['first'] = 'Escribe tu nombre.';
      if (_last.text.trim().isEmpty) _errs['last'] = 'Escribe tu apellido.';
      if (_user.text.trim().length < 3 || _user.text.contains(' ')) _errs['user'] = 'Mínimo 3 caracteres, sin espacios.';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_mail.text.trim())) _errs['mail'] = 'Escribe un correo válido.';
      if (_pw.text.length < 8) _errs['pw'] = 'Usa al menos 8 caracteres.';
      if (_city.text.trim().isEmpty) _errs['city'] = 'Escribe la ciudad.';
      if (!_terms) _errs['terms'] = 'Debes aceptar los términos.';
    });
    if (_errs.isNotEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(authRepositoryProvider).register(RegisterInput(
          accountType: AccountType.empresa,
          companyName: membership?.organization.name,
          firstName: _first.text.trim(),
          lastName: _last.text.trim(),
          username: _user.text.trim(),
          email: _mail.text.trim(),
          password: _pw.text,
          country: _country.text.trim(),
          city: _city.text.trim(),
          acceptedTerms: _terms,
        ));
    if (res.isErr) {
      if (mounted) setState(() { _busy = false; _error = res.failureOrNull; });
      return;
    }
    final login = await ref.read(qhubConnectionProvider.notifier).connect(identifier: _user.text, password: _pw.text, remember: true);
    if (mounted) setState(() { _busy = false; _error = login.failureOrNull; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final conn = ref.watch(qhubConnectionProvider);
    final org = ref.watch(activeMembershipProvider)?.organization.name ?? '';
    final reason = conn is QhubDisconnected ? conn.reason : null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(QhSpacing.s06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Panel(
              child: _restoring
                  ? const Column(children: [Skeleton(height: 24, width: 260), SizedBox(height: 16), Skeleton(height: 80)])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const QhLogo(QhLogoKind.horizontal, height: 28),
                      const SizedBox(height: QhSpacing.s06),
                      Text('Conecta $org con Qhub', style: QhText.h2),
                      const SizedBox(height: QhSpacing.s02),
                      Text('Usa la cuenta Qhub de tu organización para gestionar colas y turnos en vivo.',
                          style: QhText.body.copyWith(color: c.textSecondary)),
                      const SizedBox(height: QhSpacing.s05),
                      QhTabs(labels: const ['Ya tengo cuenta', 'Crear cuenta'], index: _tab, onChanged: (i) => setState(() { _tab = i; _error = null; _errs.clear(); })),
                      const SizedBox(height: QhSpacing.s06),
                      if (_error != null || reason != null) ...[
                        QhNotice(kind: QhNoticeKind.error, title: (_error ?? reason)!.message),
                        const SizedBox(height: QhSpacing.s05),
                      ],
                      if (_tab == 0) ...[
                        QhTextField(label: 'Correo o usuario de Qhub', controller: _id, errorText: _errs['id']),
                        const SizedBox(height: QhSpacing.s05),
                        QhTextField(label: 'Contraseña', controller: _pw, errorText: _errs['pw'], obscure: true, onSubmitted: (_) => _connect()),
                        const SizedBox(height: QhSpacing.s04),
                        Row(children: [
                          Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false)),
                          Text('Mantener sesión', style: QhText.body),
                        ]),
                        const SizedBox(height: QhSpacing.s05),
                        QhButton(label: 'Conectar', icon: QhIcons.arrowRight, size: QhButtonSize.lg, block: true, loading: _busy, onPressed: _connect),
                      ] else ...[
                        Row(children: [
                          Expanded(child: QhTextField(label: 'Nombre', controller: _first, errorText: _errs['first'])),
                          const SizedBox(width: QhSpacing.s03),
                          Expanded(child: QhTextField(label: 'Apellido', controller: _last, errorText: _errs['last'])),
                        ]),
                        const SizedBox(height: QhSpacing.s05),
                        QhTextField(label: 'Usuario de Qhub', controller: _user, errorText: _errs['user']),
                        const SizedBox(height: QhSpacing.s05),
                        QhTextField(label: 'Correo', controller: _mail, errorText: _errs['mail'], keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: QhSpacing.s05),
                        QhTextField(label: 'Contraseña', controller: _pw, errorText: _errs['pw'], obscure: true, helper: 'Mínimo 8 caracteres.'),
                        const SizedBox(height: QhSpacing.s05),
                        Row(children: [
                          Expanded(child: QhTextField(label: 'País', controller: _country)),
                          const SizedBox(width: QhSpacing.s03),
                          Expanded(child: QhTextField(label: 'Ciudad', controller: _city, errorText: _errs['city'])),
                        ]),
                        const SizedBox(height: QhSpacing.s04),
                        Row(children: [
                          Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
                          Expanded(child: Text('Acepto los términos y condiciones', style: QhText.body)),
                        ]),
                        if (_errs['terms'] != null) Text(_errs['terms']!, style: QhText.caption.copyWith(color: c.supportError)),
                        const SizedBox(height: QhSpacing.s05),
                        QhButton(label: 'Crear cuenta y conectar', icon: QhIcons.arrowRight, size: QhButtonSize.lg, block: true, loading: _busy, onPressed: _register),
                      ],
                      const SizedBox(height: QhSpacing.s05),
                      QhButton(label: 'Cerrar sesión', kind: QhButtonKind.ghost, size: QhButtonSize.sm, onPressed: () => ref.read(staffRepositoryProvider).signOut()),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
