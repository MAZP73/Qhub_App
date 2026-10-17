import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Validaciones puras (testeables).
String? validateEmail(String v) => _emailRe.hasMatch(v.trim()) ? null : 'Escribe un correo válido.';
String? validatePassword(String v) => v.length >= 8 ? null : 'Usa al menos 8 caracteres.';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  var _register = false;
  var _busy = false;
  Failure? _error;
  String? _info;
  String? _emailErr, _passErr, _firstErr, _lastErr;

  @override
  void dispose() {
    for (final c in [_email, _password, _first, _last]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailErr = validateEmail(_email.text);
      _passErr = _register ? validatePassword(_password.text) : (_password.text.isEmpty ? 'Escribe tu contraseña.' : null);
      _firstErr = _register && _first.text.trim().isEmpty ? 'Escribe tu nombre.' : null;
      _lastErr = _register && _last.text.trim().isEmpty ? 'Escribe tu apellido.' : null;
      _error = null;
      _info = null;
    });
    if ([_emailErr, _passErr, _firstErr, _lastErr].any((e) => e != null)) return;

    setState(() => _busy = true);
    final repo = ref.read(staffRepositoryProvider);
    if (_register) {
      final res = await repo.signUp(
          email: _email.text, password: _password.text, firstName: _first.text, lastName: _last.text);
      if (!mounted) return;
      res.when(
        ok: (user) => setState(() {
          _busy = false;
          if (user == null) {
            _info = 'Te enviamos un correo para confirmar tu cuenta. Después inicia sesión.';
            _register = false;
          }
        }),
        err: (f) => setState(() {
          _busy = false;
          _error = f;
        }),
      );
    } else {
      final res = await repo.signIn(email: _email.text, password: _password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = res.failureOrNull;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return Row(children: [
          if (wide)
            Expanded(
              child: Container(
                color: c.brandInk,
                padding: const EdgeInsets.all(QhSpacing.s09),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const QhLogo(QhLogoKind.horizontalNegative, height: 32),
                  const Spacer(),
                  Text('Cada turno, en su lugar.', style: QhText.display.copyWith(color: Colors.white)),
                  const SizedBox(height: QhSpacing.s05),
                  Text(
                    'Administra colas, horarios y franjas de tu organización y sigue cada fila en tiempo real.',
                    style: QhText.bodyLong.copyWith(color: c.sidebarText),
                  ),
                  const SizedBox(height: QhSpacing.s09),
                ]),
              ),
            ),
          Expanded(
            child: Container(
              color: c.layer01,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s06, vertical: QhSpacing.s07),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (!wide) ...[const QhLogo(QhLogoKind.horizontal, height: 28), const SizedBox(height: QhSpacing.s06)],
                      Semantics(header: true, child: Text(_register ? 'Crea tu cuenta' : 'Inicia sesión', style: QhText.h1)),
                      const SizedBox(height: QhSpacing.s03),
                      Wrap(children: [
                        Text(_register ? '¿Ya tienes cuenta? ' : '¿No tienes cuenta? ',
                            style: QhText.body.copyWith(color: c.textSecondary)),
                        InkWell(
                          onTap: _busy ? null : () => setState(() { _register = !_register; _error = null; _info = null; }),
                          child: Text(_register ? 'Inicia sesión' : 'Crea una organización',
                              style: QhText.body.copyWith(color: c.link, decoration: TextDecoration.underline)),
                        ),
                      ]),
                      const SizedBox(height: QhSpacing.s06),
                      if (_error != null) ...[
                        QhNotice(kind: QhNoticeKind.error, title: _error!.message),
                        const SizedBox(height: QhSpacing.s05),
                      ],
                      if (_info != null) ...[
                        QhNotice(kind: QhNoticeKind.info, title: _info!),
                        const SizedBox(height: QhSpacing.s05),
                      ],
                      if (_register) ...[
                        Row(children: [
                          Expanded(child: QhTextField(label: 'Nombre', controller: _first, errorText: _firstErr, autofillHints: const [AutofillHints.givenName])),
                          const SizedBox(width: QhSpacing.s03),
                          Expanded(child: QhTextField(label: 'Apellido', controller: _last, errorText: _lastErr, autofillHints: const [AutofillHints.familyName])),
                        ]),
                        const SizedBox(height: QhSpacing.s05),
                      ],
                      QhTextField(
                        label: 'Correo de trabajo',
                        controller: _email,
                        errorText: _emailErr,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: QhSpacing.s05),
                      QhTextField(
                        label: 'Contraseña',
                        controller: _password,
                        errorText: _passErr,
                        obscure: true,
                        helper: _register ? 'Mínimo 8 caracteres.' : null,
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: QhSpacing.s06),
                      QhButton(
                        label: _register ? 'Crear cuenta' : 'Continuar',
                        icon: QhIcons.arrowRight,
                        size: QhButtonSize.lg,
                        block: true,
                        loading: _busy,
                        onPressed: _submit,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}
