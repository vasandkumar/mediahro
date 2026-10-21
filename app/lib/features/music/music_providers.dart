import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderException;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/books/book_player.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/car/music_browse_tree.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro/features/music/library/music_indexer.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/library/ratings.dart';
import 'package:mediahro/features/music/lyrics/lrc.dart';
import 'package:mediahro/features/music/lyrics/lyrics_service.dart';
import 'package:mediahro/features/music/player/audio_focus.dart';
import 'package:mediahro/features/music/player/dsd_output.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/music_session.dart';
import 'package:mediahro/features/music/player/sleep_shake.dart';
import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro/features/music/player/spoken_mode.dart';
import 'package:mediahro/features/music/player/wake_alarms.dart';
import 'package:mediahro/features/music/podcasts/episode_downloads.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';
import 'package:mediahro/features/music/scrobble/scrobble_services.dart';
import 'package:mediahro/features/music/scrobble/scrobbler.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';
import 'package:mediahro/features/music/visualizer/visualizer.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_servers/mediahro_servers.dart';

/// Whether the app runs with a library database (always in the app; shell
/// tests run without one).
final musicLibraryAvailableProvider = Provider<bool>((ref) {
  try {
    ref.watch(libraryDatabaseProvider);
    return true;
  } on Object {
    return false;
  }
});

final musicLibraryProvider = Provider<MusicLibrary>(
  (ref) => MusicLibrary(ref.watch(libraryDatabaseProvider)),
);

final musicFilesProvider = Provider<MusicFiles>((ref) {
  final f = MusicFiles(
    ref.watch(libraryDatabaseProvider),
    ref.watch(sourceResolverProvider),
    mounts: ref.watch(mountsProvider),
  );
  ref.onDispose(() => unawaited(f.close()));
  return f;
});

final artworkStoreProvider = Provider<ArtworkStore>(
  (ref) => ArtworkStore(
    ref.watch(libraryDatabaseProvider),
    Directory(
      [
        ref.watch(appDataDirectoryProvider).path,
        'music',
        'art',
      ].join(Platform.pathSeparator),
    ),
  ),
);

/// Background tag and art reading (MUS-002, MUS-004); started by the music
/// screen and kept for the app's life.
final musicIndexerProvider = Provider<MusicIndexer>((ref) {
  final i = MusicIndexer(
    db: ref.watch(libraryDatabaseProvider),
    files: ref.watch(musicFilesProvider),
    art: ref.watch(artworkStoreProvider),
  )..start();
  ref.onDispose(() => unawaited(i.dispose()));
  return i;
});

