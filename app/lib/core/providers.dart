import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderException;
import 'package:mediahro/core/backup/backup_service.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/library/duplicates.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/core/library/parental_gate.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';
import 'package:mediahro/core/scanner/scan_service.dart';
import 'package:mediahro/core/search/library_search.dart';
import 'package:mediahro/core/sources/discovery/lan_discovery.dart';
import 'package:mediahro/core/sources/dlna/dlna_discovery.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_builders.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/core/sources/url_open.dart';
import 'package:mediahro/platform/platform_facades.dart';

// Lane B2 core services. main.dart (orchestrator) overrides the three
// roots after start-up: libraryDatabaseProvider (LibraryDatabase.open in
// the app support directory, one file per profile), networkPolicyProvider
// (PersistentNetworkPolicy.load) and appDataDirectoryProvider.

final libraryDatabaseProvider = Provider<LibraryDatabase>(
  (ref) => throw StateError('override libraryDatabaseProvider in main.dart'),
);

final networkPolicyProvider = Provider<PersistentNetworkPolicy>(
  (ref) => throw StateError('override networkPolicyProvider in main.dart'),
);

/// App-private data directory (downloads, artwork cache, key files).
final appDataDirectoryProvider = Provider<Directory>(
  (ref) => Directory.systemTemp,
);

final networkGatewayProvider = Provider<NetworkGateway>((ref) {
  final gw = NetworkGateway(ref.watch(networkPolicyProvider));
  ref.onDispose(gw.close);
  return gw;
});

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    // Riverpod 3 wraps what a provider threw when another provider reads it.
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// LAN discovery (NET-001, NET-005). C4 may wrap these to hold the Android
/// multicast lock while they run; tests replace them.
final shareDiscoveryProvider = Provider<Stream<DiscoveredShare> Function()>(
  (ref) => discoverShares,
);
final mediaServerDiscoveryProvider = Provider<Stream<UpnpDevice> Function()>(
  (ref) =>
      () => discoverMediaServers(HttpSession(ref.read(networkGatewayProvider))),
);

final mountsProvider = Provider<MountedFileSystems>(
  (ref) => MountedFileSystems(),
);

final sourceResolverProvider = Provider<SourceResolver>(
  (ref) => DefaultSourceResolver(
    builders: defaultFileSystemBuilders(
      tls: _optional(() => ref.watch(tlsSocketProvider)),
      sftp: _optional(() => ref.watch(sftpProvider)),
    ),
    storage: _optional(() => ref.watch(storageProvider)),
    secureStorage: _optional(() => ref.watch(secureStorageProvider)),
    mainIsolateKinds: mainIsolateSourceKinds,
  ),
);

final scanServiceProvider = Provider<ScanService>((ref) {
  final s = ScanService(
    db: ref.watch(libraryDatabaseProvider),
    resolver: ref.watch(sourceResolverProvider),
  );
  ref.onDispose(() => unawaited(s.dispose()));
  return s;
});

final sourceRepositoryProvider = Provider<SourceRepository>(
  (ref) => SourceRepository(
    db: ref.watch(libraryDatabaseProvider),
    resolver: ref.watch(sourceResolverProvider),
    secureStorage: _optional(() => ref.watch(secureStorageProvider)),
    storage: _optional(() => ref.watch(storageProvider)),
  ),
);

final sourceSummariesProvider = StreamProvider<List<SourceSummary>>((
  ref,
) async* {
  final repo = ref.watch(sourceRepositoryProvider);
  yield await repo.summaries();
  await for (final _ in repo.watch()) {
    yield await repo.summaries();
  }
});

final parentalGateProvider = Provider<ParentalGate?>((ref) {
  final secure = _optional(() => ref.watch(secureStorageProvider));
  if (secure == null) return null;
  final g = ParentalGate(
    db: ref.watch(libraryDatabaseProvider),
    secureStorage: secure,
    biometrics: _optional(() => ref.watch(biometricsProvider)),
  );
  ref.onDispose(() => unawaited(g.dispose()));
  return g;
});

final librarySearchProvider = Provider<LibrarySearch>(
  (ref) => LibrarySearch(ref.watch(libraryDatabaseProvider)),
);
final libraryViewsProvider = Provider<LibraryViews>(
  (ref) => LibraryViews(ref.watch(libraryDatabaseProvider)),
);
final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(libraryDatabaseProvider)),
);
final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(ref.watch(libraryDatabaseProvider)),
);
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(libraryDatabaseProvider)),
);
final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(libraryDatabaseProvider)),
);
final urlHistoryProvider = Provider<UrlHistoryRepository>(
  (ref) => UrlHistoryRepository(ref.watch(libraryDatabaseProvider)),
);
final duplicateFinderProvider = Provider<DuplicateFinder>(
  (ref) => DuplicateFinder(ref.watch(libraryDatabaseProvider)),
);
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(libraryDatabaseProvider),
    secureStorage: _optional(() => ref.watch(secureStorageProvider)),
  ),
);

final fileOperationsProvider = Provider<FileOperations>(
  (ref) => FileOperations(
    fileSystems: ref.watch(mountsProvider),
    db: ref.watch(libraryDatabaseProvider),
    storage: _optional(() => ref.watch(storageProvider)),
  ),
);

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final mounts = ref.watch(mountsProvider);
  final m = DownloadManager(
    db: ref.watch(libraryDatabaseProvider),
    directory: Directory(
      '${ref.watch(appDataDirectoryProvider).path}${Platform.pathSeparator}downloads',
    ),
    opener: (uri) => mounts.forUri(uri).open(uri),
  );
  ref.onDispose(() => unawaited(m.dispose()));
  return m;
});

/// Effective visibility for queries (LIB-013): follows the parental gate.
final visibilityProvider = StreamProvider<bool>((ref) async* {
  final gate = ref.watch(parentalGateProvider);
  yield gate?.isUnlocked ?? false;
  if (gate != null) yield* gate.changes;
});

/// Exposed for the recently-added rows of the mode home screens (C1–C3).
final FutureProviderFamily<List<ItemRow>, LibraryMode> recentlyAddedProvider =
    FutureProvider.family<List<ItemRow>, LibraryMode>(
      (ref, mode) => ref.watch(libraryViewsProvider).recentlyAdded(mode),
    );

final FutureProviderFamily<List<ResumeItem>, LibraryMode>
continueWatchingProvider = FutureProvider.family<List<ResumeItem>, LibraryMode>(
  (ref, mode) => ref.watch(libraryViewsProvider).continueWatching(mode),
);
