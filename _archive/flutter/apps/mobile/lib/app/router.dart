import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../features/auth/presentation/auth_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/organizations/presentation/explore_page.dart';
import '../features/organizations/presentation/org_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/shell/presentation/shell.dart';
import '../features/tickets/presentation/my_turn_page.dart';
import '../features/tickets/presentation/take_turn_page.dart';
import 'providers.dart';

/// Pura y testeable: a dónde va el usuario según su sesión.
String? resolveRedirect({required String location, required bool authLoading, required bool signedIn}) {
  if (authLoading) return location == '/cargando' ? null : '/cargando';
  if (!signedIn) return location == '/acceso' ? null : '/acceso';
  if (location == '/acceso' || location == '/cargando' || location == '/') return '/turno';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authUserProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/cargando',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authUserProvider);
      return resolveRedirect(location: state.uri.path, authLoading: auth.isLoading && !auth.hasValue, signedIn: auth.value != null);
    },
    routes: [
      GoRoute(path: '/cargando', builder: (_, _) => const Scaffold(body: Center(child: QhLogo(QhLogoKind.horizontal, height: 32)))),
      GoRoute(path: '/acceso', builder: (_, _) => const AuthPage()),
      ShellRoute(
        builder: (context, state, child) => MobileShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/turno', builder: (_, _) => const MyTurnPage()),
          GoRoute(path: '/explorar', builder: (_, _) => const ExplorePage()),
          GoRoute(path: '/avisos', builder: (_, _) => const NotificationsPage()),
          GoRoute(path: '/historial', builder: (_, _) => const HistoryPage()),
        ],
      ),
      GoRoute(path: '/perfil', builder: (_, _) => const ProfilePage()),
      GoRoute(path: '/org/:id', builder: (_, s) => OrgPage(organizationId: s.pathParameters['id']!)),
      GoRoute(
        path: '/org/:id/cola/:qid',
        builder: (_, s) => TakeTurnPage(organizationId: s.pathParameters['id']!, queueId: s.pathParameters['qid']!),
      ),
    ],
  );
});
