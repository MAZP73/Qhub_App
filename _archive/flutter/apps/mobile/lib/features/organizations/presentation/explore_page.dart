import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/widgets.dart';
import '../../tickets/presentation/providers.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});
  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  var _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qh;
    final orgs = ref.watch(orgSearchProvider(_query));
    final favorites = ref.watch(favoritesProvider).value ?? const <String>{};

    return Column(children: [
      const QhAppBar(title: 'Elige dónde'),
      Padding(
        padding: const EdgeInsets.all(QhSpacing.s05),
        child: QhTextField(label: 'Buscar', hint: 'Organización, ciudad o dirección', onChanged: _onChanged),
      ),
      Expanded(
        child: orgs.when(
          loading: () => const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Column(children: [Skeleton(height: 64), SizedBox(height: 8), Skeleton(height: 64), SizedBox(height: 8), Skeleton(height: 64)])),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(orgSearchProvider(_query))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                title: _query.isEmpty ? 'Aún no hay organizaciones' : 'Sin resultados',
                message: _query.isEmpty ? 'Cuando una organización se publique en Qhub la verás aquí.' : 'Prueba con otro nombre o ciudad.',
              );
            }
            final sorted = [...list]..sort((a, b) => (favorites.contains(b.id) ? 1 : 0) - (favorites.contains(a.id) ? 1 : 0));
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(orgSearchProvider(_query)),
              child: ListView.builder(
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final o = sorted[i];
                  return ListRow(
                    leading: OrgMark(o.mark),
                    title: Text(o.name, style: QhText.body.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary)),
                    subtitles: [if (o.location.isNotEmpty) o.location],
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (favorites.contains(o.id)) Padding(padding: const EdgeInsets.only(right: 8), child: Text('Favorita', style: QhText.caption.copyWith(color: c.link))),
                      const QhIcon(QhIcons.chevronRight),
                    ]),
                    onTap: () => context.push('/org/${o.id}'),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}
