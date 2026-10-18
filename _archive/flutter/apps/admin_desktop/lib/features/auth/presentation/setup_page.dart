import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';
import '../../staff/domain/staff.dart';

const timeZones = {
  'America/Guayaquil': 'Ecuador (Guayaquil)',
  'America/Bogota': 'Colombia (Bogotá)',
  'America/Lima': 'Perú (Lima)',
  'America/Mexico_City': 'México (CDMX)',
  'America/Santiago': 'Chile (Santiago)',
  'America/Argentina/Buenos_Aires': 'Argentina (Buenos Aires)',
  'America/Caracas': 'Venezuela (Caracas)',
  'America/La_Paz': 'Bolivia (La Paz)',
  'America/Montevideo': 'Uruguay (Montevideo)',
  'America/Panama': 'Panamá',
  'Europe/Madrid': 'España (Madrid)',
  'UTC': 'UTC',
};

/// Usuario sin organización: crea una o acepta una invitación.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});
  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'Ecuador');
  final _token = TextEditingController();
  var _zone = 'America/Guayaquil';
  var _tab = 0;
  var _busy = false;
  Failure? _error;
  String? _nameErr, _tokenErr;

  @override
  void dispose() {
    for (final c in [_name, _city, _country, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _nameErr = _name.text.trim().length < 2 ? 'Escribe el nombre de la organización.' : null;
      _error = null;
    });
    if (_nameErr != null) return;
    setState(() => _busy = true);
    final res = await ref.read(staffRepositoryProvider).createOrganization(
          name: _name.text,
          slug: '${slugify(_name.text)}-${DateTime.now().millisecondsSinceEpoch % 100000}',
          city: _city.text.trim().isEmpty ? null : _city.text.trim(),
          country: _country.text.trim().isEmpty ? null : _country.text.trim(),
          timeZone: _zone,
        );
    await _finish(res);
  }

  Future<void> _accept() async {
    setState(() {
      _tokenErr = _token.text.trim().isEmpty ? 'Pega el código de invitación.' : null;
      _error = null;
    });
    if (_tokenErr != null) return;
    setState(() => _busy = true);
    await _finish(await ref.read(staffRepositoryProvider).acceptInvitation(_token.text));
  }

  Future<void> _finish(Result<String> res) async {
    if (!mounted) return;
    if (res.isOk) {
      ref.invalidate(membershipsProvider);
      setState(() => _busy = false);
    } else {
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(QhSpacing.s06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const QhLogo(QhLogoKind.horizontal, height: 28),
                const SizedBox(height: QhSpacing.s06),
                Text('Configura tu organización', style: QhText.h2),
                const SizedBox(height: QhSpacing.s02),
                Text('Crea una nueva o únete con un código de invitación.',
                    style: QhText.body.copyWith(color: c.textSecondary)),
                const SizedBox(height: QhSpacing.s05),
                QhTabs(labels: const ['Crear organización', 'Tengo una invitación'], index: _tab, onChanged: (i) => setState(() { _tab = i; _error = null; })),
                const SizedBox(height: QhSpacing.s06),
                if (_error != null) ...[
                  QhNotice(kind: QhNoticeKind.error, title: _error!.message),
                  const SizedBox(height: QhSpacing.s05),
                ],
                if (_tab == 0) ...[
                  QhTextField(label: 'Nombre de la organización', controller: _name, errorText: _nameErr),
                  const SizedBox(height: QhSpacing.s05),
                  Row(children: [
                    Expanded(child: QhTextField(label: 'Ciudad', controller: _city)),
                    const SizedBox(width: QhSpacing.s03),
                    Expanded(child: QhTextField(label: 'País', controller: _country)),
                  ]),
                  const SizedBox(height: QhSpacing.s05),
                  QhSelect<String>(label: 'Zona horaria', value: _zone, items: timeZones, onChanged: (v) => setState(() => _zone = v ?? _zone)),
                  const SizedBox(height: QhSpacing.s06),
                  QhButton(label: 'Crear organización', icon: QhIcons.arrowRight, size: QhButtonSize.lg, block: true, loading: _busy, onPressed: _create),
                ] else ...[
                  QhTextField(label: 'Código de invitación', controller: _token, errorText: _tokenErr, helper: 'Te lo comparte un administrador de la organización.'),
                  const SizedBox(height: QhSpacing.s06),
                  QhButton(label: 'Unirme', icon: QhIcons.arrowRight, size: QhButtonSize.lg, block: true, loading: _busy, onPressed: _accept),
                ],
                const SizedBox(height: QhSpacing.s05),
                Align(
                  alignment: Alignment.centerLeft,
                  child: QhButton(label: 'Cerrar sesión', kind: QhButtonKind.ghost, size: QhButtonSize.sm, onPressed: () => ref.read(staffRepositoryProvider).signOut()),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
