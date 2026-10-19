import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';

/// Pumps the full app at [size] (logical pixels).
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Locale? locale,
  String initialLocation = '/video',
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      child: MediahroApp(router: buildRouter(initialLocation: initialLocation)),
    ),
  );
  await tester.pumpAndSettle();
}
