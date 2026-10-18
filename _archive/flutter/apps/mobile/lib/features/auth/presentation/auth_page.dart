import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
String? validateEmail(String v) => _emailRe.hasMatch(v.trim()) ? null : 'Escribe un correo válido.';
String? validatePassword(String v) => v.length >= 8 ? null : 'Usa al menos 8 caracteres.';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
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
    final repo = ref.read(userRepositoryProvider);
    if (_register) {
      final res = await repo.signUp(email: _email.text, password: _password.text, firstName: _first.text, lastName: _last.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = res.failureOrNull;
        if (res.isOk && res.valueOrNull == null) {
          _info = 'Te enviamos un correo para confirmar tu cuenta. Después inicia sesión.';
          _register = false;
        }
      });
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(QhSpacing.s05),
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: QhSpacing.s07),
              const QhLogo(QhLogoKind.horizontal, height: 32),
              const SizedBox(height: QhSpacing.s08),
              Semantics(header: true, child: Text('Tu turno, sin filas.', style: QhText.h1)),
              const SizedBox(height: QhSpacing.s03),
              Text(_register ? 'Crea tu cuenta para sacar y seguir turnos.' : 'Inicia sesión para ver tus turnos.',
                  style: QhText.bodyLong.copyWith(color: c.textSecondary)),
              const SizedBox(height: QhSpacing.s06),
              if (_error != null) ...[QhNotice(kind: QhNoticeKind.error, title: _error!.message), const SizedBox(height: QhSpacing.s05)],
              if (_info != null) ...[QhNotice(kind: QhNoticeKind.info, title: _info!), const SizedBox(height: QhSpacing.s05)],
              if (_register) ...[
                Row(children: [
                  Expanded(child: QhTextField(label: 'Nombre', controller: _first, errorText: _firstErr, autofillHints: const [AutofillHints.givenName])),
                  const SizedBox(width: QhSpacing.s03),
                  Expanded(child: QhTextField(label: 'Apellido', controller: _last, errorText: _lastErr, autofillHints: const [AutofillHints.familyName])),
                ]),
                const SizedBox(height: QhSpacing.s05),
              ],
              QhTextField(label: 'Correo', controller: _email, errorText: _emailErr, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
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
              QhButton(label: _register ? 'Crear cuenta' : 'Continuar', icon: QhIcons.arrowRight, size: QhButtonSize.lg, block: true, loading: _busy, onPressed: _submit),
              const SizedBox(height: QhSpacing.s03),
              QhButton(
                label: _register ? 'Ya tengo cuenta' : 'Crear cuenta',
                kind: QhButtonKind.tertiary,
                size: QhButtonSize.lg,
                block: true,
                onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; _info = null; }),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
