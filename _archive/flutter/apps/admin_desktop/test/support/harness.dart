import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/app/providers.dart';
import 'package:qhub_admin/features/staff/domain/staff.dart';
import 'package:qhub_ui/qhub_ui.dart';

import 'fakes.dart';

class Env {
  Env({
    FakeStaffRepository? staff,
    FakeAuthRepository? auth,
    FakeQueueRepository? queues,
    FakeTicketRepository? tickets,
    FakeRealtime? realtime,
  })  : staff = staff ?? FakeStaffRepository(),
        auth = auth ?? FakeAuthRepository(),
        queues = queues ?? FakeQueueRepository(),
        tickets = tickets ?? FakeTicketRepository(const []),
        realtime = realtime ?? FakeRealtime();

  final FakeStaffRepository staff;
  final FakeAuthRepository auth;
  final FakeQueueRepository queues;
  final FakeTicketRepository tickets;
  final FakeRealtime realtime;
  final store = MemoryCredentialStore();

  List<Override> get overrides => [
        envProvider.overrideWithValue(testEnv),
        staffRepositoryProvider.overrideWithValue(staff),
        authRepositoryProvider.overrideWithValue(auth),
        queueRepositoryProvider.overrideWithValue(queues),
        ticketRepositoryProvider.overrideWithValue(tickets),
        realtimeRepositoryProvider.overrideWithValue(realtime),
        healthRepositoryProvider.overrideWithValue(FakeHealth()),
        credentialStoreProvider.overrideWithValue(store),
      ];
}

void useDesktopSize(WidgetTester t, {double w = 1600, double h = 1400}) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// `pumpAndSettle` no sirve con el pulso "en vivo" (animación infinita).
Future<void> settle(WidgetTester t, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Widget themed(Widget child, Env env) => ProviderScope(
      retry: (_, _) => null,
      overrides: env.overrides,
      child: MaterialApp(theme: QhTheme.light(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child))),
    );

const adminMembership = Membership(organization: org, role: OrgRole.admin);
const agentMembership = Membership(organization: org, role: OrgRole.agente);
const ana = StaffUser(id: 'u1', email: 'ana@x.co', displayName: 'Ana Gómez');
