import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/vault/vault_keys.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/features/photos/vault/vault_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

import 'photos_harness.dart';

/// Waits for real file I/O the widget started: each step of a read needs the
/// real event loop, then the fake-async microtasks that follow it.
Future<void> io(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

final class _Locking implements SecureStorageFacade {
  bool refuse = false;

  @override
  Future<List<int>> wrapKey(
    List<int> key, {
    required bool requireBiometry,
  }) async => [for (final b in key) b ^ 0x5a];

  @override
  Future<List<int>> unwrapKey(
    List<int> wrapped, {
    required String reason,
  }) async {
    if (refuse) throw StateError('cancelled');
    return [for (final b in wrapped) b ^ 0x5a];
  }

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

final class _Lock implements BiometricsFacade {
  _Lock([this.kind = BiometricKind.fingerprint]);

  final BiometricKind kind;

  @override
  Future<BiometricKind> available() async => kind;

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

void main() {
  late Directory root;
  late _Locking secure;
  late VaultKeys keys;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mediahro-vault-ui');
    secure = _Locking();

    keys = VaultKeys(
      root: root,
      secure: secure,
      biometrics: _Lock(),
      pinIterations: 10,
    );
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort on Windows.
      }
    });
  });

  Future<void> open(
    WidgetTester tester, {
    VaultKeys? override,
    bool failKeys = false,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          vaultKeysProvider.overrideWith((ref) async {
            if (failKeys) {
              throw const PlatformCapabilityUnavailable('secure storage');
            }
            return override ?? keys;
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VaultScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A vault with [names] in it (videos, so no picture is decoded), locked.
  Future<void> seeded(
    WidgetTester tester,
    List<String> names, {
    String? decoyPin,
  }) async {
    await tester.runAsync(() async {
      final store = await keys.create();
      for (final n in names) {
        await store.add(
          name: n,
          kind: 'video',
          content: Stream.value(Uint8List.fromList([1, 2, 3])),
          size: 3,
        );
      }
      if (decoyPin != null) {
        final d = await keys.createDecoy(decoyPin);
        await d.add(
          name: 'cat.mp4',
          kind: 'video',
          content: Stream.value(Uint8List.fromList([9])),
          size: 1,
        );
      }
    });
  }

  testWidgets('IMG-011 without a vault the screen offers to set one up', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Set up the vault'), findsOneWidget);
    expect(find.text('Use PIN'), findsNothing);
    await tester.tap(find.text('Set up the vault'));
    await io(tester);
    expect(find.text('The vault is empty'), findsOneWidget);
    expect(keys.exists, isTrue);
  });

  testWidgets('IMG-011 a device with no screen lock cannot make a vault', (
    tester,
  ) async {
    final noLock = VaultKeys(
      root: root,
      secure: secure,
      biometrics: _Lock(BiometricKind.none),
      pinIterations: 10,
    );
    await open(tester, override: noLock);
    await tester.tap(find.text('Set up the vault'));
    await io(tester);
    expect(
      find.textContaining('Set a screen lock, fingerprint or face'),
      findsOneWidget,
    );
    expect(noLock.exists, isFalse);
  });

  testWidgets('IMG-011 unlocking shows what is inside, names only here', (
    tester,
  ) async {
    await seeded(tester, ['one.mp4', 'two.mp4']);
    await open(tester);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.bySemanticsLabel('one.mp4'), findsNothing);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
    expect(find.bySemanticsLabel('two.mp4'), findsOneWidget);
  });

  testWidgets('IMG-011 backing out of the prompt keeps it locked', (
    tester,
  ) async {
    await seeded(tester, ['one.mp4']);
    secure.refuse = true;
    await open(tester);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    expect(find.text('The vault stayed locked.'), findsOneWidget);
    expect(find.bySemanticsLabel('one.mp4'), findsNothing);
  });

  testWidgets('IMG-011 Lock closes the vault again', (tester) async {
    await seeded(tester, ['one.mp4']);
    await open(tester);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.bySemanticsLabel('one.mp4'), findsNothing);
  });

  testWidgets('IMG-011 leaving the app locks the vault', (tester) async {
    await seeded(tester, ['one.mp4']);
    await open(tester);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('IMG-011 deleting for good asks first and removes the file', (
    tester,
  ) async {
    await seeded(tester, ['one.mp4', 'two.mp4']);
    await open(tester);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    await tester.longPress(find.bySemanticsLabel('one.mp4'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete for good'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be undone"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete for good'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
    await io(tester);
    expect(find.bySemanticsLabel('one.mp4'), findsNothing);
    expect(find.bySemanticsLabel('two.mp4'), findsOneWidget);
  });

  testWidgets('PRIV-007 the PIN opens the decoy vault, not the real one', (
    tester,
  ) async {
    await seeded(tester, ['real.mp4'], decoyPin: '2468');
    await open(tester);
    expect(find.text('Use PIN'), findsOneWidget);
    await tester.tap(find.text('Use PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unlock'),
      ),
    );
    await io(tester);
    expect(find.text("That PIN doesn't work."), findsOneWidget);
    await tester.tap(find.text('Use PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unlock'),
      ),
    );
    await io(tester);
    expect(find.bySemanticsLabel('cat.mp4'), findsOneWidget);
    expect(find.bySemanticsLabel('real.mp4'), findsNothing);
    // Inside the decoy there is no menu that shows the decoy exists.
    expect(find.byTooltip('More'), findsNothing);
  });

  testWidgets('PRIV-007 the decoy vault is made from the real one', (
    tester,
  ) async {
    await seeded(tester, ['real.mp4']);
    await open(tester);
    await tester.tap(find.text('Unlock'));
    await io(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decoy vault'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '12');
    await tester.enterText(fields.at(1), '12');
    await tester.tap(find.text('Set up with a PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Use 4 to 12 digits.'), findsOneWidget);
    await tester.enterText(fields.at(0), '2468');
    await tester.enterText(fields.at(1), '2469');
    await tester.tap(find.text('Set up with a PIN'));
    await tester.pumpAndSettle();
    expect(find.text('The two PINs differ.'), findsOneWidget);
    await tester.enterText(fields.at(1), '2468');
    await tester.tap(find.text('Set up with a PIN'));
    await io(tester);
    expect(keys.decoyExists, isTrue);
  });

  testWidgets('IMG-011 a platform without secure storage says so', (
    tester,
  ) async {
    await open(tester, failKeys: true);
    expect(
      find.textContaining("isn't available on this device"),
      findsOneWidget,
    );
  });

  group('moving photos in', () {
    Future<void> selectAndMove(
      WidgetTester tester, {
      Set<int> videos = const {},
    }) async {
      final h = await PhotosHarness.create(tester);
      await h.pump(
        tester,
        entries: fakeEntries(days: 1, firstId: 1, videos: videos),
        extra: [vaultKeysProvider.overrideWith((ref) async => keys)],
      );
      await tester.longPress(find.byType(KGridTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to vault'));
      await tester.pumpAndSettle();
    }

    testWidgets('IMG-011 the selection menu asks before moving', (
      tester,
    ) async {
      await selectAndMove(tester);
      expect(find.text('Move this photo to the vault?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(keys.exists, isFalse);
    });

    testWidgets('IMG-011 videos are told they cannot go in yet', (
      tester,
    ) async {
      await selectAndMove(tester, videos: {1});
      expect(find.text("Videos can't go in the vault yet."), findsOneWidget);
      expect(find.text('Move this photo to the vault?'), findsNothing);
    });

    testWidgets('IMG-011 a photo that cannot be read stays where it was', (
      tester,
    ) async {
      await selectAndMove(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await io(tester);
      expect(find.textContaining('could not be moved'), findsOneWidget);
    });
  });
}
