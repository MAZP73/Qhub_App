import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qhub_ui/qhub_ui.dart';

import '../../../app/providers.dart';
import '../../../app/widgets.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.qh;
    final user = ref.watch(authUserProvider).value;
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      body: Column(children: [
        QhAppBar(title: 'Perfil', leading: QhIconButton(icon: QhIcons.chevronLeft, label: 'Atrás', onPressed: () => context.pop())),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(QhSpacing.s05), children: [
            Text(user?.displayName ?? 'Tu cuenta', style: QhText.h3),
            Text(user?.email ?? '', style: QhText.body.copyWith(color: c.textSecondary)),
            const SizedBox(height: QhSpacing.s06),
            QhSelect<ThemeMode>(
              label: 'Tema',
              value: mode,
              items: const {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
              onChanged: (v) => ref.read(themeModeProvider.notifier).set(v ?? mode),
            ),
            const SizedBox(height: QhSpacing.s07),
            QhButton(
              label: 'Cerrar sesión',
              icon: QhIcons.logout,
              kind: QhButtonKind.secondary,
              size: QhButtonSize.lg,
              block: true,
              onPressed: () async {
                final ok = await qhConfirm(context, title: 'Cerrar sesión', message: 'Tendrás que volver a iniciar sesión para ver tus turnos.', confirmLabel: 'Cerrar sesión', danger: false);
                if (ok && context.mounted) await ref.read(userRepositoryProvider).signOut();
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
