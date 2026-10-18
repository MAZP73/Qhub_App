import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qhub_ui/qhub_ui.dart';

import 'providers.dart';
import 'router.dart';

class QhubAdminApp extends ConsumerWidget {
  const QhubAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Qhub · Administración',
        debugShowCheckedModeBanner: false,
        theme: QhTheme.light(),
        darkTheme: QhTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(routerProvider),
        locale: const Locale('es'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
      );
}
