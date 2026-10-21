import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/images/pipeline/image_worker.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/images/pipeline/thumbnail_cache.dart';
import 'package:mediahro/images/pipeline/worker_pool.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

import '../../images/pipeline_fakes.dart';
import 'disk_support.dart';
import 'fake_vault_crypto.dart';
import 'photos_harness.dart';

Future<void> settleReal(WidgetTester tester) async {
  var quiet = 0;
  for (var i = 0; i < 400 && quiet < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final busy =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    quiet = busy ? 0 : quiet + 1;
  }
  await tester.pumpAndSettle();
}

final class _Window implements SecureWindowFacade {
  final List<bool> calls = [];

  @override
  Future<void> setSecure({required bool secure}) async => calls.add(secure);

  @override
  Stream<bool> get captureActive => const Stream<bool>.empty();
}

void main() {
  late Directory dir;
  late FakeVaultCrypto crypto;
  late MemorySecureStorage secure;
  late _Window window;
  late VaultManager manager;
  late DiskIo io;
  late MediahroImagePipeline pipeline;
  late PhotosHarness h;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mediahro-vault-move');
    crypto = FakeVaultCrypto();
    secure = MemorySecureStorage();
    window = _Window();
    io = DiskIo();
    manager = VaultManager(
      root: Directory('${dir.path}/vault'),
      crypto: crypto,
      secure: secure,
      iterations: 4,
    );
  });

  tearDown(() async {
    await pipeline.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  /// The harness app with real files for the entries and the vault wired in.
  Future<List<PhotoEntry>> open(
    WidgetTester tester, {
    Set<int> videos = const {},
  }) async {
    h = await PhotosHarness.create(tester);
    final entries = fakeEntries(days: 1, firstId: 1, videos: videos);
    for (final e in entries) {
      File('${dir.path}/lib/${e.relPath}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List.fromList(List.generate(3000, (i) => i)));
    }
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: ThumbnailCache(db: h.db, directory: Directory('${dir.path}/th')),
      io: io,
      fallback: FakeUiFallback(),
    );
    await h.pump(
      tester,
      entries: entries,
      extra: [
        vaultManagerProvider.overrideWith((ref) async => manager),
        secureWindowProvider.overrideWithValue(window),
        vaultMoverProvider.overrideWithValue(
          VaultMover(
            files: DiskFiles(Directory('${dir.path}/lib'), io),
            io: io,
            db: h.db,
            pipeline: pipeline,
          ),
        ),
      ],
    );
    return entries;
  }

  Future<void> chooseMove(WidgetTester tester) async {
    await tester.longPress(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to vault'));
    await tester.pumpAndSettle();
    await settleReal(tester);
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.check));
    await settleReal(tester);
  }

  testWidgets(
    'IMG-011 first use: set up, confirm, move, and the vault locks again',
    (tester) async {
      final entries = await open(tester);
      await chooseMove(tester);
      expect(find.text('Set up the vault'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246810');
      final set = find.widgetWithText(FilledButton, 'Set up');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await settleReal(tester);
      expect(find.text('Move this photo to the vault?'), findsOneWidget);
      expect(find.textContaining('best effort'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await settleReal(tester);
      expect(find.text('1 photo is in the vault.'), findsOneWidget);
      expect(
        File('${dir.path}/lib/${entries.first.relPath}').existsSync(),
        isFalse,
      );
      expect(crypto.openHandles, 0);
      // The window was protected for the whole visit and let go after.
      expect(window.calls.first, isTrue);
      expect(window.calls.last, isFalse);
    },
  );

  testWidgets('IMG-011 later uses ask for the PIN on the same pad', (
    tester,
  ) async {
    await tester.runAsync(
      () => manager
          .setUp(pin: '246810', decoyPin: '135790')
          .then((r) => r.vault!.close()),
    );
    final entries = await open(tester);
    await chooseMove(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
    // The second PIN takes the photo to the second vault, with no other prompt.
    await typePin(tester, '135790');
    expect(find.text('Move this photo to the vault?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await settleReal(tester);
    expect(find.text('1 photo is in the vault.'), findsOneWidget);
    expect(
      File('${dir.path}/lib/${entries.first.relPath}').existsSync(),
      isFalse,
    );
    await tester.runAsync(() async {
      final other = await manager.openWithPin('135790');
      expect(other.vault!.container.list(), hasLength(1));
      await other.vault!.close();
      final real = await manager.openWithPin('246810');
      expect(real.vault!.container.list(), isEmpty);
      await real.vault!.close();
    });
  });

  testWidgets('IMG-011 saying no at the question moves nothing and locks', (
    tester,
  ) async {
    await tester.runAsync(
      () => manager.setUp(pin: '246810').then((r) => r.vault!.close()),
    );
    final entries = await open(tester);
    await chooseMove(tester);
    await typePin(tester, '246810');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settleReal(tester);
    expect(
      File('${dir.path}/lib/${entries.first.relPath}').existsSync(),
      isTrue,
    );
    expect(crypto.openHandles, 0);
  });

  testWidgets('IMG-011 closing the PIN pad moves nothing', (tester) async {
    await tester.runAsync(
      () => manager.setUp(pin: '246810').then((r) => r.vault!.close()),
    );
    final entries = await open(tester);
    await chooseMove(tester);
    await tester.tap(find.byTooltip('Close'));
    await settleReal(tester);
    expect(find.text('Move this photo to the vault?'), findsNothing);
    expect(
      File('${dir.path}/lib/${entries.first.relPath}').existsSync(),
      isTrue,
    );
  });

  testWidgets('IMG-011 videos are told they cannot go in yet', (tester) async {
    await open(tester, videos: {1});
    await chooseMove(tester);
    expect(find.text("Videos can't go in the vault yet."), findsOneWidget);
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('IMG-011 where the platform has no OS crypto the move says so', (
    tester,
  ) async {
    h = await PhotosHarness.create(tester);
    pipeline = MediahroImagePipeline(
      worker: ImageWorkerClient(
        IsolateWorkerPool(size: 1, factory: fakeWorker),
      ),
      cache: ThumbnailCache(db: h.db, directory: Directory('${dir.path}/th')),
      io: io,
      fallback: FakeUiFallback(),
    );
    await h.pump(
      tester,
      entries: fakeEntries(days: 1, firstId: 1),
      extra: [
        vaultManagerProvider.overrideWith(
          (ref) async =>
              throw const PlatformCapabilityUnavailable('vaultCrypto'),
        ),
      ],
    );
    await tester.longPress(find.byType(KGridTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to vault'));
    await tester.pumpAndSettle();
    expect(
      find.text("The vault isn't available on this device."),
      findsOneWidget,
    );
  });
}
