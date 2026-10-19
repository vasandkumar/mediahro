import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/privacy/policy_privacy_usage.dart';
import 'package:mediahro/features/settings/privacy/privacy_source.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:path_provider/path_provider.dart';

/// The app's long-lived roots, opened once before the first frame by
/// main.dart (and by integration tests, so they launch what users get):
/// settings, the library database (lane B2), the network policy that reads
/// its PRIV-004 toggles from settings, and the privacy dashboard's view of
/// it (CORE-015).
final class AppServices {
  AppServices._(
    this.directory,
    this.settings,
    this.database,
    this.networkPolicy,
    this.privacyUsage,
  ) {
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(flush()),
      onHide: () => unawaited(flush()),
    );
  }

  /// Opens everything in [directory] (default: the app support directory).
  static Future<AppServices> open({Directory? directory}) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final settings = await SettingsStore.open(
      FileSettingsPersistence(directory: () async => dir),
    );
    final database = LibraryDatabase.open(dir);
    final policy = await PersistentNetworkPolicy.load(
      database,
      isToggledOn: (id) => settings.get(CoreSettings.endpoint(id)),
    );
    await policy.refreshUserHosts();
    return AppServices._(
      dir,
      settings,
      database,
      policy,
      PolicyPrivacyUsage(policy, settings),
    );
  }

  final Directory directory;
  final SettingsStore settings;
  final LibraryDatabase database;
  final PersistentNetworkPolicy networkPolicy;
  final PolicyPrivacyUsage privacyUsage;
  late final AppLifecycleListener _lifecycle;

  /// Provider overrides for `mediahroRoot`.
  List<Override> get overrides => [
    libraryDatabaseProvider.overrideWithValue(database),
    networkPolicyProvider.overrideWithValue(networkPolicy),
    appDataDirectoryProvider.overrideWithValue(directory),
    privacyUsageProvider.overrideWithValue(privacyUsage),
  ];

  /// Writes pending settings and last-used times (app pause, tests).
  Future<void> flush() async {
    await settings.flush();
    await networkPolicy.flush();
  }

  Future<void> close() async {
    _lifecycle.dispose();
    privacyUsage.dispose();
    await networkPolicy.dispose();
    await database.close();
    await settings.flush();
  }
}
