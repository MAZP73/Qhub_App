import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/env.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
    final env = AppEnv.fromMap(dotenv.env);
    await Supabase.initialize(url: env.supabaseUrl, publishableKey: env.supabaseKey);
    runApp(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        envProvider.overrideWithValue(env),
        supabaseClientProvider.overrideWithValue(Supabase.instance.client),
      ],
      child: const QhubAdminApp(),
    ));
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('No se pudo iniciar: $e'))))));
  }
}
