import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mediahro/app/capabilities.dart';

/// One key combination (CORE-009). `primary` is Ctrl on Android and
/// Windows and Cmd on Apple platforms, so one default serves every
/// platform's convention. A spec is either a physical-layout-independent
/// logical key with modifiers, or a typed character (`?`).
@immutable
final class KeySpec {
  const KeySpec(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.control = false,
  }) : character = null;

  const KeySpec.character(String this.character)
    : key = null,
      primary = false,
      shift = false,
      alt = false,
      control = false;

  /// Builds a spec from a key-down event in the remapping dialog.
  static KeySpec? fromEvent(KeyEvent event, AppPlatform platform) {
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return null;
    final keys = HardwareKeyboard.instance;
    final apple = platform == AppPlatform.ios || platform == AppPlatform.macos;
    return KeySpec(
      key,
      primary: apple ? keys.isMetaPressed : keys.isControlPressed,
      control: apple && keys.isControlPressed,
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
    );
  }

  final LogicalKeyboardKey? key;
  final String? character;
  final bool primary;
  final bool shift;
  final bool alt;

  /// The Control key on Apple platforms (where [primary] is Cmd).
  final bool control;

  ShortcutActivator activator(AppPlatform platform) {
    if (character != null) return CharacterActivator(character!);
    final apple = platform == AppPlatform.ios || platform == AppPlatform.macos;
    return SingleActivator(
      key!,
      control: apple ? control : primary,
      meta: apple && primary,
      shift: shift,
      alt: alt,
    );
  }

  /// Stable text form stored in settings: `primary+shift+<keyId>` or
  /// `char:?`.
  String encode() {
    if (character != null) return 'char:$character';
    return [
      if (primary) 'primary',
      if (control) 'control',
      if (shift) 'shift',
      if (alt) 'alt',
      key!.keyId.toString(),
    ].join('+');
  }

  static KeySpec? decode(String s) {
    if (s.startsWith('char:') && s.length > 5) {
      return KeySpec.character(s.substring(5));
    }
    final parts = s.split('+');
    final id = int.tryParse(parts.last);
    if (id == null) return null;
    final mods = parts.sublist(0, parts.length - 1).toSet();
    if (mods.difference({'primary', 'control', 'shift', 'alt'}).isNotEmpty) {
      return null;
    }
    return KeySpec(
      LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id),
      primary: mods.contains('primary'),
      control: mods.contains('control'),
      shift: mods.contains('shift'),
      alt: mods.contains('alt'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeySpec &&
      other.key == key &&
      other.character == character &&
      other.primary == primary &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, character, primary, control, shift, alt);

  @override
  String toString() => 'KeySpec(${encode()})';

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };
}
