import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_imaging.dart';
import 'package:mediahro/platform/android/gen/imaging_api.pigeon.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// The Dart half of lane C4a's ImagingFacade (ADR-037).
final class _FakeImaging extends ImagingHostApi {
  DecodeRequestMsg? decoded;
  PlatformException? failure;
  final calls = <String>[];

  void _maybeFail() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<ImagingSupportMsg> support() async => ImagingSupportMsg(
    decodable: ['heic', 'heif'],
    encodable: ['heic'],
    hdrDisplay: true,
    wallpaperTargets: [WallpaperTargetMsg.home, WallpaperTargetMsg.both],
    print: true,
    faces: true,
  );

  @override
  Future<PlatformImageMsg> decode(DecodeRequestMsg request) async {
    decoded = request;
    _maybeFail();
    return PlatformImageMsg(
      width: 2,
      height: 1,
      pixels: Uint8List(8),
      f16: false,
      frames: 3,
      hdr: true,
    );
  }

  @override
  Future<PlatformImageMsg?> thumbnail(String uri, int size) async => null;

  @override
  Future<Uint8List> encode(
    PlatformImageMsg image,
    String format,
    int quality,
    Uint8List? exif,
  ) async {
    calls.add('encode:$format:$quality:${exif?.length}');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<String?> openHdrView(String uri) async => 'mediahro/hdr_image';

  @override
  Future<void> closeHdrView() async => calls.add('closeHdr');

  @override
  Future<void> setWallpaper(String uri, WallpaperTargetMsg target) async =>
      calls.add('wallpaper:${target.name}');

  @override
  Future<bool> printImages(List<String> images, PrintLayoutMsg layout) async {
    calls.add('print:${images.length}:${layout.perPage}');
    return true;
  }

  @override
  Future<void> copyImage(String uri) async => calls.add('copy:$uri');

  @override
  Future<List<DetectedFaceMsg>> detectFaces(String uri) async => [
    DetectedFaceMsg(left: 0.1, top: 0.2, right: 0.3, bottom: 0.5),
  ];

  @override
  Future<String> noBackupDirectory(String name) async =>
      'file:///data/no_backup/$name';
}

void main() {
  late _FakeImaging api;
  late AndroidImaging imaging;
  setUp(() {
    api = _FakeImaging();
    imaging = AndroidImaging(api: api);
  });

  test('IMG-001 support maps the OS decoders and encoders', () async {
    final s = await imaging.support();
    expect(s.decodable, {'heic', 'heif'});
    expect(s.encodable, {'heic'});
    expect(s.hdrDisplay, isTrue);
    expect(s.wallpaperTargets, {WallpaperTarget.home, WallpaperTarget.both});
    expect(s.print && s.faces, isTrue);
    expect(s.screensaver, isFalse);
  });

  test('IMG-002 decode passes subsample, region, frame and HDR', () async {
    final img = await imaging.decode(
      Uri.parse('content://media/external/images/media/7'),
      maxEdge: 1024,
      region: const Rect.fromLTRB(1, 2, 30, 40),
      frame: 2,
      keepHdr: true,
    );
    final r = api.decoded!;
    expect(r.uri, 'content://media/external/images/media/7');
    expect(r.maxEdge, 1024);
    expect(
      [r.region!.left, r.region!.top, r.region!.right, r.region!.bottom],
      [1, 2, 30, 40],
    );
    expect(r.frame, 2);
    expect(r.keepHdr, isTrue);
    expect((img.width, img.height, img.frames, img.hdr), (2, 1, 3, true));
  });

  test('IMG-002 native errors become the file exceptions', () async {
    final u = Uri.parse('file:///x.heic');
    api.failure = PlatformException(code: 'notFound', message: 'gone');
    await expectLater(imaging.decode(u), throwsA(isA<PathNotFoundException>()));
    api.failure = PlatformException(code: 'permissionDenied');
    await expectLater(imaging.decode(u), throwsA(isA<PathAccessException>()));
    api.failure = PlatformException(code: 'unsupported', message: 'no');
    await expectLater(imaging.decode(u), throwsA(isA<UnsupportedError>()));
    api.failure = PlatformException(code: 'decodeFailed', message: 'bad');
    await expectLater(imaging.decode(u), throwsA(isA<FileSystemException>()));
  });

  test('IMG-003 no OS thumbnail yet is null', () async {
    expect(await imaging.thumbnail(Uri.parse('file:///a.jpg'), 256), isNull);
  });

  test('IMG-010 encode HEIC with quality and EXIF', () async {
    final out = await imaging.encode(
      PlatformImage(width: 1, height: 1, pixels: Uint8List(4)),
      'heic',
      quality: 80,
      exif: Uint8List(5),
    );
    expect(out, [1, 2, 3]);
    expect(api.calls, ['encode:heic:80:5']);
  });

  test('IMG-002 the HDR still view is an Android platform view', () async {
    final view = await imaging.openHdrView(Uri.parse('file:///a.heic'));
    expect(view!.viewType, 'mediahro/hdr_image');
    await view.setFrame(const Rect.fromLTWH(0, 0, 1, 1));
    await view.close();
    expect(api.calls, ['closeHdr']);
  });

  test('IMG-015 wallpaper, print, copy', () async {
    final u = Uri.parse('file:///a.jpg');
    await imaging.setWallpaper(u, WallpaperTarget.both);
    expect(
      await imaging.printImages([u, u, u], const PrintLayout(perPage: 4)),
      isTrue,
    );
    await imaging.copyImage(u);
    expect(api.calls, ['wallpaper:both', 'print:3:4', 'copy:file:///a.jpg']);
    await expectLater(
      imaging.setWallpaper(u, WallpaperTarget.desktop),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('IMG-005 faces come back as normalised rects', () async {
    final faces = await imaging.detectFaces(Uri.parse('file:///a.jpg'));
    expect(faces.single.bounds, const Rect.fromLTRB(0.1, 0.2, 0.3, 0.5));
    expect(faces.single.featurePrint, isNull);
  });

  test('IMG-018 the screensaver is desktop only', () async {
    await expectLater(
      imaging.configureScreensaver(const ScreensaverConfig(images: [])),
      throwsA(isA<PlatformCapabilityUnavailable>()),
    );
  });

  test('IMG-011 the vault directory is a never-backed-up file URI', () async {
    expect(
      await imaging.noBackupDirectory('vault'),
      Uri.parse('file:///data/no_backup/vault'),
    );
  });
}
