import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/app/shortcuts/key_spec.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// Two actions active at the same time share a key.
@immutable
final class ShortcutConflict {
  const ShortcutConflict(this.spec, this.actions);

  final KeySpec spec;
  final List<ShortcutAction> actions;
}

/// Effective keys per action: platform defaults, replaced by the user's
/// remapping where one exists (CORE-009).
@immutable
final class ShortcutBindings {
  const ShortcutBindings(this.actions, this._keys, this.platform);

  factory ShortcutBindings.resolve({
    required List<ShortcutAction> actions,
    required AppPlatform platform,
    required SettingsSnapshot settings,
  }) {
    final keys = <String, List<KeySpec>>{};
    for (final a in actions) {
      final stored = settings.get(CoreSettings.shortcut(a.id));
      keys[a.id] =
          identical(stored, CoreSettings.platformDefault) ||
              (stored.length == 1 && stored.first == '@default')
          ? a.defaultsFor(platform)
          : [for (final s in stored) ?KeySpec.decode(s)];
    }
    return ShortcutBindings(actions, keys, platform);
  }

  final List<ShortcutAction> actions;
  final Map<String, List<KeySpec>> _keys;
  final AppPlatform platform;

  List<KeySpec> keysFor(String actionId) => _keys[actionId] ?? const [];

  bool isDefault(ShortcutAction a) {
    final d = a.defaultsFor(platform);
    final k = keysFor(a.id);
    return d.length == k.length && d.every(k.contains);
  }

  /// Actions in the same scope, or a global and a scoped action, that share
  /// a key. Global actions stay active inside the player, so they conflict
  /// with player keys too.
  List<ShortcutConflict> get conflicts {
    final byKey = <(KeySpec, ShortcutScope), List<ShortcutAction>>{};
    for (final a in actions) {
      for (final k in keysFor(a.id)) {
        final scopes = a.scope == ShortcutScope.global
            ? ShortcutScope.values
            : [a.scope];
        for (final s in scopes) {
          (byKey[(k, s)] ??= []).add(a);
        }
      }
    }
    final seen = <String>{};
    return [
      for (final e in byKey.entries)
        if (e.value.length > 1 &&
            seen.add(
              '${e.key.$1.encode()}|${e.value.map((a) => a.id).join(',')}',
            ))
          ShortcutConflict(e.key.$1, e.value),
    ];
  }

  /// Other actions that would clash with binding [spec] to [action].
  List<ShortcutAction> clashesWith(ShortcutAction action, KeySpec spec) => [
    for (final a in actions)
      if (a.id != action.id &&
          keysFor(a.id).contains(spec) &&
          (a.scope == action.scope ||
              a.scope == ShortcutScope.global ||
              action.scope == ShortcutScope.global))
        a,
  ];

  Map<ShortcutActivator, Intent> shortcutsFor(
    ShortcutScope scope,
    Set<String> handled,
  ) => {
    for (final a in actions)
      if (a.scope == scope && handled.contains(a.id))
        for (final k in keysFor(a.id))
          k.activator(platform): ShortcutIntent(a.id),
  };
}

/// Intent carrying a [ShortcutAction] id.
@immutable
final class ShortcutIntent extends Intent {
  const ShortcutIntent(this.actionId);

  final String actionId;
}

/// All remappable actions. B3's catalogue is the default; lanes with extra
/// actions are appended by the orchestrator in main.dart.
final shortcutActionsProvider = Provider<List<ShortcutAction>>(
  (ref) => ShortcutCatalog.all,
);

final shortcutBindingsProvider = Provider<ShortcutBindings>(
  (ref) => ShortcutBindings.resolve(
    actions: ref.watch(shortcutActionsProvider),
    platform: ref.watch(capabilitiesProvider).platform,
    settings: ref.watch(settingsProvider),
  ),
);

/// Writes a remapping. Pass [keys] = null to restore the default.
void setShortcut(
  SettingsStore store,
  ShortcutAction action,
  List<KeySpec>? keys,
) {
  final key = CoreSettings.shortcut(action.id);
  if (keys == null) {
    store.reset(key);
  } else {
    store.set(key, [for (final k in keys) k.encode()]);
  }
}
