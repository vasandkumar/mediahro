import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// The app's router once the widget tree has built it (set by `MediahroApp`).
/// Null before the first frame and in an engine with no screen.
final appRouterProvider = NotifierProvider<AppRouterHolder, GoRouter?>(
  AppRouterHolder.new,
);

class AppRouterHolder extends Notifier<GoRouter?> {
  @override
  GoRouter? build() => null;

  // A setter would hide the Notifier contract; the app calls this once.
  // ignore: use_setters_to_change_properties
  void set(GoRouter? router) => state = router;
}

/// Acts on what other apps hand to Mediahro.
abstract interface class IncomingHandler {
  /// Opens files and links from Open with, Share or a link (CORE-003, SYS-004).
  Future<void> openUris(List<Uri> uris);

  /// Runs an app intent or shortcut (SYS-003).
  void runIntent(AppIntent intent);
}

/// Receives open requests and intents from the OS from the first moment of the
/// process and hands them to an [IncomingHandler] once the app is ready: what
/// arrives earlier waits in order and is delivered once.
final class IncomingRouter {
  IncomingRouter({required this.opens, required this.intents});

  /// Files and links from Open with and Share.
  final Stream<List<Uri>> opens;

  /// App intents and shortcuts.
  final Stream<AppIntent> intents;
  final _waiting = Queue<void Function(IncomingHandler)>();
  StreamSubscription<List<Uri>>? _opensSub;
  StreamSubscription<AppIntent>? _intentsSub;
  IncomingHandler? _handler;
  final _cleanups = <void Function()>[];

  /// Runs [action] when this router is disposed.
  void onDispose(void Function() action) => _cleanups.add(action);

  /// Starts listening. Does nothing when already started.
  void start() {
    _opensSub ??= opens.listen(
      (uris) => _deliver((h) => unawaited(_guard(h.openUris(uris)))),
      // A facade whose stream fails must not take the app down.
      onError: (Object _) {},
    );
    _intentsSub ??= intents.listen(
      (intent) => _deliver((h) => h.runIntent(intent)),
      onError: (Object _) {},
    );
  }

  /// The app is ready: everything waiting is delivered, once, in order.
  void attach(IncomingHandler handler) {
    _handler = handler;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst()(handler);
    }
  }

  /// The app is not ready (its screen went away): new requests wait again.
  void detach() => _handler = null;

  void _deliver(void Function(IncomingHandler) action) {
    final handler = _handler;
    if (handler == null) {
      _waiting.add(action);
    } else {
      action(handler);
    }
  }

  Future<void> _guard(Future<void> work) async {
    try {
      await work;
    } on Object {
      // One bad hand-over must not stop the next.
    }
  }

  Future<void> dispose() async {
    await _opensSub?.cancel();
    await _intentsSub?.cancel();
    _opensSub = null;
    _intentsSub = null;
    _waiting.clear();
    _handler = null;
    for (final action in _cleanups) {
      action();
    }
    _cleanups.clear();
  }
}

/// Starts receiving what other apps hand to Mediahro from [container] and
/// delivers it with [handlerFor] once `appRouterProvider` has a router.
/// Called from `main` before the first frame, so a cold start by "Open with"
/// loses nothing. A platform without the facades receives nothing.
IncomingRouter startIncoming(
  ProviderContainer container, {
  required IncomingHandler Function(ProviderContainer, GoRouter) handlerFor,
}) {
  final router = IncomingRouter(
    opens: _openRequests(container),
    intents: _incomingIntents(container),
  )..start();
  final link = container.listen<GoRouter?>(appRouterProvider, (_, next) {
    if (next == null) {
      router.detach();
    } else {
      router.attach(handlerFor(container, next));
    }
  }, fireImmediately: true);
  return router..onDispose(link.close);
}

Stream<List<Uri>> _openRequests(ProviderContainer container) {
  try {
    return container.read(systemIntegrationProvider).openRequests;
  } on Object {
    // No open-with on this platform or build.
    return const Stream.empty();
  }
}

Stream<AppIntent> _incomingIntents(ProviderContainer container) {
  try {
    return container.read(intentsProvider).incoming;
  } on Object {
    // No shortcuts on this platform or build.
    return const Stream.empty();
  }
}
