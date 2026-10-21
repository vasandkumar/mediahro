import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/app.dart';
import 'package:mediahro/app/appearance.dart';
import 'package:mediahro/app/background_work_dispatcher.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/platform/platform_facades.dart';

import '../helpers.dart';

/// A facade whose `runs` counts how often it is listened to.
final class _Work implements BackgroundWorkFacade {
  _Work() {
    controller = StreamController<String>.broadcast(onListen: () => listens++);
  }

  late final StreamController<String> controller;
  int listens = 0;

  @override
  Stream<String> get runs => controller.stream;

  @override
  Future<void> schedulePeriodic(
    String id,
    Duration interval, {
    bool requiresNetwork = true,
    bool unmeteredOnly = false,
    bool requiresCharging = false,
  }) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> complete(String id, {required bool success}) async {}

  @override
  Future<bool> get available async => true;
}

void main() {
  testWidgets('ADR-049 the dispatcher listens before any widget is built', (
    tester,
  ) async {
    final store = await tester.runAsync(memoryStore);
    final work = _Work();
    final container = mediahroContainer(
      store!,
      overrides: [backgroundWorkProvider.overrideWithValue(work)],
    );
    addTearDown(() async {
      container.dispose();
      await work.controller.close();
    });
    expect(work.listens, 0);

    // What main() does before runApp: no widget exists yet.
    container.read(backgroundWorkDispatcherProvider);

    expect(work.listens, 1);
    expect(find.byType(MediahroApp), findsNothing);
  });

  testWidgets('ADR-049 showing the app from the container adds no listener', (
    tester,
  ) async {
    final store = await tester.runAsync(memoryStore);
    final work = _Work();
    final container = mediahroContainer(
      store!,
      overrides: [backgroundWorkProvider.overrideWithValue(work)],
    );
    addTearDown(() async {
      container.dispose();
      await work.controller.close();
    });
    final dispatcher = container.read(backgroundWorkDispatcherProvider);

    await tester.pumpWidget(mediahroApp(container));
    await tester.pumpAndSettle();

    expect(find.byType(MediahroApp), findsOneWidget);
    // The tree uses the same container: the same dispatcher, one listener.
    expect(container.read(backgroundWorkDispatcherProvider), same(dispatcher));
    expect(work.listens, 1);
  });

  testWidgets('CORE-007 the container serves the default appearance', (
    tester,
  ) async {
    final store = await tester.runAsync(memoryStore);
    final container = mediahroContainer(store!);
    addTearDown(container.dispose);
    expect(
      container.read(platformAppearanceProvider),
      const PlatformAppearance(),
    );
    await tester.pumpWidget(mediahroApp(container));
    await tester.pumpAndSettle();
    expect(
      container.read(platformAppearanceProvider),
      const PlatformAppearance(),
    );
  });
}
