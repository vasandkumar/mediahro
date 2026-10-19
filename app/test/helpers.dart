import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/router.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// A loaded in-memory settings store (no disk in widget tests).
Future<SettingsStore> memoryStore([Map<String, Object?>? values]) =>
    SettingsStore.open(
      MemorySettingsPersistence(
        values == null ? null : SettingsDocument(values: values).toJson(),
      ),
      null,
    );

/// Pumps the full app at [size] (logical pixels).
///
/// Pick the platform family with `variant: TargetPlatformVariant.only(...)`
/// on the test (Android → Material, iOS/macOS → Apple, Windows → Fluent).
/// Without a router the app builds its own, which
/// exercises last-mode restore.
Future<SettingsStore> pumpApp(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Locale? locale,
  String? initialLocation = '/video',
  SettingsStore? settings,
  double? textScale,
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  if (locale != null) {
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final store =
      settings ??
      await tester.runAsync(memoryStore) ??
      (throw StateError('store'));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(store), ...overrides],
      child: MediahroApp(
        router: initialLocation == null
            ? null
            : buildRouter(initialLocation: initialLocation),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}
