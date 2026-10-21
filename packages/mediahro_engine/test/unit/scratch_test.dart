import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_engine/src/mpv/audio_decoder.dart';
import 'package:mediahro_engine/src/mpv/audio_tapper.dart';
import 'package:mediahro_engine/src/mpv/pcm_storage.dart';
import 'package:mediahro_engine/src/mpv/scratch.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

final class _File implements VirtualFile {
  _File(this.uri);

  @override
  final Uri uri;
  @override
  bool get isSeekable => true;
  @override
  Future<int?> length() async => 0;
  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List(0);
  @override
  Future<void> close() async {}
}

void _age(Directory dir, Duration by) {
  final old = DateTime.now().subtract(by);
  for (final e in dir.listSync(recursive: true)) {
    if (e is File) e.setLastModifiedSync(old);
  }
}

void main() {
  group('PRIV-007 protected media never reaches disk', () {
    test('PRIV-007 vault sources are sensitive, the rest are not', () {
      expect(
        isSensitiveSource(VirtualFileSource(_File(Uri.parse('vault:/a/b')))),
        isTrue,
      );
      expect(isSensitiveSource(UriSource(Uri.parse('vault:/x'))), isTrue);
      expect(
        isSensitiveSource(VirtualFileSource(_File(Uri.parse('smb://h/s/f')))),
        isFalse,
      );
      expect(isSensitiveSource(UriSource(Uri.file('/m/a.mkv'))), isFalse);
      expect(isSensitiveSource(null), isFalse);
    });

    test('PRIV-007 the sensitive flag marks a source, whatever its scheme', () {
      final file = _File(Uri.parse('smb://h/s/f.mkv'));
      expect(
        isSensitiveSource(VirtualFileSource(file, sensitive: true)),
        isTrue,
      );
      expect(
        isSensitiveSource(UriSource(Uri.file('/m/a.mkv'), sensitive: true)),
        isTrue,
      );
      expect(VirtualFileSource(file).sensitive, isFalse);
      // The flag is part of what a source is.
      expect(
        UriSource(Uri.file('/m/a.mkv')) ==
            UriSource(Uri.file('/m/a.mkv'), sensitive: true),
        isFalse,
      );
      expect(
        VirtualFileSource(file) == VirtualFileSource(file, sensitive: true),
        isFalse,
      );
    });

    test(
      'PRIV-007 a flagged source decodes only from RAM or not at all',
      () async {
        if (Platform.isAndroid || Platform.isLinux) return;
        final decoder = AudioDecoder(
          VirtualFileSource(
            _File(Uri.parse('smb://h/s/f.mkv')),
            sensitive: true,
          ),
        );
        await expectLater(
          decoder.stream.toList(),
          throwsA(
            isA<EngineException>().having(
              (e) => e.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
      },
    );

    test(
      'PRIV-007 the visualiser tap of a protected source writes no file',
      () async {
        if (Platform.isAndroid || Platform.isLinux) {
          return; // memfd exists there: the tap works from RAM
        }
        Set<String> folders() => scratchParent.existsSync()
            ? scratchParent.listSync().map((e) => e.path).toSet()
            : <String>{};
        final before = folders();
        final tap = AnalysisTap(
          frames: 256,
          source: () => UriSource(Uri.file('/m/a.mkv'), sensitive: true),
          item: () => 1,
          position: () => const Duration(seconds: 3),
          playing: () => true,
          isLocal: () => true,
          dumpCache: (a, b, path) async => false,
          period: const Duration(milliseconds: 10),
        );
        final frames = <AudioTapFrame>[];
        final sub = tap.stream.listen(frames.add);
        // Several ticks: each would make PCM storage and start a core.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(tap.active, isFalse, reason: 'no analysis core was started');
        expect(frames, isEmpty);
        expect(folders(), before, reason: 'no scratch folder was made');
        await sub.cancel();
      },
    );

    test(
      'PRIV-007 casting a protected source is refused before any file',
      () async {
        await expectLater(
          CastTranscoder.start(
            UriSource(Uri.file('/m/a.mkv'), sensitive: true),
            const CastPlan(
              kind: CastPlanKind.transcode,
              container: CastContainer.mp4,
              video: StreamAction.encode,
              audio: StreamAction.encode,
            ),
          ),
          throwsA(
            isA<EngineException>().having(
              (e) => e.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
      },
    );

    test('PRIV-007 memory-only PCM refuses the file fallback', () async {
      PcmStorage.memfdOpener = (name) => null; // no usable RAM-backed file
      addTearDown(() => PcmStorage.memfdOpener = null);
      final before = scratchParent.existsSync()
          ? scratchParent.listSync().length
          : 0;
      await expectLater(
        PcmStorage.create(memoryOnly: true),
        throwsA(
          isA<EngineException>().having(
            (e) => e.error.code,
            'code',
            EngineErrorCode.notSupported,
          ),
        ),
      );
      final after = scratchParent.existsSync()
          ? scratchParent.listSync().length
          : 0;
      expect(after, before, reason: 'no scratch folder was made');
    });

    test(
      'PRIV-007 memory-only PCM uses a RAM-backed file when it works',
      () async {
        final dir = Directory.systemTemp.createTempSync('mh-ram');
        addTearDown(() => dir.deleteSync(recursive: true));
        PcmStorage.memfdOpener = (name) => (
          fd: 50,
          path: (File(
            '${dir.path}${Platform.pathSeparator}$name',
          )..writeAsBytesSync(const [])).path,
        );
        PcmStorage.fdCloser = (_) {};
        addTearDown(() {
          PcmStorage.memfdOpener = null;
          PcmStorage.fdCloser = null;
        });
        final s = await PcmStorage.create(memoryOnly: true);
        expect(s.inMemory, isTrue);
        await s.dispose();
      },
    );

    test(
      'PRIV-007 decoding a protected source is refused before any file',
      () async {
        if (Platform.isAndroid || Platform.isLinux) {
          return; // memfd exists there: protected audio decodes from RAM
        }
        final decoder = AudioDecoder(
          VirtualFileSource(_File(Uri.parse('vault:/a/film.mkv'))),
        );
        await expectLater(
          decoder.stream.toList(),
          throwsA(
            isA<EngineException>().having(
              (e) => e.error.code,
              'code',
              EngineErrorCode.notSupported,
            ),
          ),
        );
      },
    );
  });

  group('PRIV-007 scratch folders', () {
    test(
      'PRIV-007 the PCM fallback lives in the private scratch folder and goes',
      () async {
        PcmStorage.memfdOpener = (name) => null;
        addTearDown(() => PcmStorage.memfdOpener = null);
        final s = await PcmStorage.create();
        final dir = File(s.pcmPath).parent;
        expect(dir.parent.path, scratchParent.path);
        expect(
          dir.uri.pathSegments.where((p) => p.isNotEmpty).last,
          startsWith('pcm-'),
        );
        if (!Platform.isWindows) {
          expect(
            dir.statSync().mode & 0x1FF,
            0x1C0,
            reason: 'rwx for the owner only',
          );
        }
        File(s.pcmPath).writeAsBytesSync([1, 2, 3]);
        await s.dispose();
        expect(dir.existsSync(), isFalse);
      },
    );

    test(
      'PRIV-007 the fallback file loses its name once both sides hold it open',
      () async {
        PcmStorage.memfdOpener = (name) => null;
        addTearDown(() => PcmStorage.memfdOpener = null);
        final s = await PcmStorage.create(slice: false);
        addTearDown(s.dispose);
        // mpv appends to the file; the decoder reads it. Both open it
        // before the name goes.
        final writer = File(s.pcmPath).openSync(mode: FileMode.append);
        final reader = File(s.pcmPath).openSync();
        addTearDown(() {
          writer.closeSync();
          reader.closeSync();
        });
        writer.writeFromSync(Uint8List(3 << 20));
        expect(s.unlinkWhileOpen(reader), isTrue);
        expect(File(s.pcmPath).existsSync(), isFalse, reason: 'no name left');
        expect(s.unlinked, isTrue);
        expect(s.pcmLength, 3 << 20);
        writer
          ..writeFromSync(Uint8List(1 << 20))
          ..flushSync();
        expect(s.pcmLength, 4 << 20, reason: 'length through the reader');
        s.release(2 << 20);
        expect(s.released, 2 << 20, reason: 'hole punching still works');
        expect(s.unlinkWhileOpen(reader), isFalse, reason: 'only once');
      },
      skip: Platform.isWindows
          ? 'Windows cannot delete a file that is open'
          : false,
    );

    test('PRIV-007 a memfd has no name to remove', () async {
      final dir = Directory.systemTemp.createTempSync('mh-ram');
      addTearDown(() => dir.deleteSync(recursive: true));
      PcmStorage.memfdOpener = (name) => (
        fd: 51,
        path: (File(
          '${dir.path}${Platform.pathSeparator}$name',
        )..writeAsBytesSync(const [])).path,
      );
      PcmStorage.fdCloser = (_) {};
      addTearDown(() {
        PcmStorage.memfdOpener = null;
        PcmStorage.fdCloser = null;
      });
      final s = await PcmStorage.create(slice: false);
      final reader = File(s.pcmPath).openSync();
      addTearDown(reader.closeSync);
      expect(s.unlinkWhileOpen(reader), isFalse);
      expect(File(s.pcmPath).existsSync(), isTrue);
      await s.dispose();
    });

    test(
      'PRIV-007 stale folders are swept; fresh and active ones stay',
      () async {
        final parent = scratchParent..createSync(recursive: true);
        Directory stale() {
          final d = parent.createTempSync('pcm-stale-');
          File('${d.path}${Platform.pathSeparator}audio.pcm')
              .writeAsBytesSync([9]);
          _age(d, const Duration(hours: 3));
          return d;
        }

        final old = stale();
        final fresh = parent.createTempSync('pcm-fresh-')
          ..childFile('audio.pcm').writeAsBytesSync([1]);
        final active = await createScratch('pcm');
        File('${active.path}${Platform.pathSeparator}audio.pcm')
            .writeAsBytesSync([1]);
        _age(active, const Duration(hours: 3));
        // The folders earlier versions made directly in the temp directory.
        final legacies = [
          for (final name in [
            'mediahro-pcm',
            'mediahro-subx',
            'mediahro-subimg',
            'mediahro-cast',
            'mediahro-shot',
            'mediahro-disc',
            'mh-subs',
          ])
            Directory.systemTemp.createTempSync(name),
        ];
        for (final legacy in legacies) {
          File('${legacy.path}${Platform.pathSeparator}data')
              .writeAsBytesSync([2]);
          _age(legacy, const Duration(hours: 3));
        }
        // A recent one of another process is left alone.
        final recent = Directory.systemTemp.createTempSync('mediahro-cast');
        File('${recent.path}${Platform.pathSeparator}data')
            .writeAsBytesSync([3]);
        addTearDown(() async {
          await deleteScratch(fresh);
          await deleteScratch(active);
          for (final d in [...legacies, recent]) {
            if (d.existsSync()) d.deleteSync(recursive: true);
          }
        });

        await sweepStaleScratch();

        expect(old.existsSync(), isFalse, reason: 'stale folder swept');
        for (final legacy in legacies) {
          expect(legacy.existsSync(), isFalse, reason: 'legacy $legacy swept');
        }
        expect(recent.existsSync(), isTrue, reason: 'recent one kept');
        expect(fresh.existsSync(), isTrue, reason: 'recent work kept');
        expect(active.existsSync(), isTrue, reason: 'in use by this process');
      },
    );
  });
}

extension on Directory {
  File childFile(String name) => File('$path${Platform.pathSeparator}$name');
}