/// The music player over the pool's music engine (MUS-006, MUS-007).
final musicPlayerProvider = Provider<MusicPlayer>((ref) {
  final p = MusicPlayer(
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    queues: ref.watch(queueRepositoryProvider),
    library: ref.watch(musicLibraryProvider),
    files: ref.watch(musicFilesProvider),
    progress: ref.watch(progressRepositoryProvider),
    playlists: ref.watch(playlistRepositoryProvider),
  );
  unawaited(p.init());
  ref.onDispose(() => unawaited(p.dispose()));
  final output = _optional(() => ref.read(audioOutputProvider));
  final dsd = ref.read(dsdOutputGateProvider);
  if (dsd != null) {
    // Native DSD (AUD-043) stays switched on for the DAC it was offered on.
    unawaited(
      dsd
          .restore(ref.read(playbackEngineProvider(EngineRole.music)))
          .catchError((Object _) {}),
    );
  }
  if (output != null) {
    final focus = MusicFocusBridge(
      player: p,
      engine: ref.watch(playbackEngineProvider(EngineRole.music)),
      output: output,
    )..start();
    ref.onDispose(() => unawaited(focus.dispose()));
  }
  final session = _optional(() => ref.read(mediaSessionProvider));
  if (session != null) {
    // One session owner for music and video (ADR-029).
    final owners = StreamController<MediaSessionKind?>.broadcast();
    ref
      ..listen(mediaSessionOwnerProvider, (_, next) => owners.add(next))
      ..onDispose(() => unawaited(owners.close()));
    final bridge = MusicSessionBridge(
      player: p,
      session: session,
      art: ref.watch(artworkStoreProvider),
      widgets: _optional(() => ref.read(homeWidgetsProvider)),
      owner: SessionOwnerLink(
        claim: () => ref
            .read(mediaSessionOwnerProvider.notifier)
            .claim(MediaSessionKind.music),
        release: () => ref
            .read(mediaSessionOwnerProvider.notifier)
            .release(MediaSessionKind.music),
        changes: owners.stream,
      ),
    )..start();
    ref.onDispose(() => unawaited(bridge.dispose()));
  }
  final scrobbler = Scrobbler(
    db: ref.watch(libraryDatabaseProvider),
    prefs: ref.watch(musicPrefsProvider),
    player: p,
    services: ref.watch(scrobbleServicesProvider),
  )..start();
  _scrobblers[p] = scrobbler;
  ref.onDispose(() => unawaited(scrobbler.dispose()));
  final browse = _optional(() => ref.read(mediaBrowseProvider));
  if (browse != null) {
    final tree = MusicBrowseTree(
      db: ref.watch(libraryDatabaseProvider),
      library: ref.watch(musicLibraryProvider),
      playlists: ref.watch(musicPlaylistsProvider),
      views: ref.watch(libraryViewsProvider),
      player: p,
      art: ref.watch(artworkStoreProvider),
      labels: _browseLabels(),
    );
    unawaited(browse.register(tree));
    // The car's queue view follows the player.
    var lastQueue = -1;
    final sub = p.states.listen((s) {
      final key = Object.hash(s.queueId, s.queue.length, s.index);
      if (key == lastQueue) return;
      lastQueue = key;
      unawaited(browse.notifyChildrenChanged(MusicBrowseTree.queueId));
    });
    ref.onDispose(() => unawaited(sub.cancel()));
  }
  return p;
});

/// Scrobbling accounts (MUS-009). Last.fm only when the build has its
/// keys; none where secure storage is missing (credentials live nowhere
/// else).
final scrobbleServicesProvider = Provider<List<ScrobbleService>>((ref) {
  final secure = _optional(() => ref.read(secureStorageProvider));
  if (secure == null) return const [];
  final http = _LazyTransport(() => ref.read(networkGatewayProvider));
  return [
    ListenBrainzService(http, secure),
    ?AudioscrobblerService.lastFm(http, secure),
    AudioscrobblerService.libreFm(http, secure),
  ];
});

final Expando<Scrobbler> _scrobblers = Expando('scrobbler');

/// The scrobbler that follows the music player (MUS-009).
final scrobblerProvider = Provider<Scrobbler>(
  (ref) => _scrobblers[ref.watch(musicPlayerProvider)]!,
);

MusicBrowseLabels _browseLabels() {
  final locale = PlatformDispatcher.instance.locale;
  final l10n = lookupAppLocalizations(
    AppLocalizations.delegate.isSupported(locale) ? locale : const Locale('en'),
  );
  return MusicBrowseLabels(
    queue: l10n.musicQueue,
    playlists: l10n.musicTabPlaylists,
    albums: l10n.musicTabAlbums,
    artists: l10n.musicTabArtists,
    folders: l10n.musicTabFolders,
    songs: l10n.musicTabSongs,
    unknownArtist: l10n.musicUnknownArtist,
  );
}

final musicPlaylistsProvider = Provider<MusicPlaylists>(
  (ref) => MusicPlaylists(
    ref.watch(libraryDatabaseProvider),
    ref.watch(playlistRepositoryProvider),
    ref.watch(musicLibraryProvider),
  ),
);

/// The user's radio stations (MUS-014).
final radioStationsProvider = Provider<RadioStations>((ref) {
  final r = RadioStations(ref.watch(musicPrefsProvider));
  ref.onDispose(() => unawaited(r.dispose()));
  return r;
});

/// The native DSD gate (AUD-043); null where the platform has no audio
/// output facade.
final dsdOutputGateProvider = Provider<DsdOutputGate?>((ref) {
  final output = _optional(() => ref.read(audioOutputProvider));
  if (output == null) return null;
  return DsdOutputGate(output: output, prefs: ref.watch(musicPrefsProvider));
});

