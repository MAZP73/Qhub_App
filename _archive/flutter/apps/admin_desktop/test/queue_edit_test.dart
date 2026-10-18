import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_admin/app/providers.dart';
import 'package:qhub_admin/features/queues/presentation/queue_edit_page.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_ui/qhub_ui.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

Widget host(Env env, {String? id}) {
  final router = GoRouter(initialLocation: id == null ? '/nueva' : '/editar', routes: [
    GoRoute(path: '/nueva', builder: (_, _) => const _Page(QueueEditPage())),
    GoRoute(path: '/editar', builder: (_, _) => _Page(QueueEditPage(queueId: id))),
    GoRoute(path: '/colas', builder: (_, _) => const Scaffold(body: Text('LISTA DE COLAS'))),
  ]);
  return ProviderScope(
    retry: (_, _) => null,
    overrides: env.overrides,
    child: MaterialApp.router(theme: QhTheme.light(), routerConfig: router),
  );
}

/// Mantiene vivos los providers de sesión, como lo hace el router real.
class _Page extends ConsumerWidget {
  const _Page(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(membershipsProvider);
    return Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child));
  }
}

void main() {
  Env env() => Env(staff: FakeStaffRepository(user: ana, memberships: const [adminMembership]));

  testWidgets('crear: valida el nombre y el horario antes de ir a la red', (t) async {
    useDesktopSize(t);
    final e = env();
    await t.pumpWidget(host(e));
    await settle(t);

    await t.tap(find.text('Guardar cola'));
    await settle(t);
    expect(find.text('Escribe el nombre de la cola.'), findsOneWidget);
    expect(e.queues.lastCreate, isNull);

    await t.enterText(find.byType(TextField).at(0), 'Cajas');
    await t.enterText(find.byType(TextField).at(4), '07:00'); // cierre antes de apertura
    await t.tap(find.text('Guardar cola'));
    await settle(t);
    expect(find.text('El cierre debe ser posterior a la apertura.'), findsOneWidget);
    expect(e.queues.lastCreate, isNull);
  });

  testWidgets('crear: el resumen se calcula y se envía el horario', (t) async {
    useDesktopSize(t);
    final e = env();
    await t.pumpWidget(host(e));
    await settle(t);

    await t.enterText(find.byType(TextField).at(0), 'Cajas');
    await t.enterText(find.byType(TextField).at(5), '10'); // trámite
    await t.enterText(find.byType(TextField).at(6), '2'); // puestos
    await settle(t);
    expect(find.text('Cupos por franja'), findsOneWidget);
    expect(find.text('6'), findsWidgets); // 30/10 × 2

    await t.tap(find.text('Guardar cola'));
    await settle(t);

    final input = e.queues.lastCreate!;
    expect(input.name, 'Cajas');
    expect(input.schedule!.capacityPerSlot, 6);
    expect(input.schedule!.days, [1, 2, 3, 4, 5]);
    expect(e.staff.prefixes['q2'], 'C'); // prefijo por defecto de "Cajas"
    expect(e.staff.audits, ['cola.crear']);
    expect(find.text('LISTA DE COLAS'), findsOneWidget);
  });

  testWidgets('crear: un 409 de la API se muestra sin salir de la pantalla', (t) async {
    useDesktopSize(t);
    final e = env();
    e.queues.createFailure = const ConflictFailure('Ya tienes una cola con ese nombre.');
    await t.pumpWidget(host(e));
    await settle(t);
    await t.enterText(find.byType(TextField).at(0), 'Caja 1');
    await t.tap(find.text('Guardar cola'));
    await settle(t);
    expect(find.text('Ya tienes una cola con ese nombre.'), findsOneWidget);
    expect(find.text('LISTA DE COLAS'), findsNothing);
  });

  testWidgets('editar: carga la cola y su horario; eliminar pide confirmación', (t) async {
    useDesktopSize(t);
    final e = env();
    await t.pumpWidget(host(e, id: 'q1'));
    await settle(t);
    expect(find.text('Editar cola'), findsOneWidget);
    expect(t.widget<EditableText>(find.byType(EditableText).at(0)).controller.text, 'Caja 1');
    expect(t.widget<EditableText>(find.byType(EditableText).at(3)).controller.text, '08:00');

    await t.tap(find.text('Eliminar cola'));
    await settle(t);
    expect(find.textContaining('Se archiva'), findsOneWidget);
    await t.tap(find.text('Cancelar').last);
    await settle(t);
    expect(e.queues.calls, isNot(contains('delete:q1')));

    await t.tap(find.text('Eliminar cola'));
    await settle(t);
    await t.tap(find.text('Eliminar cola').last);
    await settle(t);
    expect(e.queues.calls, contains('delete:q1'));
    expect(e.staff.audits, contains('cola.archivar'));
  });

  testWidgets('editar: guardar reemplaza el horario completo (PUT)', (t) async {
    useDesktopSize(t);
    final e = env();
    await t.pumpWidget(host(e, id: 'q1'));
    await settle(t);
    await t.enterText(find.byType(TextField).at(8), '40'); // tope diario
    await t.tap(find.text('Guardar cola'));
    await settle(t);
    expect(e.queues.lastSchedule!.dailyCapacity, 40);
    expect(e.queues.lastSchedule!.stations, 2);
    expect(e.queues.calls, contains('update:q1:Caja 1:null'));
  });
}
