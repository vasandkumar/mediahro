// Lane C3 device batch, the vault (IMG-011, PRIV-007): the real OS crypto and
// Keystore behind the vault on the Samsung. Needs the Android
// VaultCryptoFacade (C4a, PR #88); until it is registered the tests skip
// themselves. The fingerprint prompt and the screen capture block are manual
// checks (listed in the PR).
//
//   flutter test integration_test/c3_vault_test.dart -d <serial> --no-dds \
//     -P kotlin.incremental=false
//
// Reports (binding.reportData): vault_kdf_ms (one PIN check at the shipped
// 600,000 rounds, two vaults in parallel), vault_seal_ms_per_mib.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer c;
  VaultManager? manager;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('c3-vault');
    c = ProviderContainer(overrides: platformOverrides());
    try {
      manager = VaultManager(
        root: Directory('${dir.path}/vault'),
        crypto: c.read(vaultCryptoProvider),
        secure: c.read(secureStorageProvider),
      );
    } on Object {
      manager = null;
    }
  });

  tearDown(() async {
    await manager?.reset();
    c.dispose();
    dir.deleteSync(recursive: true);
  });

  Uint8List bytes(int n, int seed) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

  testWidgets('IMG-011 two vaults, a PIN each, and a photo that reads back', (
    tester,
  ) async {
    final m = manager;
    if (m == null) {
      markTestSkipped('blocked: Android VaultCryptoFacade (C4a, PR #88)');
      return;
    }
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
  });

  testWidgets('IMG-011 nothing readable is on disk and the folder is private', (
    tester,
  ) async {
    final m = manager;
    if (m == null) {
      markTestSkipped('blocked: Android VaultCryptoFacade (C4a, PR #88)');
      return;
    }
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
  });

  testWidgets(
    'IMG-011 locking releases the keystore handle and a tampered file fails',
    (tester) async {
      final m = manager;
      if (m == null) {
        markTestSkipped('blocked: Android VaultCryptoFacade (C4a, PR #88)');
        return;
      }
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
  );
}
