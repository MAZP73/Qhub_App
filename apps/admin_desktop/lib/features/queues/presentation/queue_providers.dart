import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_api_client/qhub_api_client.dart';

import '../../../app/providers.dart';

final queuesProvider = FutureProvider.autoDispose<List<Queue>>((ref) async {
  final res = await ref.watch(queueRepositoryProvider).list();
  return res.getOrThrow();
});

final queueLimitProvider = FutureProvider.autoDispose<QueueLimit>((ref) async {
  final res = await ref.watch(queueRepositoryProvider).limit();
  return res.getOrThrow();
});

final queueStateProvider = FutureProvider.autoDispose.family<QueueState, String>((ref, id) async {
  final res = await ref.watch(queueRepositoryProvider).state(id);
  return res.getOrThrow();
});

final queueScheduleProvider = FutureProvider.autoDispose.family<Schedule, String>((ref, id) async {
  final res = await ref.watch(queueRepositoryProvider).schedule(id);
  return res.getOrThrow();
});

/// Prefijos de turno (`A`, `E`…) guardados en el Supabase del escritorio.
final queuePrefixesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final org = ref.watch(activeMembershipProvider)?.organization.id;
  if (org == null) return const {};
  final res = await ref.watch(staffRepositoryProvider).queuePrefixes(org);
  return res.valueOrNull ?? const {};
});
