// Lane C3 device batch, the vault (IMG-011, PRIV-007): the real OS crypto and
// Keystore behind the vault on the Samsung (C4a's AndroidVaultCrypto). The
// fingerprint prompt and the screen capture block are manual checks (listed
// in the PR).
//
//   flutter test integration_test/c3_vault_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
//
// Reports (binding.reportData): vault_kdf_ms (one PIN check at the shipped
// 600,000 rounds, two vaults in parallel), vault_seal_ms_per_mib.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/photos/vault/vault_import.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_player.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show PosixFdIo;

/// A short 16-bit stereo WAV tone (a song small enough to keep in memory).
Uint8List wavTone({double seconds = 3}) {
  const rate = 44100;
  final frames = (seconds * rate).round();
  final pcm = ByteData(frames * 4);
  for (var i = 0; i < frames; i++) {
    final v = (math.sin(2 * math.pi * 440 * i / rate) * 3000).round();
    pcm
      ..setInt16(i * 4, v, Endian.little)
      ..setInt16(i * 4 + 2, v, Endian.little);
  }
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24]);
  void u16(int v) => b.add([v & 255, v >> 8]);
  b.add('RIFF'.codeUnits);
  u32(36 + pcm.lengthInBytes);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(2);
  u32(rate);
  u32(rate * 4);
  u16(4);
  u16(16);
  b.add('data'.codeUnits);
  u32(pcm.lengthInBytes);
  b.add(pcm.buffer.asUint8List());
  return b.takeBytes();
}

