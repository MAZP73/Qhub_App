import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/app/app.dart';
import 'package:qhub_core/qhub_core.dart';

import 'package:qhub_admin/features/qhub/domain/qhub_connection.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

Future<void> pumpApp(WidgetTester t, Env env) async {
  useDesktopSize(t);
  await t.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: env.overrides, child: const QhubAdminApp()));
  await settle(t);
}

void main() {
  testWidgets('sin sesión muestra el login y valida los campos', (t) async {
    final env = Env();
    await pumpApp(t, env);
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Cada turno, en su lugar.'), findsOneWidget);

    await t.tap(find.text('Continuar'));
    await settle(t);
    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    expect(env.staff.calls, isEmpty);
  });

  testWidgets('credenciales incorrectas muestran el error', (t) async {
    final env = Env(staff: FakeStaffRepository()..signInFailure = const UnauthorizedFailure('Correo o contraseña incorrectos.'));
    await pumpApp(t, env);
    await t.enterText(find.byType(TextField).at(0), 'ana@x.co');
    await t.enterText(find.byType(TextField).at(1), 'secreto123');
    await t.tap(find.text('Continuar'));
    await settle(t);
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('Inicia sesión'), findsOneWidget);
  });

  testWidgets('flujo completo: login → crear organización → conectar Qhub → colas', (t) async {
    final env = Env();
    await pumpApp(t, env);

    await t.enterText(find.byType(TextField).at(0), 'ana@x.co');
    await t.enterText(find.byType(TextField).at(1), 'secreto123');
    await t.tap(find.text('Continuar'));
    await settle(t);
    expect(find.text('Configura tu organización'), findsOneWidget);

    await t.enterText(find.byType(TextField).at(0), 'Notaría 12');
    await t.tap(find.text('Crear organización').last);
    await settle(t);
    expect(env.staff.calls, contains('createOrg:Notaría 12'));
    expect(find.text('Conecta Notaría 12 con Qhub'), findsOneWidget);

    await t.enterText(find.byType(TextField).at(0), 'notaria12');
    await t.enterText(find.byType(TextField).at(1), 'clave-segura-1');
    await t.tap(find.text('Conectar'));
    await settle(t);

    expect(env.auth.logins, ['notaria12']);
    expect(find.text('Colas'), findsWidgets);
    expect(find.text('Caja 1'), findsOneWidget);
    expect(find.text('Crear cola'), findsOneWidget); // es admin
    expect(env.store.data['org-new']?.identifier, 'notaria12'); // "Mantener sesión" viene marcado
  });

  testWidgets('con "Mantener sesión" guardada entra directo a colas', (t) async {
    final env = Env(staff: FakeStaffRepository(user: ana, memberships: const [adminMembership]));
    env.store.data['org1'] = const QhubCredential('notaria12', 'pw');
    await pumpApp(t, env);
    expect(find.text('Caja 1'), findsOneWidget);
    expect(env.auth.logins, ['notaria12']);
  });

  testWidgets('el agente ve la operación pero no la administración', (t) async {
    final env = Env(staff: FakeStaffRepository(user: ana, memberships: const [agentMembership]));
    env.store.data['org1'] = const QhubCredential('notaria12', 'pw');
    await pumpApp(t, env);
    expect(find.text('Caja 1'), findsOneWidget);
    expect(find.text('En vivo'), findsWidgets);
    expect(find.text('Historial'), findsWidgets);
    expect(find.text('Equipo'), findsNothing);
    expect(find.text('Ajustes'), findsNothing);
    expect(find.text('Crear cola'), findsNothing);
  });

  testWidgets('el admin ve Equipo y puede invitar', (t) async {
    final env = Env(staff: FakeStaffRepository(user: ana, memberships: const [adminMembership]));
    env.store.data['org1'] = const QhubCredential('notaria12', 'pw');
    await pumpApp(t, env);
    await t.tap(find.text('Equipo'));
    await settle(t);
    expect(find.text('Ana Gómez (tú)'), findsOneWidget);
    expect(find.text('Luis Vera'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'nuevo@x.co');
    await t.tap(find.text('Invitar').last);
    await settle(t);
    expect(env.staff.calls, contains('invite:nuevo@x.co:agente'));
    expect(find.text('tok-0'), findsOneWidget);
  });

  testWidgets('límite de colas alcanzado deshabilita "Crear cola" y avisa', (t) async {
    final env = Env(
      staff: FakeStaffRepository(user: ana, memberships: const [adminMembership]),
      queues: FakeQueueRepository(limitValue: const QueueLimitFake().value),
    );
    env.store.data['org1'] = const QhubCredential('notaria12', 'pw');
    await pumpApp(t, env);
    expect(find.textContaining('Llegaste al límite de colas (6)'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.ancestor(of: find.text('Crear cola'), matching: find.byType(FilledButton)).first);
    expect(btn.onPressed, isNull);
  });
}
