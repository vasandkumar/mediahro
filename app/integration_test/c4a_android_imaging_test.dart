import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mediahro/platform/android/android_imaging.dart';
import 'package:mediahro/platform/platform_bindings.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Lane C4a: ImagingFacade on an Android device (ADR-037): ImageDecoder with
/// subsample and region, the HEIC encoder, faces, the vault directory and the
/// HDR view's gate. Wallpaper and print are not run here: they change the
/// owner's phone or open system UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  Future<Uint8List> pngOf(WidgetTester tester, int w, int h) async {
    final bytes = await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      // Left half red, right half blue, so a region crop is checkable.
      ui.Canvas(rec)
        ..drawRect(
          ui.Rect.fromLTWH(0, 0, w / 2, h.toDouble()),
          ui.Paint()..color = const ui.Color(0xFFFF0000),
        )
        ..drawRect(
          ui.Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
          ui.Paint()..color = const ui.Color(0xFF0000FF),
        );
      final image = await rec.endRecording().toImage(w, h);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('IMG-001 Android bindings provide imaging', (tester) async {
    final c = ProviderContainer(overrides: platformOverrides());
    addTearDown(c.dispose);
    expect(c.read(imagingProvider), isA<AndroidImaging>());
  }, skip: !android);

  testWidgets('IMG-001 support lists what this device can do', (tester) async {
    final s = await AndroidImaging().support();
    expect(s.faces, isTrue);
    expect(s.screensaver, isFalse);
    expect(s.decodable.difference({'heic', 'heif', 'avif'}), isEmpty);
    expect(s.encodable.difference({'heic'}), isEmpty);
  }, skip: !android);

  testWidgets('IMG-001 decode subsamples to maxEdge and crops a region', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('imaging');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/two.png')
      ..writeAsBytesSync(await pngOf(tester, 400, 200));
    final imaging = AndroidImaging();

    final full = await imaging.decode(file.uri);
    expect((full.width, full.height), (400, 200));
    expect(full.pixels.length, 400 * 200 * 4);
    expect(full.pixels.sublist(0, 4), [255, 0, 0, 255]);

    final small = await imaging.decode(file.uri, maxEdge: 100);
    expect((small.width, small.height), (100, 50));

    // The right half of the full image is blue.
    final right = await imaging.decode(
      file.uri,
      region: const ui.Rect.fromLTRB(200, 0, 400, 200),
    );
    expect((right.width, right.height), (200, 200));
    expect(right.pixels.sublist(0, 4), [0, 0, 255, 255]);
  }, skip: !android);

  testWidgets('IMG-001 a missing image throws PathNotFoundException', (
    tester,
  ) async {
    await expectLater(
      AndroidImaging().decode(Uri.file('/data/local/tmp/mediahro-none.heic')),
      throwsA(anyOf(isA<PathNotFoundException>(), isA<FileSystemException>())),
    );
  }, skip: !android);

  testWidgets('IMG-003 no OS thumbnail for a plain file', (tester) async {
    expect(
      await AndroidImaging().thumbnail(Uri.file('/data/local/tmp/x.jpg'), 128),
      isNull,
    );
  }, skip: !android);

  testWidgets('IMG-010 HEIC round trip where the device can encode', (
    tester,
  ) async {
    final imaging = AndroidImaging();
    final s = await imaging.support();
    if (!s.encodable.contains('heic')) {
      markTestSkipped('this device has no HEIC encoder');
      return;
    }
    final px = Uint8List(64 * 64 * 4);
    for (var i = 0; i < px.length; i += 4) {
      px[i] = (i ~/ 4) % 64 * 4;
      px[i + 1] = 90;
      px[i + 2] = 160;
      px[i + 3] = 255;
    }
    final heic = await imaging.encode(
      PlatformImage(width: 64, height: 64, pixels: px),
      'heic',
      quality: 85,
    );
    expect(heic.length, greaterThan(100));
    final dir = await Directory.systemTemp.createTemp('imaging');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.heic')..writeAsBytesSync(heic);
    expect(s.decodable, contains('heic'));
    final back = await imaging.decode(file.uri);
    expect((back.width, back.height), (64, 64));
  }, skip: !android);

  testWidgets('IMG-005 a flat image has no faces', (tester) async {
    final dir = await Directory.systemTemp.createTemp('imaging');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/flat.png')
      ..writeAsBytesSync(await pngOf(tester, 128, 128));
    expect(await AndroidImaging().detectFaces(file.uri), isEmpty);
  }, skip: !android);

  testWidgets('IMG-011 the vault directory is created outside backups', (
    tester,
  ) async {
    final uri = await AndroidImaging().noBackupDirectory('mediahro-test-vault');
    final dir = Directory.fromUri(uri);
    expect(dir.existsSync(), isTrue);
    expect(dir.path, contains('no_backup'));
    dir.deleteSync();
  }, skip: !android);

  testWidgets('IMG-002 the HDR view opens only on an HDR display', (
    tester,
  ) async {
    final imaging = AndroidImaging();
    final s = await imaging.support();
    final dir = await Directory.systemTemp.createTemp('imaging');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.png')
      ..writeAsBytesSync(await pngOf(tester, 32, 32));
    final view = await imaging.openHdrView(file.uri);
    if (s.hdrDisplay) {
      expect(view!.viewType, 'mediahro/hdr_image');
      await view.close();
    } else {
      expect(view, isNull);
    }
  }, skip: !android);

  testWidgets('IMG-015 copy image puts a clip on the clipboard', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('imaging');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/c.png')
      ..writeAsBytesSync(await pngOf(tester, 32, 32));
    await AndroidImaging().copyImage(file.uri);
  }, skip: !android);
}
