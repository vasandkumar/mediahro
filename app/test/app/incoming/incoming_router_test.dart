import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/incoming/incoming_router.dart';
import 'package:mediahro/platform/platform_facades.dart';

final class _Handler implements IncomingHandler {
  final seen = <Object>[];

  @override
  Future<void> openUris(List<Uri> uris) async => seen.add(uris);

  @override
  void runIntent(AppIntent intent) => seen.add(intent);
}

final class _Throwing implements IncomingHandler {
  @override
  Future<void> openUris(List<Uri> uris) async => throw StateError('boom');

  @override
  void runIntent(AppIntent intent) {}
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late StreamController<List<Uri>> opens;
  late StreamController<AppIntent> intents;
  late IncomingRouter router;

  setUp(() {
    opens = StreamController<List<Uri>>.broadcast();
    intents = StreamController<AppIntent>.broadcast();
    router = IncomingRouter(opens: opens.stream, intents: intents.stream)
      ..start();
  });

  tearDown(() async {
    await router.dispose();
    await opens.close();
    await intents.close();
  });

  final a = [Uri.parse('content://media/1')];
  final b = [Uri.parse('content://media/2')];
  const open = AppIntent(AppIntentKind.openMode, argument: 'music');

  test(
    'SYS-004 what arrives before the app is ready waits, in order',
    () async {
      opens.add(a);
      intents.add(open);
      opens.add(b);
      await settle();
      final handler = _Handler();

      router.attach(handler);
      await settle();

      expect(handler.seen, [a, open, b]);
    },
  );

  test('SYS-004 a queued request is delivered once', () async {
    opens.add(a);
    await settle();
    final first = _Handler();
    router.attach(first);
    await settle();
    final second = _Handler();
    router.attach(second);
    await settle();

    expect(first.seen, [a]);
    expect(second.seen, isEmpty);
  });

  test(
    'SYS-004 after the app is ready requests are delivered at once',
    () async {
      final handler = _Handler();
      router.attach(handler);
      opens.add(a);
      intents.add(open);
      await settle();
      expect(handler.seen, [a, open]);
    },
  );

  test('SYS-004 when the screen goes away new requests wait again', () async {
    final handler = _Handler();
    router
      ..attach(handler)
      ..detach();
    opens.add(a);
    await settle();
    expect(handler.seen, isEmpty);
    router.attach(handler);
    await settle();
    expect(handler.seen, [a]);
  });

  test('SYS-004 a handler that fails does not stop the next request', () async {
    router.attach(_Throwing());
    opens.add(a);
    await settle();
    final handler = _Handler();
    router.attach(handler);
    opens.add(b);
    await settle();
    expect(handler.seen, [b]);
  });

  test('SYS-004 start twice listens once', () async {
    router.start();
    final handler = _Handler();
    router.attach(handler);
    opens.add(a);
    await settle();
    expect(handler.seen, [a]);
  });

  group('startIncoming', () {
    test(
      'requests that come before the router exists are delivered when it does',
      () async {
        final fakeOpens = StreamController<List<Uri>>.broadcast();
        final fakeIntents = StreamController<AppIntent>.broadcast();
        addTearDown(() async {
          await fakeOpens.close();
          await fakeIntents.close();
        });
        final container = ProviderContainer(
          overrides: [
            systemIntegrationProvider.overrideWithValue(
              _System(fakeOpens.stream),
            ),
            intentsProvider.overrideWithValue(_Intents(fakeIntents.stream)),
          ],
        );
        addTearDown(container.dispose);
        final handler = _Handler();
        final incoming = startIncoming(
          container,
          handlerFor: (_, _) => handler,
        );
        addTearDown(incoming.dispose);

        fakeOpens.add(a);
        fakeIntents.add(open);
        await settle();
        expect(handler.seen, isEmpty);

        final go = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => throw UnimplementedError()),
          ],
        );
        container.read(appRouterProvider.notifier).set(go);
        await settle();
        expect(handler.seen, [a, open]);

        container.read(appRouterProvider.notifier).set(null);
        fakeOpens.add(b);
        await settle();
        expect(handler.seen, [a, open], reason: 'detached: waits');
      },
    );

    test(
      'a platform without the facades receives nothing and does not fail',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final incoming = startIncoming(
          container,
          handlerFor: (_, _) => _Handler(),
        );
        await incoming.dispose();
      },
    );
  });
}

final class _System implements SystemIntegrationFacade {
  _System(this.openRequests);

  @override
  final Stream<List<Uri>> openRequests;

  @override
  Future<void> showDefaultAppGuidance() async {}

  @override
  Future<void> setAlwaysOnTop({required bool enabled}) async {}

  @override
  Future<WindowFrame?> windowFrame() async => null;

  @override
  Future<void> setWindowFrame(WindowFrame frame) async {}

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;
}

final class _Intents implements IntentsFacade {
  _Intents(this.incoming);

  @override
  final Stream<AppIntent> incoming;

  @override
  Future<void> publishShortcuts(List<AppShortcut> shortcuts) async {}
}