final musicPrefsProvider = Provider<MusicPrefs>(
  (ref) => MusicPrefs(ref.watch(libraryDatabaseProvider)),
);

/// EQ, levelling and crossfade for the music engine (MUS-006, AUD-003/005).
final musicDspProvider = Provider<MusicDsp>((ref) {
  final d = MusicDsp(
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    prefs: ref.watch(musicPrefsProvider),
    db: ref.watch(libraryDatabaseProvider),
  );
  unawaited(d.load());
  ref.onDispose(() => unawaited(d.dispose()));
  return d;
});

final musicSoundProvider = StreamProvider<MusicSound>(
  (ref) => ref.watch(musicDspProvider).changes,
);

final sleepTimerProvider = Provider<SleepTimer>((ref) {
  final t = SleepTimer(
    player: ref.watch(musicPlayerProvider),
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
  );
  ref.onDispose(() => unawaited(t.dispose()));
  // Shake-to-extend (POD-001), where the phone has a motion sensor.
  final motion = _optional(() => ref.read(motionProvider));
  if (motion != null) {
    final shake = SleepShakeExtender(timer: t, motion: motion)..start();
    ref.onDispose(() => unawaited(shake.dispose()));
  }
  return t;
});

final sleepTimerStateProvider = StreamProvider<SleepTimerState>(
  (ref) => ref.watch(sleepTimerProvider).states,
);

/// Wake-up alarms (MUS-011); null where the platform has no AlarmFacade.
final wakeAlarmsProvider = Provider<WakeAlarms?>((ref) {
  final facade = _optional(() => ref.read(alarmProvider));
  if (facade == null) return null;
  final a = WakeAlarms(
    facade: facade,
    prefs: ref.watch(musicPrefsProvider),
    player: ref.watch(musicPlayerProvider),
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    db: ref.watch(libraryDatabaseProvider),
    library: ref.watch(musicLibraryProvider),
  );
  unawaited(a.start());
  ref.onDispose(() => unawaited(a.dispose()));
  return a;
});

final musicRatingsProvider = Provider<MusicRatings>(
  (ref) => MusicRatings(
    ref.watch(libraryDatabaseProvider),
    ref.watch(tagRepositoryProvider),
  ),
);

/// Rating and favourite of an item, refreshed on index changes.
final FutureProviderFamily<(int?, bool), int> ratingProvider =
    FutureProvider.family<(int?, bool), int>((ref, itemId) async {
      ref.watch(musicLibraryChangesProvider);
      final r = ref.watch(musicRatingsProvider);
      return (await r.rating(itemId), await r.isFavourite(itemId));
    });

/// Lyrics (MUS-005): edited, sidecar, embedded, then LRCLIB when the user
/// turned that endpoint on (PRIV-004).
final lyricsServiceProvider = Provider<LyricsService>(
  (ref) => LyricsService(
    files: ref.watch(musicFilesProvider),
    cacheDir: Directory(
      [
        ref.watch(appDataDirectoryProvider).path,
        'music',
        'lyrics',
      ].join(Platform.pathSeparator),
    ),
    readTags: readTagsOf,
    transport: _LazyTransport(() => ref.read(networkGatewayProvider)),
    onlineEnabled: () => ref
        .read(settingsStoreProvider)
        .get(CoreSettings.endpoint(Endpoints.lrclib.id)),
  ),
);

/// Lyrics of an item; refresh with `ref.invalidate(lyricsProvider(id))`.
final FutureProviderFamily<Lyrics?, MusicTrack> lyricsProvider =
    FutureProvider.family<Lyrics?, MusicTrack>(
      (ref, track) => ref.watch(lyricsServiceProvider).forTrack(track),
    );

/// Podcasts (POD-002): subscriptions, refresh, downloads and playback.
final podcastStoreProvider = Provider<PodcastStore>(
  (ref) => PodcastStore(ref.watch(musicPrefsProvider)),
);

