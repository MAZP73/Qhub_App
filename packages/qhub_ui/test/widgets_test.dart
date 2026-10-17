import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_api_client/qhub_api_client.dart' show Slot, TicketStatus;
import 'package:qhub_ui/qhub_ui.dart';

Widget host(Widget child, {bool dark = false}) => MaterialApp(
      theme: QhTheme.light(),
      darkTheme: QhTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: Center(child: SingleChildScrollView(child: child))),
    );

double luminance(Color c) => c.computeLuminance();
double contrast(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('tokens', () {
    test('los dos temas tienen los mismos tokens y difieren en superficie', () {
      expect(QhColors.light.background, isNot(QhColors.dark.background));
      expect(QhColors.light.brandIndigo, QhColors.dark.brandIndigo);
    });

    test('contraste AA del texto principal en ambos temas', () {
      expect(contrast(QhColors.light.textPrimary, QhColors.light.layer01), greaterThan(4.5));
      expect(contrast(QhColors.dark.textPrimary, QhColors.dark.layer01), greaterThan(4.5));
      expect(contrast(QhColors.light.textOnColor, QhColors.light.interactive), greaterThan(4.5));
      expect(contrast(QhColors.light.textOnAccent, QhColors.light.stateWaiting), greaterThan(4.5));
      expect(contrast(QhColors.light.textOnAccent, QhColors.light.stateNoshow), greaterThan(4.5));
    });

    test('alias resueltos y escalas 8px', () {
      expect(QhColors.light.interactive, QhColors.light.brandIndigo);
      expect(QhSpacing.s03, 8);
      expect(QhSize.controlMd, 40);
      expect(QhSize.controlLg, 48);
      expect(QhRadius.sm, 2);
    });

    test('el overlay RGBA se convierte a ARGB', () {
      expect(QhColors.light.overlay.a, closeTo(0x99 / 255, 0.01));
    });
  });

  group('widgets', () {
    testWidgets('TurnBadge muestra palabra para cada estado (nunca solo color)', (t) async {
      await t.pumpWidget(host(Column(children: [for (final s in TicketStatus.values) TurnBadge(s)])));
      for (final label in ['En espera', 'Atendiendo', 'Finalizado', 'Cancelado', 'No-show']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('TurnNumber formatea A-023', (t) async {
      await t.pumpWidget(host(const TurnNumber(number: 23, prefix: 'E')));
      expect(find.text('E-023'), findsOneWidget);
    });

    testWidgets('QhButton dispara onPressed y respeta disabled/loading', (t) async {
      var taps = 0;
      await t.pumpWidget(host(Column(children: [
        QhButton(label: 'Llamar siguiente', onPressed: () => taps++),
        const QhButton(label: 'Deshabilitado', onPressed: null),
        QhButton(label: 'Cargando', onPressed: () => taps += 100, loading: true),
      ])));
      await t.tap(find.text('Llamar siguiente'));
      await t.tap(find.text('Deshabilitado'), warnIfMissed: false);
      await t.tap(find.text('Cargando'), warnIfMissed: false);
      expect(taps, 1);
    });

    testWidgets('QhTextField muestra el error con mensaje', (t) async {
      await t.pumpWidget(host(const QhTextField(label: 'Correo', errorText: 'Escribe un correo válido.')));
      expect(find.text('Correo'), findsOneWidget);
      expect(find.text('Escribe un correo válido.'), findsOneWidget);
    });

    testWidgets('QhTextField oculta/muestra contraseña', (t) async {
      await t.pumpWidget(host(const QhTextField(label: 'Contraseña', obscure: true)));
      expect(tester(t).obscureText, isTrue);
      await t.tap(find.text('Mostrar'));
      await t.pump();
      expect(tester(t).obscureText, isFalse);
    });

    testWidgets('EmptyState', (t) async {
      await t.pumpWidget(host(const SizedBox(height: 400, child: EmptyState(title: 'Crea tu primera cola', message: 'Aún no tienes colas.'))));
      expect(find.text('Crea tu primera cola'), findsOneWidget);
    });

    testWidgets('QueueTile con datos y cerrada', (t) async {
      await t.pumpWidget(host(Column(children: [
        const SizedBox(width: 360, child: QueueTile(name: 'Caja 1', waiting: 4, serving: 1, currentNumber: 12, prefix: 'C')),
        const SizedBox(width: 360, child: QueueTile(name: 'Caja 2', waiting: 0, serving: 0, closed: true)),
      ])));
      expect(find.text('C-012'), findsOneWidget);
      expect(find.text('Cerrada'), findsOneWidget);
      expect(find.text('Sin turno en atención'), findsOneWidget);
    });

    testWidgets('LiveIndicator', (t) async {
      await t.pumpWidget(host(const LiveIndicator(live: false)));
      expect(find.text('Sin conexión'), findsOneWidget);
    });

    testWidgets('modo oscuro compila sin errores', (t) async {
      await t.pumpWidget(host(const TurnBadge(TicketStatus.noShow), dark: true));
      expect(find.text('No-show'), findsOneWidget);
    });

    testWidgets('QhDateSlotPicker: días deshabilitados, franja llena y selección', (t) async {
      final slots = [
        Slot(start: DateTime.utc(2026, 10, 20, 15), end: DateTime.utc(2026, 10, 20, 15, 30), capacity: 6, taken: 6, available: 0),
        Slot(start: DateTime.utc(2026, 10, 20, 16), end: DateTime.utc(2026, 10, 20, 16, 30), capacity: 6, taken: 5, available: 1),
      ];
      Slot? picked;
      DateTime? day;
      await t.pumpWidget(host(SizedBox(
        width: 380,
        child: QhDateSlotPicker(
          month: DateTime(2026, 10),
          selectedDate: DateTime(2026, 10, 20),
          enabledWeekdays: const {1, 2, 3, 4, 5},
          firstDate: DateTime(2026, 10, 1),
          lastDate: DateTime(2026, 10, 31),
          slots: slots,
          selectedSlot: null,
          onDateChanged: (d) => day = d,
          onMonthChanged: (_) {},
          onSlotChanged: (s) => picked = s,
        ),
      )));
      expect(find.text('Llena'), findsOneWidget);
      expect(find.text('1 cupos'), findsOneWidget);
      await t.tap(find.text('Llena'), warnIfMissed: false);
      expect(picked, isNull); // llena: no se puede elegir
      await t.tap(find.text('1 cupos'));
      expect(picked?.available, 1);
      await t.tap(find.text('21')); // miércoles hábil
      expect(day?.day, 21);
      day = null;
      await t.tap(find.text('24')); // sábado: deshabilitado
      expect(day, isNull);
    });
  });
}

EditableText tester(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText));
