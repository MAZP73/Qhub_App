import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/setup_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/live/presentation/live_page.dart';
import '../features/qhub/domain/qhub_connection.dart';
import '../features/qhub/presentation/connect_page.dart';
import '../features/queues/presentation/queue_edit_page.dart';
import '../features/queues/presentation/queues_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/shell.dart';
import '../features/team/presentation/team_page.dart';
import 'providers.dart';

/// Decide a dónde va el usuario según su estado. Pura y testeable.
String? resolveRedirect({
  required String location,
  required bool authLoading,
  required bool signedIn,
  required bool membershipsLoading,
  required bool hasOrganization,
  required bool isAdmin,
  required bool connected,
}) {
  const authPages = {'/login', '/setup', '/connect', '/cargando'};
  if (authLoading) return location == '/cargando' ? null : '/cargando';
  if (!signedIn) return location == '/login' ? null : '/login';
  if (membershipsLoading) return location == '/cargando' ? null : '/cargando';
  if (!hasOrganization) return location == '/setup' ? null : '/setup';
  if (!connected) return location == '/connect' ? null : '/connect';
  if (authPages.contains(location) || location == '/') return '/colas';
  if (!isAdmin && (location.startsWith('/equipo') || location.startsWith('/ajustes'))) return '/colas';
  if (!isAdmin && location.startsWith('/colas/')) return '/colas';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  void bump(_, _) => refresh.value++;
  ref
    ..listen(authUserProvider, bump)
    ..listen(membershipsProvider, bump)
    ..listen(qhubConnectionProvider, bump)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/cargando',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authUserProvider);
      final mem = ref.read(membershipsProvider);
      return resolveRedirect(
        location: state.uri.path,
        authLoading: auth.isLoading && !auth.hasValue,
        signedIn: auth.value != null,
        membershipsLoading: mem.isLoading && !mem.hasValue,
        hasOrganization: (mem.value ?? const []).isNotEmpty,
        isAdmin: ref.read(activeMembershipProvider)?.isAdmin ?? false,
        connected: ref.read(qhubConnectionProvider) is QhubConnected,
      );
    },
    routes: [
      GoRoute(path: '/cargando', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupPage()),
      GoRoute(path: '/connect', builder: (_, _) => const ConnectPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/colas', builder: (_, _) => const QueuesPage(), routes: [
            GoRoute(path: 'nueva', builder: (_, _) => const QueueEditPage()),
            GoRoute(path: ':id', builder: (_, s) => QueueEditPage(queueId: s.pathParameters['id'])),
          ]),
          GoRoute(path: '/en-vivo', builder: (_, s) => LivePage(initialQueueId: s.uri.queryParameters['cola'])),
          GoRoute(path: '/historial', builder: (_, _) => const HistoryPage()),
          GoRoute(path: '/equipo', builder: (_, _) => const TeamPage()),
          GoRoute(path: '/ajustes', builder: (_, _) => const SettingsPage()),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: QhLogo(QhLogoKind.horizontal, height: 32)));
}