/// The way podcasts reach the network: through the gateway, one allowed hop
/// at a time, each request chain allowed only to the code running that
/// request (a feed cannot widen the allow-list, nothing stays allowed after
/// the request, and a hop to the listener's own network is refused unless it
/// is the host the listener gave for that feed).
final podcastHttpProvider = Provider<PodcastHttp>((ref) {
  // Looked up when a request is made, so a podcast screen costs nothing
  // until the network is used.
  return PodcastHttp(
    send: (r, {maxRedirects = 5}) => ref
        .read(networkGatewayProvider)
        .sendStreamed(r, maxRedirects: maxRedirects),
    beginChain: () {
      final scope = ref.read(networkPolicyProvider).beginAllowScope();
      return ChainAllowance(
        allow: scope.allow,
        close: scope.close,
        run: scope.run,
      );
    },
  );
});

final episodeDownloadsProvider = Provider<ManagerEpisodeDownloads>((ref) {
  final d = ManagerEpisodeDownloads(
    manager: ref.watch(downloadManagerProvider),
    mounts: ref.watch(mountsProvider),
    fileSystem: HttpUrlFileSystem(
      ref.watch(podcastHttpProvider),
      trustedFor: ref.read(podcastStoreProvider).feedHostFor,
    ),
  );
  unawaited(d.resumePending().catchError((Object _) {}));
  return d;
});

final podcastServiceProvider = Provider<PodcastService>((ref) {
  final net = _optional(() => ref.read(networkStatusProvider));
  final s = PodcastService(
    store: ref.watch(podcastStoreProvider),
    http: ref.watch(podcastHttpProvider),
    downloads: ref.watch(episodeDownloadsProvider),
    artDir: Directory(
      [
        ref.watch(appDataDirectoryProvider).path,
        'music',
        'podcasts',
        'art',
      ].join(Platform.pathSeparator),
    ),
    canDownloadNow: net == null
        ? null
        : () async {
            final st = await net.current();
            return !st.metered && !st.constrained;
          },
  );
  ref.onDispose(() => unawaited(s.dispose()));
  return s;
});

/// Checks the subscriptions for new episodes at start and then about every
/// hour while the app runs (POD-002). The OS does not wake the app for it:
/// that waits for a background task facade (ADR request).
final podcastBootProvider = Provider<void>((ref) {
  final s = ref.watch(podcastServiceProvider);
  Future<void> check() => s
      .refreshAll(minAge: const Duration(hours: 2))
      .then((_) {}, onError: (Object _) {});
  unawaited(Future(check));
  final timer = Timer.periodic(
    const Duration(hours: 1),
    (_) => unawaited(check()),
  );
  ref.onDispose(timer.cancel);
});

final podcastPlayerProvider = Provider<PodcastPlayer>((ref) {
  final sleep = ref.watch(sleepTimerProvider);
  final p = PodcastPlayer(
    mode: ref.watch(spokenModeProvider),
    player: ref.watch(musicPlayerProvider),
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    dsp: ref.watch(musicDspProvider),
    service: ref.watch(podcastServiceProvider),
    holdAtEnd: () {
      final s = sleep.state;
      return s.active &&
          (s.mode == SleepMode.endOfTrack ||
              (s.mode == SleepMode.tracks && s.tracksLeft == 1));
    },
  );
  ref.onDispose(() => unawaited(p.dispose()));
  return p;
});

final podcastPlayerStateProvider = StreamProvider<PodcastPlayerState>(
  (ref) => ref.watch(podcastPlayerProvider).states,
);

/// The subscriptions with their unplayed counts; reloads on any change.
final podcastShowsProvider = StreamProvider<List<(PodcastShow, int)>>((
  ref,
) async* {
  final s = ref.watch(podcastServiceProvider);
  Future<List<(PodcastShow, int)>> load() async {
    final counts = await s.unplayedCounts();
    return [for (final show in await s.shows()) (show, counts[show.id] ?? 0)];
  }

  yield await load();
  await for (final _ in s.changes) {
    yield await load();
  }
});

/// One show; reloads on any change.
final FutureProviderFamily<PodcastShow?, String> podcastShowProvider =
    FutureProvider.family<PodcastShow?, String>((ref, showId) {
      final s = ref.watch(podcastServiceProvider);
      final sub = s.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return s.store.show(showId);
    });

