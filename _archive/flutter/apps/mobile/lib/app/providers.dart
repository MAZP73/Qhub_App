import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart' hide Queue;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../features/auth/data/supabase_user_repository.dart';
import '../features/auth/domain/user.dart';
import '../features/gateway/data/proxy_adapter.dart';
import '../features/gateway/data/supabase_invoker.dart';
import '../features/gateway/domain/gateway.dart';
import '../features/history/data/supabase_history_repository.dart';
import '../features/history/domain/history.dart';
import '../features/organizations/data/supabase_organization_repository.dart';
import '../features/organizations/domain/organizations.dart';
import 'env.dart';

export 'package:qhub_api_client/qhub_api_client.dart' show Queue;

final envProvider = Provider<AppEnv>((_) => throw UnimplementedError('envProvider sin override'));
final supabaseClientProvider = Provider<SupabaseClient>((_) => throw UnimplementedError('supabaseClientProvider sin override'));

final userRepositoryProvider = Provider<UserRepository>((ref) => SupabaseUserRepository(ref.watch(supabaseClientProvider)));
final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) => SupabaseOrganizationRepository(ref.watch(supabaseClientProvider)));
final historyRepositoryProvider = Provider<HistoryRepository>((ref) => SupabaseHistoryRepository(ref.watch(supabaseClientProvider)));
final gatewayProvider = Provider<QhubGateway>((ref) => ProxyQhubGateway(supabaseProxyInvoker(ref.watch(supabaseClientProvider))));

final authUserProvider = StreamProvider<AppUser?>((ref) => ref.watch(userRepositoryProvider).authChanges());

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode m) => state = m;
}

/// Atajos tipados para no repetir `ref.watch(gatewayProvider).tickets(org)`.
extension GatewayRefX on Ref {
  QueueRepository queuesOf(String org) => read(gatewayProvider).queues(org);
  TicketRepository ticketsOf(String org) => read(gatewayProvider).tickets(org);
  NotificationRepository notificationsOf(String org) => read(gatewayProvider).notifications(org);
}
