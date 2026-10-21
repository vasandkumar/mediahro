import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Keeps the screen on while the vault does long work or plays something
/// (PRIV-007): a screen that goes off sends the app to the background, which
/// locks the vault and stops the work. Holds are counted across the app (one
/// [ScreenAwake] from [screenAwakeProvider]), so a move, an add and a player
/// open at once do not switch each other off; the screen may sleep when the
/// last [ScreenHold] is released.
final class ScreenAwake {
  ScreenAwake(this._display);

  final DisplayFacade? _display;
  int _holds = 0;

  /// Asks for the screen to stay on until the returned hold is released.
  ScreenHold hold() {
    if (_holds++ == 0) unawaited(_set(on: true));
    return ScreenHold._(this);
  }

  void _release() {
    if (_holds == 0) return;
    if (--_holds == 0) unawaited(_set(on: false));
  }

  /// How many holds are on (for tests).
  int get holds => _holds;

  Future<void> _set({required bool on}) async {
    try {
      await _display?.keepScreenOn(on: on);
    } on Object {
      // No display facade here: the screen may time out.
    }
  }
}

/// One claim on the screen staying on. Releasing twice does nothing, so a
/// hold can never take another one's place.
final class ScreenHold {
  ScreenHold._(this._owner);

  final ScreenAwake _owner;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _owner._release();
  }
}

/// The app-wide counter of vault screen holds.
final Provider<ScreenAwake> screenAwakeProvider = Provider<ScreenAwake>((ref) {
  DisplayFacade? display;
  try {
    display = ref.watch(displayProvider);
  } on Object {
    display = null;
  }
  return ScreenAwake(display);
});
