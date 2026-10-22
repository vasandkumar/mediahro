import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_engine/src/mpv/mp4_gapless.dart' show LocalVirtualFile;
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// AUD-043 (batch 6): disposing an engine closed the probe's file while the
/// stream protocol still had a read pending, and `RandomAccessFile.close`
/// throws `An async operation is currently pending`.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('local-vf-');
    file = File('${dir.path}/big.bin')
      ..writeAsBytesSync(Uint8List.fromList(List.generate(4 << 20, (i) => i)));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'AUD-043 closing while a read is pending lets the read finish',
    () async {
      final vf = LocalVirtualFile(file);
      await vf.read(0, 16); // opens the handle
      final pending = vf.read(1 << 20, 2 << 20); // in flight
      await vf.close(); // must not throw
      final data = await pending;
      expect(data, hasLength(2 << 20));
      expect(data.first, (1 << 20) & 0xff);
    },
  );

  test(
    'AUD-043 closing behind several queued reads waits for all of them',
    () async {
      final vf = LocalVirtualFile(file);
      await vf.read(0, 16);
      final reads = [for (var i = 0; i < 5; i++) vf.read(i * 1024, 512 << 10)];
      await vf.close();
      final all = await Future.wait(reads);
      expect(all.map((d) => d.length), everyElement(512 << 10));
    },
  );

  test('AUD-043 a read asked for after close is refused', () async {
    final vf = LocalVirtualFile(file);
    await vf.read(0, 16);
    await vf.close();
    await expectLater(
      vf.read(0, 16),
      throwsA(
        isA<VirtualFileException>().having(
          (e) => e.error,
          'error',
          VirtualFileError.closed,
        ),
      ),
    );
  });

  test(
    'AUD-043 a read asked for before close is served even if it runs after it',
    () async {
      final vf = LocalVirtualFile(file);
      // Closed before the first read ever opened a handle.
      final read = vf.read(0, 16);
      final close = vf.close();
      // The read was asked for first, so it is served; close waits behind it.
      expect(await read, hasLength(16));
      await close;
      await expectLater(vf.read(0, 16), throwsA(isA<VirtualFileException>()));
    },
  );

  test('AUD-043 closing twice, or a file never read, is harmless', () async {
    final vf = LocalVirtualFile(file);
    await vf.close();
    await vf.close();
    final never = LocalVirtualFile(file);
    await never.close();
  });

  test(
    'AUD-043 the file can be deleted after close (the handle is released)',
    () async {
      final vf = LocalVirtualFile(file);
      await vf.read(0, 16);
      await vf.close();
      file.deleteSync();
      expect(file.existsSync(), isFalse);
    },
  );
}
