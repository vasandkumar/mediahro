import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/key_spec.dart';
import 'package:mediahro/app/shortcuts/shortcut_bindings.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';

/// Binds handlers to shortcut actions for one scope (CORE-009). Keys come
/// from the user's remapping, never from the caller:
///
/// ```dart
/// ShortcutScopeWidget(
///   scope: ShortcutScope.player,
///   handlers: {'player.playPause': engine.togglePause},
///   child: player,
/// )
/// ```
///
/// Typed characters (such as `?`) are ignored while a text field has focus
/// so they reach the field.
class ShortcutScopeWidget extends ConsumerWidget {
  const ShortcutScopeWidget({
    required this.scope,
    required this.handlers,
    required this.child,
    super.key,
  });

  final ShortcutScope scope;
  final Map<String, VoidCallback> handlers;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(shortcutBindingsProvider);
    return Shortcuts(
      shortcuts: bindings.shortcutsFor(scope, handlers.keys.toSet()),
      child: Actions(
        actions: {ShortcutIntent: _ShortcutAction(handlers)},
        child: child,
      ),
    );
  }
}

class _ShortcutAction extends ContextAction<ShortcutIntent> {
  _ShortcutAction(this.handlers);

  final Map<String, VoidCallback> handlers;

  static bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  @override
  bool isEnabled(ShortcutIntent intent, [BuildContext? context]) =>
      handlers.containsKey(intent.actionId) && !_typing;

  @override
  bool consumesKey(ShortcutIntent intent) => !_typing;

  @override
  Object? invoke(ShortcutIntent intent, [BuildContext? context]) {
    handlers[intent.actionId]?.call();
    return null;
  }
}

/// Human-readable key label in the platform's convention: `⌘⇧S` on Apple,
/// `Ctrl+Shift+S` elsewhere.
String keyLabel(KeySpec spec, AppPlatform platform, AppLocalizations l10n) {
  if (spec.character != null) return spec.character!;
  final apple = platform == AppPlatform.ios || platform == AppPlatform.macos;
  final key = _keyName(spec.key!, l10n);
  if (apple) {
    return [
      if (spec.control) '⌃',
      if (spec.alt) '⌥',
      if (spec.shift) '⇧',
      if (spec.primary) '⌘',
      key,
    ].join();
  }
  return [
    if (spec.primary || spec.control) l10n.appKeyCtrl,
    if (spec.alt) l10n.appKeyAlt,
    if (spec.shift) l10n.appKeyShift,
    key,
  ].join('+');
}

String _keyName(LogicalKeyboardKey k, AppLocalizations l10n) {
  if (k == LogicalKeyboardKey.space) return l10n.appKeySpace;
  if (k == LogicalKeyboardKey.escape) return l10n.appKeyEscape;
  if (k == LogicalKeyboardKey.backspace) return l10n.appKeyBackspace;
  if (k == LogicalKeyboardKey.enter) return l10n.appKeyEnter;
  if (k == LogicalKeyboardKey.tab) return l10n.appKeyTab;
  if (k == LogicalKeyboardKey.arrowLeft) return '←';
  if (k == LogicalKeyboardKey.arrowRight) return '→';
  if (k == LogicalKeyboardKey.arrowUp) return '↑';
  if (k == LogicalKeyboardKey.arrowDown) return '↓';
  final label = k.keyLabel;
  return label.isEmpty ? '#${k.keyId}' : label;
}