/// A short silent-colour video: an AVI of raw 24-bit frames (64 by 48, 25
/// frames a second), which libmpv plays everywhere without a codec.
Uint8List rawAvi({int frames = 75}) {
  const w = 64;
  const h = 48;
  const fps = 25;
  const frameBytes = w * h * 3;
  void u32(BytesBuilder o, int v) =>
      o.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24]);
  void u16(BytesBuilder o, int v) => o.add([v & 255, v >> 8]);
  List<int> chunk(String id, List<int> body) {
    final o = BytesBuilder()..add(id.codeUnits);
    u32(o, body.length);
    o.add(body);
    if (body.length.isOdd) o.addByte(0);
    return o.takeBytes();
  }

  List<int> list(String type, List<int> body) {
    final o = BytesBuilder()..add('LIST'.codeUnits);
    u32(o, body.length + 4);
    o
      ..add(type.codeUnits)
      ..add(body);
    return o.takeBytes();
  }

  final avih = BytesBuilder();
  u32(avih, 1000000 ~/ fps);
  u32(avih, frameBytes * fps);
  u32(avih, 0);
  u32(avih, 0x10);
  u32(avih, frames);
  u32(avih, 0);
  u32(avih, 1);
  u32(avih, frameBytes);
  u32(avih, w);
  u32(avih, h);
  for (var i = 0; i < 4; i++) {
    u32(avih, 0);
  }
  final strh = BytesBuilder()..add('vidsDIB '.codeUnits);
  u32(strh, 0);
  u16(strh, 0);
  u16(strh, 0);
  u32(strh, 0);
  u32(strh, 1);
  u32(strh, fps);
  u32(strh, 0);
  u32(strh, frames);
  u32(strh, frameBytes);
  u32(strh, 0xFFFFFFFF);
  u32(strh, 0);
  u16(strh, 0);
  u16(strh, 0);
  u16(strh, w);
  u16(strh, h);
  final strf = BytesBuilder();
  u32(strf, 40);
  u32(strf, w);
  u32(strf, h);
  u16(strf, 1);
  u16(strf, 24);
  u32(strf, 0);
  u32(strf, frameBytes);
  u32(strf, 0);
  u32(strf, 0);
  u32(strf, 0);
  u32(strf, 0);
  final hdrl = list('hdrl', [
    ...chunk('avih', avih.takeBytes()),
    ...list('strl', [
      ...chunk('strh', strh.takeBytes()),
      ...chunk('strf', strf.takeBytes()),
    ]),
  ]);
  final movi = BytesBuilder();
  final idx = BytesBuilder();
  var offset = 4;
  for (var i = 0; i < frames; i++) {
    final shade = i * 255 ~/ frames;
    final frame = Uint8List(frameBytes);
    for (var p = 0; p < frameBytes; p += 3) {
      frame[p] = shade;
      frame[p + 1] = 255 - shade;
      frame[p + 2] = 128;
    }
    final c = chunk('00db', frame);
    movi.add(c);
    idx.add('00db'.codeUnits);
    u32(idx, 0x10);
    u32(idx, offset);
    u32(idx, frameBytes);
    offset += c.length;
  }
  final body = BytesBuilder()
    ..add(hdrl)
    ..add(list('movi', movi.takeBytes()))
    ..add(chunk('idx1', idx.takeBytes()));
  final out = BytesBuilder()..add('RIFF'.codeUnits);
  u32(out, body.length + 4);
  out
    ..add('AVI '.codeUnits)
    ..add(body.takeBytes());
  return out.takeBytes();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer c;
  late VaultManager manager;

  // The vault key and the vault entries in secure storage are the app's own,
  // not the test's: on a phone that already has a real vault these tests
  // would use (and, in reset, delete) the real key. They run only where there
  // is no vault yet.
  var realVault = false;

  /// True (and the test is marked skipped) when the phone has a real vault.
  bool skipForRealVault() {
    if (!realVault) return false;
    markTestSkipped('this phone has a vault of its own; not touching its key');
    return true;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('c3-vault');
    c = ProviderContainer(overrides: platformOverrides());
    if (!Platform.isAndroid) return;
    final real = Directory.fromUri(
      await c.read(imagingProvider).noBackupDirectory('vault'),
    );
    realVault =
        real.existsSync() && real.listSync().whereType<Directory>().isNotEmpty;
    manager = VaultManager(
      root: Directory('${dir.path}/vault'),
      crypto: c.read(vaultCryptoProvider),
      secure: c.read(secureStorageProvider),
    );
  });

  tearDown(() async {
    if (Platform.isAndroid && !realVault) await manager.reset();
    c.dispose();
    dir.deleteSync(recursive: true);
  });

  Uint8List bytes(int n, int seed) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

  testWidgets('IMG-011 two vaults, a PIN each, and a photo that reads back', (
    tester,
  ) async {
    if (skipForRealVault()) return;
    final m = manager;
    final kdf = Stopwatch()..start();
    final made = await m.setUp(pin: '246810', decoyPin: '135790');
    kdf.stop();
    expect(made.isOpen, isTrue, reason: '${made.outcome}');
    final data = bytes(3 << 20, 7);
    final sw = Stopwatch()..start();
    final item = await made.vault!.container.add(
      name: 'a.jpg',
      kind: 'image',
      content: Stream.value(data),
      size: data.length,
    );
    sw.stop();
    await made.vault!.close();
    binding.reportData = {
      'vault_kdf_ms': kdf.elapsedMilliseconds,
      'vault_seal_ms_per_mib': sw.elapsedMilliseconds ~/ 3,
    };

    final again = await m.openWithPin('246810');
    expect(again.isOpen, isTrue, reason: '${again.outcome}');
    expect(await again.vault!.container.readAll(item.id), data);
    await again.vault!.close();

    final other = await m.openWithPin('135790');
    expect(other.vault!.container.list(), isEmpty);
    await other.vault!.close();

    expect((await m.openWithPin('000000')).outcome, VaultOutcome.wrongPin);
  }, skip: !Platform.isAndroid);

  testWidgets(
    'IMG-011 Change PIN seals the secret again and keeps the photos',
    (tester) async {
      if (skipForRealVault()) return;
      final m = manager;
      final r = await m.setUp(pin: '246810', decoyPin: '135790');
      final data = bytes(200000, 5);
      final item = await r.vault!.container.add(
        name: 'a.jpg',
        kind: 'image',
        content: Stream.value(data),
        size: data.length,
      );
      expect(await m.changePin(r.vault!, '555555'), VaultOutcome.opened);
      await r.vault!.close();
      // The old PIN is a wrong PIN, not a lost key.
      expect((await m.openWithPin('246810')).outcome, VaultOutcome.wrongPin);
      final again = await m.openWithPin('555555');
      expect(again.isOpen, isTrue, reason: '${again.outcome}');
      expect(await again.vault!.container.readAll(item.id), data);
      await again.vault!.close();
    },
    skip: !Platform.isAndroid,
  );

  testWidgets('IMG-011 nothing readable is on disk and the folder is private', (
    tester,
  ) async {
    if (skipForRealVault()) return;
    final m = manager;
    final r = await m.setUp(pin: '246810');
    final secret = bytes(200000, 3);
    await r.vault!.container.add(
      name: 'private holiday.jpg',
      kind: 'image',
      content: Stream.value(secret),
      size: secret.length,
    );
    await r.vault!.close();
    for (final f in Directory(
      '${dir.path}/vault',
    ).listSync(recursive: true).whereType<File>()) {
      final text = String.fromCharCodes(f.readAsBytesSync());
      expect(text, isNot(contains('private holiday')));
      expect(
        text,
        isNot(contains(String.fromCharCodes(secret.sublist(500, 540)))),
      );
    }
  }, skip: !Platform.isAndroid);

  testWidgets(
    'IMG-011 locking releases the keystore handle and a tampered file fails',
    (tester) async {
      if (skipForRealVault()) return;
      final m = manager;
      final r = await m.setUp(pin: '246810');
      final data = bytes(500000, 5);
      final item = await r.vault!.container.add(
        name: 'a.jpg',
        kind: 'image',
        content: Stream.value(data),
        size: data.length,
      );
      await r.vault!.close();
      final file = File('${r.vault!.container.directory.path}/${item.id}.mv');
      final tampered = file.readAsBytesSync()..[600] ^= 1;
      file.writeAsBytesSync(tampered);
      final again = await m.openWithPin('246810');
      await expectLater(
        again.vault!.container.readAll(item.id),
        throwsA(isA<Object>()),
      );
      await again.vault!.close();
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'IMG-011 reset deletes the Keystore key and a new vault can be made',
    (tester) async {
      if (skipForRealVault()) return;
      final m = manager;
      final first = await m.setUp(pin: '246810');
      expect(first.isOpen, isTrue, reason: '${first.outcome}');
      final item = await first.vault!.container.add(
        name: 'a.jpg',
        kind: 'image',
        content: Stream.value(bytes(1000, 1)),
        size: 1000,
      );
      await first.vault!.close();
      await m.reset();
      expect(m.exists, isFalse);
      final second = await m.setUp(pin: '135790');
      expect(second.isOpen, isTrue, reason: '${second.outcome}');
      expect(second.vault!.container.list(), isEmpty);
      expect(second.vault!.container.byId(item.id), isNull);
      await second.vault!.close();
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'PRIV-007 a video and a song play from the vault on the real engine and cannot be saved out',
    (tester) async {
      if (skipForRealVault()) return;
      final made = await manager.setUp(pin: '246810', decoyPin: '135790');
      expect(made.isOpen, isTrue, reason: '${made.outcome}');
      final vault = made.vault!.container;
      final avi = rawAvi();
      final wav = wavTone();
      final video = await vault.add(
        name: 'clip.avi',
        kind: 'video',
        content: Stream.value(avi),
        size: avi.length,
      );
      final song = await vault.add(
        name: 'tone.wav',
        kind: 'audio',
        content: Stream.value(wav),
        size: wav.length,
      );
      // Nothing readable is on disk beside the vault.
      for (final f in Directory(
        '${dir.path}/vault',
      ).listSync(recursive: true).whereType<File>()) {
        final bytes = f.readAsBytesSync();
        expect(String.fromCharCodes(bytes.take(4)), isNot('RIFF'));
      }

      for (final item in [video, song]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: platformOverrides(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: VaultPlayerScreen(container: vault, item: item),
            ),
          ),
        );
        final scope = ProviderScope.containerOf(
          tester.element(find.byType(VaultPlayerScreen)),
        );
        final engine = scope.read(playbackEngineProvider(EngineRole.video));
        // It plays: the position moves past a moment in.
        var position = Duration.zero;
        for (
          var i = 0;
          i < 100 && position < const Duration(milliseconds: 500);
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          position = engine.current.position;
        }
        expect(
          position,
          greaterThanOrEqualTo(const Duration(milliseconds: 500)),
          reason: '${item.name}: ${engine.current.status}',
        );
        expect(engine.current.status, PlaybackStatus.playing);

        // What would put decoded content on disk is refused (ADR-043).
        final tmp = Directory.systemTemp.createTempSync('c3-refused');
        addTearDown(() => tmp.deleteSync(recursive: true));
        Matcher refused() => throwsA(
          isA<EngineException>().having(
            (e) => e.error.code,
            'code',
            EngineErrorCode.notSupported,
          ),
        );
        await expectLater(engine.screenshot(), refused());
        await expectLater(
          engine.export(
            Duration.zero,
            const Duration(seconds: 1),
            ExportFormat.gif,
            tmp.uri.resolve('out.gif'),
          ),
          refused(),
        );
        await expectLater(
          engine.extractSubtitles(1, tmp.uri.resolve('subs.srt')),
          refused(),
        );
        await expectLater(
          CastTranscoder.start(
            VirtualFileSource(await vault.openFile(item.id), sensitive: true),
            const CastPlan(
              kind: CastPlanKind.transcode,
              container: CastContainer.mp4,
              video: StreamAction.encode,
              audio: StreamAction.encode,
            ),
          ),
          refused(),
        );
        // Nothing was left on disk by trying.
        expect(tmp.listSync(), isEmpty);

        // Leaving stops it.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        expect(engine.current.status, isNot(PlaybackStatus.playing));
      }
      await made.vault!.close();
    },
    skip: !Platform.isAndroid,
  );

  // The pick of a content document is read through its detached fd, never by
  // opening /proc/self/fd/N (Android 16 refuses that with EACCES).
  testWidgets('PRIV-007 a detached fd is read in pieces on a worker isolate', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      List.generate((2 << 20) + 5, (i) => (i * 7) % 251),
    );
    final file = File('${dir.path}/picked.bin')..writeAsBytesSync(bytes);
    final libc = DynamicLibrary.process();
    final cMalloc = libc
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr),
          Pointer<Uint8> Function(int)
        >('malloc');
    final cFree = libc
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('free');
    final open = libc
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Int32),
          int Function(Pointer<Uint8>, int)
        >('open');
    final name = utf8.encode(file.path);
    final path = cMalloc(name.length + 1);
    path.asTypedList(name.length + 1)
      ..setAll(0, name)
      ..[name.length] = 0;
    final opened = <int>[];
    final storage = _FdStorage(() {
      final fd = open(path, 0); // O_RDONLY
      expect(fd, greaterThanOrEqualTo(0));
      opened.add(fd);
      return fd;
    });
    try {
      final r = await openPickedStream(
        storage,
        Uri.parse('content://media/external/file/7'),
      );
      expect(r.size, bytes.length);
      final got = BytesBuilder(copy: false);
      await r.content.forEach(got.add);
      expect(got.takeBytes(), bytes);
      // Every fd was closed: reading one again fails with EBADF.
      for (final fd in opened) {
        expect(() => PosixFdIo().size(fd), throwsA(anything));
      }
    } finally {
      cFree(path);
    }
  }, skip: !Platform.isAndroid);
}

/// Hands out a fresh detached fd for any document.
final class _FdStorage implements StorageFacade {
  _FdStorage(this._open);

  final int Function() _open;

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) async => _open();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
