import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon, {this.adminOnly = false});
  final String path;
  final String label;
  final QhIcons icon;
  final bool adminOnly;
}

const _operation = [
  _NavItem('/colas', 'Colas', QhIcons.queue),
  _NavItem('/en-vivo', 'En vivo', QhIcons.live),
  _NavItem('/historial', 'Historial', QhIcons.history),
];
const _admin = [
  _NavItem('/equipo', 'Equipo', QhIcons.user, adminOnly: true),
  _NavItem('/ajustes', 'Ajustes', QhIcons.settings, adminOnly: true),
];

/// Cabecera Ink de 48 px + sidebar Ink de 256 px + contenido sobre `background`.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final membership = ref.watch(activeMembershipProvider);
    final user = ref.watch(authUserProvider).value;
    final isAdmin = membership?.isAdmin ?? false;

    Widget item(_NavItem n) {
      final selected = location.startsWith(n.path);
      return Semantics(
        button: true,
        selected: selected,
        label: n.label,
        excludeSemantics: true,
        child: InkWell(
          onTap: () => context.go(n.path),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: selected ? c.sidebarActive : null,
              border: Border(left: BorderSide(color: selected ? c.brandMint : Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
            child: Row(children: [
              QhIcon(n.icon, size: 16, color: selected ? c.sidebarTextActive : c.sidebarText),
              const SizedBox(width: QhSpacing.s04),
              Text(n.label, style: QhText.body.copyWith(color: selected ? c.sidebarTextActive : c.sidebarText)),
            ]),
          ),
        ),
      );
    }

    Widget group(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(QhSpacing.s05, QhSpacing.s05, QhSpacing.s05, QhSpacing.s02),
          child: Text(t.toUpperCase(), style: QhText.label.copyWith(color: c.sidebarText.withValues(alpha: 0.7))),
        );

    return Scaffold(
      body: Column(children: [
        Container(
          height: QhSize.headerHeight,
          color: c.sidebarBg,
          padding: const EdgeInsets.symmetric(horizontal: QhSpacing.s05),
          child: Row(children: [
            const QhLogo(QhLogoKind.horizontalNegative, height: 22),
            const SizedBox(width: QhSpacing.s07),
            QhIcon(QhIcons.building, color: c.sidebarText),
            const SizedBox(width: QhSpacing.s03),
            Text(membership?.organization.name ?? '', style: QhText.body.copyWith(color: c.sidebarTextActive)),
            const SizedBox(width: QhSpacing.s03),
            Text('· ${membership?.role.label ?? ''}', style: QhText.caption.copyWith(color: c.sidebarText)),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: 'Cuenta',
              color: c.layer01,
              shape: const RoundedRectangleBorder(),
              onSelected: (v) async {
                if (v == 'out') {
                  ref.read(qhubConnectionProvider.notifier).disconnect();
                  await ref.read(staffRepositoryProvider).signOut();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(user?.email ?? '', style: QhText.caption)),
                const PopupMenuItem(value: 'out', child: Text('Cerrar sesión')),
              ],
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.interactive, shape: BoxShape.circle),
                child: Text(user?.initials ?? '?', style: QhText.label.copyWith(color: c.textOnColor)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Row(children: [
            Container(
              width: QhSize.sidebarWidth,
              color: c.sidebarBg,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                group('Operación'),
                for (final n in _operation) item(n),
                if (isAdmin) ...[group('Administración'), for (final n in _admin) item(n)],
                const Spacer(),
                const Padding(padding: EdgeInsets.all(QhSpacing.s05), child: Align(alignment: Alignment.centerLeft, child: LiveIndicator(onInk: true, label: 'Conectado'))),
              ]),
            ),
            Expanded(
              child: ColoredBox(
                color: c.background,
                child: Padding(padding: const EdgeInsets.all(QhSpacing.s07), child: child),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
