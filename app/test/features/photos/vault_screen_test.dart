import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/features/photos/vault/vault_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';

import 'fake_vault_crypto.dart';

Uint8List bytesOf(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

/// Waits for real work the screen started (isolates, files): alternate the
/// real event loop with the fake-async microtasks.
Future<void> settleReal(
  WidgetTester tester, {
  int quietPumps = 20,
  Finder? until,
}) async {
  var quiet = 0;
  for (var i = 0; i < 3000 && quiet < quietPumps; i++) {
    if (until != null && until.evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final busy =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    // With a finder the wait is for that, however long the machine takes (the
    // quiet count is only a guess), up to a bound.
    quiet = busy || until != null ? 0 : quiet + 1;
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

final class _Storage implements StorageFacade {
  final List<PickedFile> picks = [];
  final List<String> saved = [];

  @override
  Future<List<PickedFile>> pickFiles({
    Set<PickKind> kinds = const {PickKind.any},
    bool multiple = false,
  }) async => picks;

  @override
  Future<Uri?> saveFile({
    required String suggestedName,
    required String mimeType,
    required Stream<List<int>> content,
  }) async {
    await content.drain<void>();
    saved.add(suggestedName);
    return Uri.parse('content://saved/$suggestedName');
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late FakeVaultCrypto crypto;
  late MemorySecureStorage secure;
  late _Window window;
  late _Storage storage;
  late LibraryDatabase db;
  late VaultManager manager;
  late DateTime now;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mediahro-vault-ui');
    crypto = FakeVaultCrypto();
    secure = MemorySecureStorage();
    window = _Window();
    storage = _Storage();
    db = LibraryDatabase.memory();
    now = DateTime(2026, 10, 21, 12);
    manager = VaultManager(
      root: root,
      crypto: crypto,
      secure: secure,
      iterations: 4,
      minRounds: 1,
      kdf: inlinePinToken,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort on Windows.
    }
  });

  Future<void> open(WidgetTester tester, {double height = 900}) async {
    tester.view
      ..physicalSize = Size(400, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultManagerProvider.overrideWith((ref) async => manager),
          secureWindowProvider.overrideWithValue(window),
          storageProvider.overrideWithValue(storage),
          libraryDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openVault(context),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
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

  /// A made vault with [names] (as videos, so no picture is decoded) in the
  /// one [pin] opens.
  Future<void> seeded(
    WidgetTester tester, {
    List<String> names = const [],
    List<String> otherNames = const [],
  }) async {
    await tester.runAsync(() async {
      final r = await manager.setUp(pin: '246810', decoyPin: '135790');
      for (final n in names) {
        await r.vault!.container.add(
          name: n,
          kind: 'video',
          content: Stream.value(bytesOf(10)),
          size: 10,
        );
      }
      await r.vault!.close();
      if (otherNames.isNotEmpty) {
        final o = await manager.openWithPin('135790');
        for (final n in otherNames) {
          await o.vault!.container.add(
            name: n,
            kind: 'video',
            content: Stream.value(bytesOf(10)),
            size: 10,
          );
        }
        await o.vault!.close();
      }
    });
  }

  Set<String> everyText(WidgetTester tester) => {
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      if (t.data != null) t.data!,
    for (final b in tester.widgetList<IconButton>(find.byType(IconButton)))
      if (b.tooltip != null) 'tooltip:${b.tooltip}',
  };

  group('IMG-011 set-up', () {
    testWidgets('IMG-011 the first visit offers set-up and checks the PINs', (
      tester,
    ) async {
      await open(tester, height: 1400);
      expect(find.text('Set up the vault'), findsOneWidget);
      final fields = find.byType(TextField);
      final set = find.widgetWithText(FilledButton, 'Set up');
      await tester.enterText(fields.at(0), '12');
      await tester.enterText(fields.at(1), '12');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await tester.pump();
      expect(find.text('Use 6 to 12 digits.'), findsOneWidget);
      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246811');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await tester.pump();
      expect(find.text('The two PINs differ.'), findsOneWidget);
      await tester.enterText(fields.at(1), '246810');
      await tester.enterText(fields.at(2), '246810');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await tester.pump();
      expect(
        find.text('The second PIN must differ from the first.'),
        findsOneWidget,
      );
      expect(manager.exists, isFalse);
    });

    testWidgets('IMG-011 set-up makes both vaults and opens the empty one', (
      tester,
    ) async {
      await open(tester);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246810');
      final set = find.widgetWithText(FilledButton, 'Set up');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await settleReal(tester);
      expect(find.text('The vault is empty'), findsOneWidget);
      expect(root.listSync().whereType<Directory>(), hasLength(2));
    });

    testWidgets('IMG-011 the second vault is explained honestly', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('two vaults'), findsOneWidget);
      expect(find.textContaining('examines this phone'), findsOneWidget);
    });

    testWidgets('IMG-011 a device with no screen lock is told so', (
      tester,
    ) async {
      crypto.failPlainOpen = VaultCryptoError.notEnrolled;
      await open(tester);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246810');
      final set = find.widgetWithText(FilledButton, 'Set up');
      await tester.ensureVisible(set);
      await tester.tap(set);
      await settleReal(tester);
      expect(find.textContaining('Set a screen lock'), findsOneWidget);
      expect(manager.exists, isFalse);
    });
  });

  group('IMG-011 the PIN pad', () {
    testWidgets('IMG-011 the right PIN opens the vault, a wrong one says so', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4', 'two.mp4']);
      await open(tester);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await typePin(tester, '111111');
      expect(find.text("That PIN doesn't open the vault."), findsOneWidget);
      expect(find.bySemanticsLabel('one.mp4'), findsNothing);
      await typePin(tester, '246810');
      expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
      expect(find.bySemanticsLabel('two.mp4'), findsOneWidget);
    });

    testWidgets(
      'IMG-011 the other PIN opens the other vault with the same screen',
      (tester) async {
        await seeded(tester, names: ['real.mp4'], otherNames: ['cat.mp4']);
        await open(tester);
        await typePin(tester, '135790');
        expect(find.bySemanticsLabel('cat.mp4'), findsOneWidget);
        expect(find.bySemanticsLabel('real.mp4'), findsNothing);
      },
    );

    testWidgets('IMG-011 the two vaults show exactly the same controls', (
      tester,
    ) async {
      await seeded(tester);
      await open(tester);
      await typePin(tester, '246810');
      final real = everyText(tester);
      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      await typePin(tester, '135790');
      expect(everyText(tester), real);
      // The menu offers the same items too.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final decoyMenu = everyText(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      await typePin(tester, '246810');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(everyText(tester), decoyMenu);
    });

    testWidgets(
      'IMG-011 the lock screen is the same with or without a second PIN',
      (tester) async {
        await seeded(tester);
        await open(tester);
        final withSecond = everyText(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => manager.reset());
        await tester.runAsync(
          () => manager.setUp(pin: '246810').then((r) => r.vault!.close()),
        );
        await open(tester);
        expect(everyText(tester), withSecond);
      },
    );

    testWidgets(
      'IMG-011 too many wrong PINs ask to wait, and say for how long',
      (tester) async {
        await seeded(tester);
        await open(tester);
        for (var i = 0; i < 4; i++) {
          await typePin(tester, '111111');
        }
        expect(find.textContaining('Try again in 30 seconds'), findsOneWidget);
        await typePin(tester, '246810');
        expect(find.textContaining('Try again in'), findsOneWidget);
      },
    );

    testWidgets('IMG-011 the keys are labelled for a screen reader', (
      tester,
    ) async {
      await seeded(tester);
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(find.bySemanticsLabel('Digit 7'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete last digit'), findsOneWidget);
      await tester.tap(find.text('7'));
      await tester.pump();
      expect(find.bySemanticsLabel('1 digit entered'), findsOneWidget);
      handle.dispose();
    });
  });

  group('IMG-011 fingerprint', () {
    testWidgets('IMG-011 the button is there only when it was turned on', (
      tester,
    ) async {
      await seeded(tester);
      await open(tester);
      expect(find.text('Use fingerprint'), findsNothing);
      await typePin(tester, '246810');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fingerprint unlock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anyone can make you'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Open with fingerprint'),
      );
      await settleReal(tester);
      expect(
        find.text('The fingerprint now opens this vault.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Lock'));
      await settleReal(tester);
      expect(find.text('Use fingerprint'), findsOneWidget);
      await tester.tap(find.text('Use fingerprint'));
      await settleReal(tester);
      expect(find.byTooltip('Lock'), findsOneWidget);
    });

    testWidgets('IMG-011 backing out of the prompt leaves it locked', (
      tester,
    ) async {
      await seeded(tester);
      await tester.runAsync(() async {
        final v = (await manager.openWithPin('246810')).vault!;
        await manager.setFingerprint(v, enabled: true);
        await v.close();
      });
      crypto.failBiometricOpen = VaultCryptoError.cancelled;
      await open(tester);
      await tester.tap(find.text('Use fingerprint'));
      await settleReal(tester);
      expect(find.text('The vault stayed locked.'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets(
      'IMG-011 a new fingerprint on the phone is explained, the PIN still works',
      (tester) async {
        await seeded(tester);
        await tester.runAsync(() async {
          final v = (await manager.openWithPin('246810')).vault!;
          await manager.setFingerprint(v, enabled: true);
          await v.close();
        });
        crypto.invalidateBiometricKey();
        await open(tester);
        await tester.tap(find.text('Use fingerprint'));
        await settleReal(tester);
        expect(
          find.textContaining('fingerprints on this phone changed'),
          findsOneWidget,
        );
        expect(find.text('Use fingerprint'), findsNothing);
        await typePin(tester, '246810');
        expect(find.byTooltip('Lock'), findsOneWidget);
      },
    );
  });

  group('IMG-011 locking', () {
    testWidgets('IMG-011 Lock closes the vault and the keystore handle', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4']);
      await open(tester);
      await typePin(tester, '246810');
      expect(crypto.openHandles, 1);
      await tester.tap(find.byTooltip('Lock'));
      await settleReal(tester);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.bySemanticsLabel('one.mp4'), findsNothing);
      expect(crypto.openHandles, 0);
    });

    testWidgets('IMG-011 leaving the app locks it', (tester) async {
      await seeded(tester, names: ['one.mp4']);
      await open(tester);
      await typePin(tester, '246810');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleReal(tester);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(crypto.openHandles, 0);
    });

    testWidgets('IMG-011 locking closes the dialogs opened over the vault', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4']);
      await open(tester);
      await typePin(tester, '246810');
      await tester.longPress(find.bySemanticsLabel('one.mp4'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete for good'));
      await tester.pumpAndSettle();
      expect(find.textContaining("can't be undone"), findsOneWidget);
      tester
          .element(find.byType(AlertDialog))
          .findAncestorStateOfType<NavigatorState>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AlertDialog)),
      );
      container.read(vaultSessionProvider.notifier).lock();
      await settleReal(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets('IMG-011 leaving the screen locks the vault', (tester) async {
      await seeded(tester);
      await open(tester);
      await typePin(tester, '246810');
      await tester.pageBack();
      await settleReal(tester);
      expect(crypto.openHandles, 0);
    });

    testWidgets(
      'IMG-011 the window is hidden from screenshots while any vault screen is up',
      (tester) async {
        await seeded(tester);
        await open(tester);
        expect(window.calls, [true]);
        await typePin(tester, '246810');
        await tester.pageBack();
        await settleReal(tester);
        expect(window.calls, [true, false]);
      },
    );
  });

  group('IMG-011 inside the vault', () {
    testWidgets('IMG-011 deleting for good asks first and removes the file', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4', 'two.mp4']);
      await open(tester);
      await typePin(tester, '246810');
      await tester.longPress(find.bySemanticsLabel('one.mp4'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete for good'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete for good'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete for good'));
      await settleReal(tester);
      expect(find.bySemanticsLabel('one.mp4'), findsNothing);
      expect(find.bySemanticsLabel('two.mp4'), findsOneWidget);
    });

    testWidgets(
      'IMG-011 taking out saves a copy and then removes it from the vault',
      (tester) async {
        await seeded(tester, names: ['one.mp4']);
        await open(tester);
        await typePin(tester, '246810');
        await tester.longPress(find.bySemanticsLabel('one.mp4'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Take out'));
        await settleReal(
          tester,
          until: find.text('1 photo taken out of the vault.'),
        );
        expect(storage.saved, ['one.mp4']);
        expect(find.text('1 photo taken out of the vault.'), findsOneWidget);
        expect(find.bySemanticsLabel('one.mp4'), findsNothing);
      },
    );

    testWidgets(
      'IMG-011 adding from the picker says the originals stay and skips what it cannot read',
      (tester) async {
        await seeded(tester);
        await open(tester);
        await typePin(tester, '246810');
        storage.picks.add(
          PickedFile(
            uri: Uri.parse('file:///nonexistent/a.jpg'),
            name: 'a.jpg',
          ),
        );
        await tester.tap(find.byTooltip('Add photos'));
        await tester.pumpAndSettle();
        expect(find.textContaining('stay where they are'), findsOneWidget);
        expect(find.textContaining('64 MB'), findsOneWidget);
        await tester.tap(find.text('Choose photos'));
        await settleReal(tester);
        expect(find.textContaining('1 file was skipped'), findsOneWidget);
      },
    );

    testWidgets(
      'IMG-011 a new PIN replaces the old one and turns the fingerprint off',
      (tester) async {
        await seeded(tester, names: ['one.mp4']);
        await open(tester);
        await typePin(tester, '246810');
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change PIN'));
        await tester.pumpAndSettle();
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), '999999');
        await tester.enterText(fields.at(1), '999999');
        await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
        await settleReal(tester, until: find.byType(SnackBar));
        expect(find.textContaining('PIN changed'), findsOneWidget);
        await tester.tap(find.byTooltip('Lock'));
        await settleReal(tester);
        await typePin(tester, '246810');
        expect(find.text("That PIN doesn't open the vault."), findsOneWidget);
        await typePin(tester, '999999');
        expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
      },
    );

    Future<void> changePinTo(WidgetTester tester, String pin) async {
      // Every outcome of a Change PIN ends in one message on a snackbar.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), pin);
      await tester.enterText(fields.at(1), pin);
      await tester.tap(find.widgetWithText(FilledButton, 'Change PIN'));
      await settleReal(tester, until: find.byType(SnackBar));
    }

    testWidgets('IMG-011 the other vault PIN is refused as a new PIN', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4']);
      await open(tester);
      await typePin(tester, '246810');
      await changePinTo(tester, '135790');
      expect(find.text('Choose a different PIN.'), findsOneWidget);
      // Nothing changed: the old PIN still opens it and the other opens its own.
      await tester.tap(find.byTooltip('Lock'));
      await settleReal(tester);
      await typePin(tester, '246810');
      expect(find.bySemanticsLabel('one.mp4'), findsOneWidget);
    });

    testWidgets('IMG-011 a plain Change PIN does not mention the fingerprint', (
      tester,
    ) async {
      await seeded(tester);
      await open(tester);
      await typePin(tester, '246810');
      await changePinTo(tester, '999999');
      expect(find.text('PIN changed.'), findsOneWidget);
    });

    testWidgets(
      'IMG-011 the fingerprint stays on when the other vault changes its PIN',
      (tester) async {
        await seeded(tester);
        await tester.runAsync(() async {
          final v = (await manager.openWithPin('246810')).vault!;
          await manager.setFingerprint(v, enabled: true);
          await v.close();
        });
        await open(tester);
        await typePin(tester, '135790');
        await changePinTo(tester, '999999');
        expect(find.text('PIN changed.'), findsOneWidget);
        expect(await tester.runAsync(() => manager.fingerprintOn), isTrue);
      },
    );

    testWidgets(
      'IMG-011 changing the PIN of the vault with the fingerprint keeps it on',
      (tester) async {
        await seeded(tester);
        await tester.runAsync(() async {
          final v = (await manager.openWithPin('246810')).vault!;
          await manager.setFingerprint(v, enabled: true);
          await v.close();
        });
        await open(tester);
        await typePin(tester, '246810');
        await changePinTo(tester, '999999');
        expect(find.text('PIN changed.'), findsOneWidget);
        expect(await tester.runAsync(() => manager.fingerprintOn), isTrue);
      },
    );

    testWidgets('IMG-011 the fingerprint is explained before it is turned on', (
      tester,
    ) async {
      await seeded(tester);
      await open(tester);
      await typePin(tester, '246810');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fingerprint unlock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anyone can make you'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleReal(tester);
      expect(await tester.runAsync(() => manager.fingerprintOn), isFalse);
    });
  });

  group('IMG-011 a lost key', () {
    testWidgets('IMG-011 says so and offers to start over after a question', (
      tester,
    ) async {
      await seeded(tester, names: ['one.mp4']);
      crypto.loseKeys();
      await open(tester);
      await typePin(tester, '246810');
      expect(find.textContaining('key is gone'), findsOneWidget);
      await tester.tap(find.text('Reset the vault'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the vault?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(manager.exists, isTrue);
      await tester.tap(find.text('Reset the vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete the vault'));
      await settleReal(tester);
      expect(manager.exists, isFalse);
      expect(find.text('Set up the vault'), findsOneWidget);
    });
  });

  testWidgets('IMG-011 if the key cannot be deleted nothing is deleted', (
    tester,
  ) async {
    await seeded(tester, names: ['one.mp4']);
    crypto.loseKeys();
    await open(tester);
    await typePin(tester, '246810');
    crypto.failReset = VaultCryptoError.unavailable;
    await tester.tap(find.text('Reset the vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete the vault'));
    await settleReal(tester);
    expect(manager.exists, isTrue);
    expect(find.textContaining("isn't available"), findsOneWidget);
    expect(find.text('Reset the vault'), findsOneWidget);
  });

  testWidgets(
    'IMG-011 where the platform has no OS crypto the vault says it is not available',
    (tester) async {
      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultManagerProvider.overrideWith(
              (ref) async =>
                  throw const PlatformCapabilityUnavailable('vaultCrypto'),
            ),
            secureWindowProvider.overrideWithValue(window),
            libraryDatabaseProvider.overrideWithValue(db),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: VaultScreen(),
          ),
        ),
      );
      await settleReal(tester);
      expect(
        find.textContaining("isn't available on this device"),
        findsOneWidget,
      );
    },
  );
}
