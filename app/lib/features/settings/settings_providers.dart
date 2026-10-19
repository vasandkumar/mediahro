import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// The settings document. Production loads `settings.json` asynchronously;
/// main.dart may instead pass an already opened store
/// (`settingsStoreProvider.overrideWithValue(await SettingsStore.open())`)
/// so the first frame already has the user's theme and last mode.
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  final store = SettingsStore(FileSettingsPersistence());
  unawaited(store.load());
  ref.onDispose(store.dispose);
  return store;
});

/// Immutable snapshot; widgets select single keys:
/// `ref.watch(settingsProvider.select((s) => s.get(CoreSettings.amoled)))`.
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsSnapshot>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<SettingsSnapshot> {
  @override
  SettingsSnapshot build() {
    final store = ref.watch(settingsStoreProvider);
    void listener() => state = store.snapshot;
    store.addListener(listener);
    ref.onDispose(() => store.removeListener(listener));
    return store.snapshot;
  }
}

/// Completes once the store has loaded from disk.
final settingsReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(settingsStoreProvider).ready,
);

/// Every lane's settings rows. B3's core sections are the default; the
/// orchestrator overrides this in main.dart to append the other lanes'
/// contributions, each defined in that lane's own folder:
/// `settingsContributionsProvider.overrideWithValue([...coreSettingsContributions, ...videoSettingsContributions])`.
final settingsContributionsProvider = Provider<List<SettingsContribution>>(
  (ref) => coreSettingsContributions,
);

final settingsRegistryProvider = Provider<SettingsRegistry>(
  (ref) => SettingsRegistry(
    ref.watch(settingsContributionsProvider),
    ref.watch(capabilitiesProvider),
  ),
);
