import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations_en.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/player_sheets.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

import '../../../integration_test/support/c1_engine.dart';
import '../../core/fakes.dart';
import '../../helpers.dart';

Uint8List _text(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late Directory cache;
  late MemoryFileSystem fs;
  late SidecarLoader loader;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('c1_subs');
    fs = MemoryFileSystem({
      'films/Film.mkv': _text('video'),
      'films/Film.en.srt': _text('1\n00:00:01,000 --> 00:00:02,000\nHi\n'),
      'films/Film.ger.forced.ass': _text('[Script Info]'),
      'films/Film.idx': _text('# VobSub index'),
      'films/Film.sub': _text('vobsub bits'),
      'films/Other.srt': _text('not ours'),
      'films/Subs/3_Spanish.srt': _text('hola'),
      'films/Film.huge.srt': Uint8List(64),
      'mine/Film.ja.srt': _text('konnichiwa'),
    });
    loader = SidecarLoader(
      fileSystemFor: (_) => fs,
      cacheDir: cache,
      maxBytes: 48,
    );
  });

  tearDown(() async {
    // Windows may still hold a just-written file for a moment.
    for (var i = 0; i < 10; i++) {
      try {
        cache.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  final video = Uri.parse('mem:///films/Film.mkv');

  group('SUB-012 external subtitles', () {
    test('SUB-012 sidecars of a streamed video are found and cached', () async {
      final r = await loader.find(video);
      expect(r.map((s) => s.title), [
        'Film.en.srt',
        'Film.ger.forced.ass',
        'Film.idx',
        '3_Spanish.srt',
      ]);
      expect(r.map((s) => s.language), ['en', 'de', null, 'es']);
      expect(r[1].forced, isTrue);
      for (final s in r) {
        expect(s.file.scheme, 'file');
        expect(File.fromUri(s.file).existsSync(), isTrue);
      }
      expect(
        File('${File.fromUri(r[2].file).parent.path}/Film.sub').existsSync(),
        isTrue,
        reason: 'the VobSub .sub travels with its .idx',
      );
      expect(r.any((s) => s.title.contains('huge')), isFalse, reason: 'limit');
      expect(r.any((s) => s.title == 'Other.srt'), isFalse);
    });

    test(
      'SUB-012 a chosen subtitle folder is searched by video name',
      () async {
        final r = await loader.find(
          video,
          ownFolder: false,
          userFolder: Uri.parse('mem:///mine/'),
        );
        expect(r.single.title, 'Film.ja.srt');
        expect(r.single.language, 'ja');
      },
    );

    test(
      'SUB-012 an unreadable folder finds nothing instead of failing',
      () async {
        final broken = SidecarLoader(
          fileSystemFor: (u) =>
              throw VirtualFileException(VirtualFileError.unsupported, u),
          cacheDir: cache,
        );
        expect(await broken.find(video), isEmpty);
      },
    );

    test('SUB-012 picked files are stored for the engine', () async {
      final f = await loader.store('picked.srt', utf8.encode('1\n'));
      expect(f!.existsSync(), isTrue);
      expect(await loader.store('big.srt', Uint8List(100)), isNull);
    });
  });

  group('SUB-012 SUB-013 in the player', () {
    late RecordingEngine engine;
    late VideoMemory memory;
    late SettingsStore settings;
    late VideoPlayerController c;

    setUp(() async {
      engine = RecordingEngine(
        tracks: const [
          Track(id: 1, type: TrackType.video, width: 1920, height: 1080),
          Track(id: 1, type: TrackType.audio, codec: 'aac'),
        ],
      );
      memory = await VideoMemory.open(MemoryVideoMemoryPersistence());
      settings = await memoryStore();
      c = VideoPlayerController(
        engine: engine,
        memory: memory,
        settings: settings,
        sidecars: SidecarLoader(fileSystemFor: (_) => fs, cacheDir: cache),
      );
    });

    tearDown(() async {
      c.dispose();
      await engine.dispose();
    });

    PlayRequest streamed() => PlayRequest(
      resolve: () async => UriSource(Uri.parse('http://nas/films/Film.mkv')),
      locate: () async => video,
      title: 'Film',
      memoryKey: video.toString(),
    );

    // The loader copies files with real I/O: wait for [tracks] sidecars,
    // then for the selection that follows them.
    Future<void> settle({int tracks = 5}) async {
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (engine.externalTracks.length >= tracks) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    test(
      'SUB-012 sidecars become tracks; the preferred language is shown',
      () async {
        settings.set(VideoSettings.subtitleLanguages, ['es']);
        await c.open(streamed());
        await settle();
        expect(engine.externalTracks, hasLength(5));
        final spanish = engine.current.tracks.firstWhere(
          (t) => t.type == TrackType.subtitle && t.language == 'es',
        );
        expect(engine.current.subtitleTrackId, spanish.id);
      },
    );

    test('SUB-012 without a preference the first sidecar is shown', () async {
      await c.open(streamed());
      await settle();
      expect(engine.current.subtitleTrackId, 1);
    });

    test('SUB-012 subtitles the user turned off stay off', () async {
      memory.updateItem(
        video.toString(),
        (m) => m.copyWith(subtitlesOff: true),
      );
      await c.open(streamed());
      await settle();
      expect(engine.externalTracks, isNotEmpty);
      expect(engine.current.subtitleTrackId, isNull);
    });

    test(
      'SUB-012 local files: only the chosen folder (mpv finds the rest)',
      () async {
        settings.set(VideoSettings.subtitleFolder, 'mem:///mine/');
        await c.open(
          PlayRequest(
            source: UriSource(Uri.parse('file:///films/Film.mkv')),
            locate: () async => Uri.parse('file:///films/Film.mkv'),
            title: 'Film',
            memoryKey: 'local',
          ),
        );
        await settle(tracks: 1);
        expect(
          engine.externalTracks.single.$2.pathSegments.last,
          'Film.ja.srt',
        );
      },
    );

    test(
      'SUB-013 a forced character set applies and is remembered per file',
      () async {
        await c.open(streamed());
        await c.setSubtitleCodepage('cp1251');
        expect(engine.fake.subtitleCodepage, 'cp1251');
        await c.open(PlayRequest.uri(Uri.parse('file:///other.mkv')));
        await c.setSubtitleCodepage(null);
        await c.open(streamed());
        expect(engine.fake.subtitleCodepage, 'cp1251');
        expect(c.subtitleCodepage, 'cp1251');
      },
    );

    test('SUB-013 charset labels name the script and the encoding', () {
      final l = AppLocalizationsEn();
      expect(charsetLabel(l, null), 'Detect automatically');
      expect(charsetLabel(l, 'cp1251'), 'Cyrillic (Windows-1251)');
      expect(charsetLabel(l, 'shift_jis'), 'Japanese (SHIFT_JIS)');
    });
  });

  test('SUB-010 SUB-011 subtitle formats show their usual names', () {
    String n(String codec) =>
        formatName(Track(id: 1, type: TrackType.subtitle, codec: codec));
    expect(n('subrip'), 'SRT');
    expect(n('ass'), 'ASS');
    expect(n('hdmv_pgs_subtitle'), 'PGS');
    expect(n('dvd_subtitle'), 'VobSub');
    expect(n('dvb_subtitle'), 'DVB');
    expect(n('webvtt'), 'WebVTT');
    expect(
      formatName(const Track(id: 1, type: TrackType.audio, codec: 'eac3')),
      'EAC3',
    );
  });
}