/// The episodes of one show; reloads on any change.
final FutureProviderFamily<List<EpisodeEntry>, String> podcastEpisodesProvider =
    FutureProvider.family<List<EpisodeEntry>, String>((ref, showId) {
      final s = ref.watch(podcastServiceProvider);
      final sub = s.changes.listen((_) => ref.invalidateSelf());
      ref.onDispose(sub.cancel);
      return s.episodes(showId);
    });

/// Audiobooks (POD-001): the books in the music library, where the listener
/// stands in each, and the player mode that remembers it.
final bookStoreProvider = Provider<BookStore>(
  (ref) => BookStore(ref.watch(musicPrefsProvider)),
);

final bookLibraryProvider = Provider<BookLibrary>(
  (ref) => BookLibrary(
    library: ref.watch(musicLibraryProvider),
    store: ref.watch(bookStoreProvider),
    files: ref.watch(musicFilesProvider),
    readTags: readTagsOf,
  ),
);

/// Who owns the engine's speed while spoken word plays (books, podcasts).
final spokenModeProvider = Provider<SpokenMode>((ref) => SpokenMode());

final bookPlayerProvider = Provider<BookPlayer>((ref) {
  final b = BookPlayer(
    mode: ref.watch(spokenModeProvider),
    player: ref.watch(musicPlayerProvider),
    engine: ref.watch(playbackEngineProvider(EngineRole.music)),
    dsp: ref.watch(musicDspProvider),
    library: ref.watch(bookLibraryProvider),
    store: ref.watch(bookStoreProvider),
  );
  ref.onDispose(() => unawaited(b.dispose()));
  return b;
});

final bookPlayerStateProvider = StreamProvider<BookPlayerState>(
  (ref) => ref.watch(bookPlayerProvider).states,
);

/// The book list; reloads when the library changes or the book in play
/// changes. Pull to refresh with `ref.invalidate`.
final bookEntriesProvider = FutureProvider<List<BookEntry>>((ref) {
  ref
    ..watch(musicLibraryChangesProvider)
    ..watch(bookPlayerStateProvider.select((s) => s.value?.book?.id))
    ..watch(bookPlayerStateProvider.select((s) => s.value?.finished));
  return ref.watch(bookLibraryProvider).entries();
});

/// Safe tag editing (MUS-003).
final tagEditorProvider = Provider<TagEditor>(
  (ref) => TagEditor(
    db: ref.watch(libraryDatabaseProvider),
    files: ref.watch(musicFilesProvider),
    art: ref.watch(artworkStoreProvider),
    prefs: ref.watch(musicPrefsProvider),
    cacheDir: Directory(
      [
        ref.watch(appDataDirectoryProvider).path,
        'music',
        'edit',
      ].join(Platform.pathSeparator),
    ),
  ),
);

/// Audio tap for the visualiser (AUD-046). Null until the engine's
/// `audioTap` (ADR-027, lane B1) is available; then this adapts it.
final visualizerFeedProvider = Provider<VisualizerFeed?>((ref) => null);

final musicPlayerStateProvider = StreamProvider<MusicPlayerState>(
  (ref) => ref.watch(musicPlayerProvider).states,
);

/// Bumps whenever music items, tags or art change, so views reload.
final musicLibraryChangesProvider = StreamProvider<int>((ref) async* {
  var n = 0;
  yield n;
  await for (final _ in ref.watch(musicLibraryProvider).changes()) {
    yield ++n;
  }
});

/// Cover file of an item (MUS-004), or null.
final FutureProviderFamily<String?, int> coverPathProvider =
    FutureProvider.family<String?, int>((ref, itemId) {
      ref.watch(musicLibraryChangesProvider);
      return ref.watch(artworkStoreProvider).coverPath(itemId);
    });

/// Reads a platform facade that may be unavailable. Always with
/// `ref.read`: Riverpod 3 retries providers that throw, and a `watch` would
/// rebuild (and reset) the player on every retry.
T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// Resolves the gateway only when a request is made, so features that may
/// go online stay usable where networking is not set up (tests, shells).
final class _LazyTransport implements HttpTransport {
  _LazyTransport(this._gateway);

  final HttpTransport Function() _gateway;

  @override
  Future<HttpResponseData> send(HttpRequestData request) =>
      _gateway().send(request);
}
