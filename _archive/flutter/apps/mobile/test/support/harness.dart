import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_mobile/app/app.dart';

import 'fakes.dart';

void usePhone(WidgetTester t) {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> settle(WidgetTester t, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpApp(WidgetTester t, Env env) async {
  usePhone(t);
  await t.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: env.overrides, child: const QhubApp()));
  await settle(t);
}
