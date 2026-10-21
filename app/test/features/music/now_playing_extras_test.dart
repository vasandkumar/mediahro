import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/ratings.dart';
import 'package:mediahro/features/music/player/audio_focus.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro/features/music/player/wake_alarms.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

import 'music_test_support.dart';

void main() {
  late LibraryDatabase db;
  late MusicLibrary lib;
  late ScriptedMusicEngine engine;
  late MusicPlayer player;
  late List<MusicTrack> album;

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    db = LibraryDatabase.memory();
    lib = MusicLibrary(db);
    engine = ScriptedMusicEngine();
    final seed = MusicSeed(db);
    for (var i = 1; i <= 4; i++) {
      await seed.song(
        'a/$i.flac',
        title: 'T$i',
        album: 'A',
        albumArtist: 'X',
        track: i,
      );
    }
    album = await lib.albumTracks((await lib.albums()).single.groupKey);
    player = MusicPlayer(
      engine: engine,
      queues: QueueRepository(db),
      library: lib,
      files: localMusicFiles(db),
      openTimeout: const Duration(milliseconds: 100),
    );
    await player.init();
  });
  tearDown(() async {
    await player.dispose();
    await db.close();
  });

  group('MUS-011 sleep timer', () {
    test('MUS-011 by time: fades out at the end, pauses, restores the '
        'volume', () async {
      final timer = SleepTimer(
        player: player,
        engine: engine,
        fade: const Duration(milliseconds: 400),
        tick: const Duration(milliseconds: 20),
      );
      await player.playTracks(album);
      timer.startTime(const Duration(milliseconds: 600));
      expect(timer.state.mode, SleepMode.time);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      // Inside the fade: the volume is going down, playback continues.
      expect(timer.state.fading, isTrue);
      expect(engine.current.volume, lessThan(1));
      expect(engine.current.status, PlaybackStatus.playing);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(engine.current.status, PlaybackStatus.paused);
      expect(engine.current.volume, 1);
      expect(timer.state.active, isFalse);
      await timer.dispose();
    });

    test(
      'MUS-011 by tracks: pauses after N tracks end; extend and cancel',
      () async {
        final timer = SleepTimer(player: player, engine: engine);
        await player.playTracks(album);
        timer.startTracks(2);
        engine.finishTrack();
        await settle();
        expect(timer.state.tracksLeft, 1);
        expect(engine.current.status, PlaybackStatus.playing);
        engine.finishTrack();
        await settle();
        expect(engine.current.status, PlaybackStatus.paused);
        expect(timer.state.active, isFalse);

        timer.startEndOfTrack();
        expect(timer.state.mode, SleepMode.endOfTrack);
        timer.cancel();
        expect(timer.state.active, isFalse);
        await timer.dispose();
      },
    );
  });

  test('AUD-043 sleep timer by tracks counts DSD items that end with no '
      'gapless join, and the last one leaves the next paused', () async {
    engine.joinsGapless = false;
    final timer = SleepTimer(player: player, engine: engine);
    await player.playTracks(album);
    timer.startTracks(2);
    engine.finishTrack();
    for (var i = 0; i < 4; i++) {
      await settle();
    }
    // The player opened track 2; that start counted as one.
    expect(player.state.index, 1);
    expect(timer.state.tracksLeft, 1);
    expect(engine.current.status, PlaybackStatus.playing);
    engine.finishTrack();
    for (var i = 0; i < 4; i++) {
      await settle();
    }
    expect(timer.state.active, isFalse);
    expect(player.state.index, 2);
    expect(engine.current.status, PlaybackStatus.paused);
    expect(player.holdAtEnd, isFalse);
    await timer.dispose();
  });

  group('MUS-011 wake alarms', () {
    test('MUS-011 next firing honours weekdays and the time of day', () {
      final mon = DateTime(2026, 10, 19, 6, 59); // Monday
      const once = WakeAlarm(id: 'a', hour: 7, minute: 0);
      expect(once.nextAfter(mon), DateTime(2026, 10, 19, 7));
      expect(
        once.nextAfter(DateTime(2026, 10, 19, 7, 1)),
        DateTime(2026, 10, 20, 7),
      );
      const weekend = WakeAlarm(id: 'b', hour: 9, minute: 30, weekdays: {6, 7});
      expect(weekend.nextAfter(mon), DateTime(2026, 10, 24, 9, 30));
      expect(WakeAlarm.fromJson(weekend.toJson())!.weekdays, {6, 7});
    });

    test('MUS-011 alarms persist, schedule with the OS and play a playlist '
        'with a fade-in when fired', () async {
      final facade = _FakeAlarms();
      final prefs = MusicPrefs(db);
      final now = DateTime(2026, 10, 20, 6);
      WakeAlarms make() => WakeAlarms(
        facade: facade,
        prefs: prefs,
        player: player,
        engine: engine,
        db: db,
        library: lib,
        clock: () => now,
        fadeStep: const Duration(milliseconds: 1),
      );
      final alarms = make();
      await alarms.start();
      final pid = await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              name: 'Wake',
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final (i, t) in album.reversed.indexed) {
        await db
            .into(db.playlistItems)
            .insert(
              PlaylistItemsCompanion.insert(
                playlistId: pid,
                position: i,
                itemId: Value(t.itemId),
              ),
            );
      }
      final alarm = WakeAlarm(
        id: alarms.newId(),
        hour: 7,
        minute: 15,
        playlistId: pid,
        fadeIn: const Duration(milliseconds: 5),
      );
      await alarms.save(alarm);
      expect(facade.scheduled[alarm.id]!.at, DateTime(2026, 10, 20, 7, 15));
      await alarms.dispose();

      // A new session restores it; firing plays the playlist with a ramp.
      final again = make();
      await again.start();
      expect(again.alarms.single.playlistId, pid);
      facade.fire(alarm.id);
      // The ramp ends at full volume; wait for that, however slow the
      // machine, instead of a fixed time.
      for (var i = 0; i < 500 && engine.volumes.lastOrNull != 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(player.state.current!.title, 'T4');
      expect(engine.volumes.first, 0);
      expect(engine.volumes.last, 1);
      // One-off alarms switch off after firing.
      expect(again.alarms.single.enabled, isFalse);
      expect(facade.cancelled, contains(alarm.id));
      await again.dispose();
    });
  });

  group('MUS-006 sound, rating, favourite, focus', () {
    test('MUS-006 EQ presets apply to the engine and persist', () async {
      final dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      await dsp.load();
      expect(engine.dsp!.graphicEq, isEmpty);
      await dsp.applyPreset('bassBoost');
      expect(engine.dsp!.graphicEq, builtInEqPresets['bassBoost']);
      await dsp.update(
        dsp.sound.copyWith(
          preampDb: -3,
          loudness: LoudnessMode.replayGainAlbum,
          crossfade: const Duration(seconds: 4),
        ),
      );
      final id = await dsp.savePreset('Mine');
      expect(engine.transition!.naturalEnd, const Duration(seconds: 4));
      expect(engine.transition!.manualSkip, Duration.zero);
      final reloaded = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
      await reloaded.load();
      expect(reloaded.sound.preset, 'custom:$id');
      expect(reloaded.sound.loudness, LoudnessMode.replayGainAlbum);
      expect(engine.dsp!.preampDb, -3);
      expect((await reloaded.customPresets()).single.name, 'Mine');
      await reloaded.deletePreset(id);
      expect(await reloaded.customPresets(), isEmpty);
      await dsp.dispose();
      await reloaded.dispose();
    });

    test('MUS-006 rating and favourite', () async {
      final r = MusicRatings(db, TagRepository(db));
      final id = album.first.itemId;
      expect(await r.rating(id), isNull);
      await r.setRating(id, 8);
      expect(await r.rating(id), 8);
      await r.setRating(id, 0);
      expect(await r.rating(id), isNull);
      await r.setFavourite(id, favourite: true);
      expect(await r.isFavourite(id), isTrue);
      await r.setFavourite(id, favourite: false);
      expect(await r.isFavourite(id), isFalse);
    });

    test('MUS-006 audio focus: pause for calls and resume, duck, pause on '
        'unplug', () async {
      final out = _FakeOutput();
      final focus = MusicFocusBridge(
        player: player,
        engine: engine,
        output: out,
      )..start();
      await player.playTracks(album);
      await settle();
      expect(out.focusRequests, 1);
      out.send(AudioInterruptionKind.began);
      await settle();
      expect(engine.current.status, PlaybackStatus.paused);
      out.send(AudioInterruptionKind.endedShouldResume);
      await settle();
      expect(engine.current.status, PlaybackStatus.playing);
      out.send(AudioInterruptionKind.duck);
      await settle();
      expect(engine.ducking, 0.25);
      out.send(AudioInterruptionKind.unduck);
      await settle();
      expect(engine.ducking, 1);
      out.send(AudioInterruptionKind.becomingNoisy);
      await settle();
      expect(engine.current.status, PlaybackStatus.paused);
      out.send(AudioInterruptionKind.endedShouldResume);
      await settle();
      expect(engine.current.status, PlaybackStatus.paused);
      await focus.dispose();
      expect(out.abandoned, isTrue);
    });
  });
}

final class _FakeAlarms implements AlarmFacade {
  final scheduled = <String, ScheduledAlarm>{};
  final cancelled = <String>[];
  final _fired = StreamController<String>.broadcast();

  void fire(String id) => _fired.add(id);

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> schedule(ScheduledAlarm alarm) async =>
      scheduled[alarm.id] = alarm;

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Stream<String> get fired => _fired.stream;
}

final class _FakeOutput implements AudioOutputFacade {
  final _i = StreamController<AudioInterruption>.broadcast();
  int focusRequests = 0;
  bool abandoned = false;

  void send(AudioInterruptionKind k) => _i.add(AudioInterruption(k));

  @override
  Stream<AudioInterruption> get interruptions => _i.stream;

  @override
  Future<bool> requestFocus({bool duckOthers = false}) async {
    focusRequests++;
    return true;
  }

  @override
  Future<void> abandonFocus() async => abandoned = true;

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}
