import 'dart:async';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/features/music/library/music_files.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Music test data on an in-memory index.
final class MusicSeed {
  MusicSeed(this.db);

  final LibraryDatabase db;
  late final IndexWriter writer = IndexWriter(db);
  int? _source;

  Future<int> source([String root = 'file:///music/']) async =>
      _source ??= await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              kind: SourceKind.local,
              name: 'Music',
              rootUri: root,
              addedAt: DateTime.utc(2026),
            ),
          );

  Future<int> song(
    String relPath, {
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    String? genre,
    String? composer,
    int? year,
    int? track,
    int? disc,
    int durationMs = 180000,
    DateTime? addedAt,
  }) async {
    final sid = await source();
    final name = relPath.split('/').last;
    final slash = relPath.lastIndexOf('/');
    final id = await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            sourceId: sid,
            relPath: relPath,
            parentPath: slash < 0 ? '' : relPath.substring(0, slash),
            name: name,
            ext: name.split('.').last,
            kind: ItemKind.audio,
            size: 1000,
            mtime: DateTime.utc(2026),
            addedAt: addedAt ?? DateTime.utc(2026),
            scannedAt: DateTime.utc(2026),
            title: name,
            sortTitle: name.toLowerCase(),
          ),
        );
    await writer.applyProbe(
      id,
      ProbeResult(
        durationMs: durationMs,
        title: title ?? name,
        artist: artist,
        albumArtist: albumArtist,
        album: album,
        genre: genre,
        composer: composer,
        year: year,
        trackNumber: track,
        discNumber: disc,
      ),
    );
    return id;
  }
}

MusicFiles localMusicFiles(LibraryDatabase db) => MusicFiles(
  db,
  DefaultSourceResolver(
    builders: {SourceKind.local: (_) => const LocalFileSystem()},
  ),
);

/// A music engine that behaves like `CrossfadingEngine` for the player's
/// purposes: `item` increments on every start (open, skip, gapless
/// advance), and [finishTrack] plays into the prepared next item.
final class ScriptedMusicEngine implements PlaybackEngine {
  final calls = <String>[];
  final opened = <MediaSource>[];
  MediaSource? next;
  bool nextSameAlbum = false;

  /// False plays like a DSD item over DoP (AUD-043): the engine never joins
  /// the next item gaplessly, so `nextPrepared` stays false.
  bool joinsGapless = true;
  final _c = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  @override
  EngineRole get role => EngineRole.music;

  @override
  PlaybackState get current => _state;

  @override
  Stream<PlaybackState> get state => Stream.multi((l) {
    l.add(_state);
    final s = _c.stream.listen(l.add);
    l.onCancel = s.cancel;
  });

  void _emit(PlaybackState s) {
    _state = s;
    _c.add(s);
  }

  @override
  Future<void> open(MediaSource src, {OpenOptions? opts}) async {
    calls.add('open');
    opened.add(src);
    next = null;
    final o = opts ?? const OpenOptions();
    _emit(
      PlaybackState(
        status: o.autoplay ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: o.start ?? Duration.zero,
        duration: const Duration(minutes: 3),
        item: _state.item + 1,
      ),
    );
  }

  @override
  Future<void> setNext(MediaSource? next, {bool sameAlbum = false}) async {
    calls.add('setNext');
    final prepared = joinsGapless ? next : null;
    this.next = prepared;
    nextSameAlbum = sameAlbum;
    _emit(_state.copyWith(nextPrepared: prepared != null));
  }

  @override
  Future<void> skipToNext() async {
    calls.add('skipToNext');
    final n = next;
    if (n == null) return;
    opened.add(n);
    next = null;
    _emit(
      _state.copyWith(
        item: _state.item + 1,
        position: Duration.zero,
        nextPrepared: false,
        status: PlaybackStatus.playing,
      ),
    );
  }

  /// The current track reaches its end: gapless advance into [next], or
  /// `ended` when nothing is prepared.
  void finishTrack() {
    final n = next;
    if (n == null) {
      _emit(_state.copyWith(status: PlaybackStatus.ended));
      return;
    }
    opened.add(n);
    next = null;
    _emit(
      _state.copyWith(
        item: _state.item + 1,
        position: Duration.zero,
        nextPrepared: false,
      ),
    );
  }

  void at(Duration position) => _emit(_state.copyWith(position: position));

  @override
  Future<void> play() async {
    calls.add('play');
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _emit(_state.copyWith(status: PlaybackStatus.idle));
  }

  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.keyframe,
  }) async {
    calls.add('seek');
    _emit(_state.copyWith(position: position));
  }

  final volumes = <double>[];
  double? ducking;
  AudioDspChain? dsp;
  TransitionConfig? transition;

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    _emit(_state.copyWith(volume: volume));
  }

  @override
  Future<void> setDucking(double gain) async {
    ducking = gain;
    _emit(_state.copyWith(ducked: gain < 1));
  }

  @override
  Future<void> audioRouteChanged() async {}

  /// Every [AudioOutputConfig] the app applied, and the devices mpv lists.
  final audioOutputs = <AudioOutputConfig>[];
  List<EngineAudioDevice> devices = const [];

  @override
  Future<void> setAudioOutput(AudioOutputConfig config) async =>
      audioOutputs.add(config);

  @override
  Future<List<EngineAudioDevice>> audioDevices() async => devices;

  @override
  Future<void> setAudioDsp(AudioDspChain chain) async => dsp = chain;

  @override
  Future<void> setTransition(TransitionConfig config) async =>
      transition = config;

  /// Every speed the app set (POD-001).
  final rates = <double>[];

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    _emit(_state.copyWith(rate: rate));
  }

  @override
  Future<void> dispose() => _c.close();

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}

String uriOf(MediaSource s) => switch (s) {
  UriSource(:final uri) => uri.toString(),
  VirtualFileSource(:final file) => file.uri.toString(),
};
