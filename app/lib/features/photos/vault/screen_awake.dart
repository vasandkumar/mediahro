import 'dart:async';

import 'package:mediahro/platform/display.dart';

/// Keeps the screen on while the vault does long work or plays something
/// (PRIV-007): a screen that goes off sends the app to the background, which
/// locks the vault and stops the work. Holds count: the screen may sleep
/// again when the last one is released. Take the facade from the provider
/// early and keep it here; a provider cannot be read once a screen is gone.
final class ScreenAwake {
  ScreenAwake(this._display);

  final DisplayFacade? _display;
  int _holds = 0;

  /// Asks for the screen to stay on. Pair with [release].
  Future<void> hold() async {
    if (_holds++ == 0) await _set(on: true);
  }

  /// Gives one hold back; the screen may sleep when none is left.
  Future<void> release() async {
    if (_holds == 0) return;
    if (--_holds == 0) await _set(on: false);
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
