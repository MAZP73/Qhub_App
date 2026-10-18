import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/features/settings/presentation/settings_page.dart';
import 'package:qhub_admin/features/staff/domain/staff.dart';
import 'package:qhub_core/qhub_core.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  Env env({bool linked = false, FakeStaffRepository? staff}) => Env(
        staff: staff ??
            FakeStaffRepository(user: ana, memberships: [
              Membership(
                organization: Organization(id: 'org1', name: 'Notaría 12', slug: 'n12', timeZone: 'America/Guayaquil', linked: linked, published: linked),
                role: OrgRole.admin,
              ),
            ]),
      );

  testWidgets('no publicada: ofrece publicar y pide la cuenta Qhub', (t) async {
    useDesktopSize(t);
    final e = env();
    await t.pumpWidget(themed(const SettingsPage(), e));
    await settle(t);
    expect(find.text('Tu organización aún no aparece en la app móvil.'), findsOneWidget);

    await t.ensureVisible(find.text('Publicar en la app móvil').last);
    await t.tap(find.text('Publicar en la app móvil').last);
    await settle(t);
    expect(find.text('Confirma la cuenta Qhub de tu organización. La validamos y la guardamos en el servidor.'), findsOneWidget);

    await t.enterText(find.byType(TextField).last, 'clave-segura-1');
    await t.enterText(find.byType(TextField).at(find.byType(TextField).evaluate().length - 2), 'notaria12');
    await t.tap(find.text('Publicar').last);
    await settle(t);
    expect(e.staff.calls, contains('publish:notaria12'));
  });

  testWidgets('si Qhub rechaza la cuenta se explica el motivo', (t) async {
    useDesktopSize(t);
    final staff = FakeStaffRepository(user: ana, memberships: const [adminMembership])..publishFailure = const BadRequestFailure('Usuario o contraseña de Qhub incorrectos');
    final e = env(staff: staff);
    await t.pumpWidget(themed(const SettingsPage(), e));
    await settle(t);
    await t.ensureVisible(find.text('Publicar en la app móvil').last);
    await t.tap(find.text('Publicar en la app móvil').last);
    await settle(t);
    await t.tap(find.text('Publicar').last);
    await settle(t);
    expect(find.text('Usuario o contraseña de Qhub incorrectos'), findsOneWidget);
  });

  testWidgets('publicada: permite dejar de publicar con confirmación', (t) async {
    useDesktopSize(t);
    final e = env(linked: true);
    await t.pumpWidget(themed(const SettingsPage(), e));
    await settle(t);
    expect(find.text('Tu organización está publicada en la app móvil.'), findsOneWidget);
    await t.ensureVisible(find.text('Dejar de publicar').last);
    await t.tap(find.text('Dejar de publicar').last);
    await settle(t);
    await t.tap(find.text('Dejar de publicar').last);
    await settle(t);
    expect(e.staff.calls, contains('unpublish'));
  });

  testWidgets('la contraseña de Qhub se avisa que vive solo en el servidor', (t) async {
    useDesktopSize(t);
    await t.pumpWidget(themed(const SettingsPage(), env()));
    await settle(t);
    expect(find.textContaining('solo en el servidor'), findsOneWidget);
  });
}
