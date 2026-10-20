import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/imaging_api.pigeon.dart';
import 'package:mediahro/platform/imaging.dart';
import 'package:mediahro/platform/platform_facades.dart'
    show PlatformCapabilityUnavailable;

/// [ImagingFacade] on Android (ADR-037, `ImagingModule.kt`): `ImageDecoder`
/// (subsample, region, HEIF sequences, Ultra HDR gain maps, PQ/HLG),
/// the MediaStore thumbnail cache, `HeifWriter` HEIC, `WallpaperManager`,
/// the print framework, the clipboard, `android.media.FaceDetector` (no ML
/// Kit, ADR-034) and `noBackupFilesDir`.
///
/// Errors: a missing image throws [PathNotFoundException], a refused one
/// [PathAccessException], an operation the device cannot do [UnsupportedError],
/// anything else [FileSystemException]. [configureScreensaver] throws
/// [PlatformCapabilityUnavailable] (desktop only).
final class AndroidImaging implements ImagingFacade {
  AndroidImaging({ImagingHostApi? api}) : _api = api ?? ImagingHostApi();

  final ImagingHostApi _api;

  @override
  Future<ImagingSupport> support() => _call(() async {
    final s = await _api.support();
    return ImagingSupport(
      decodable: s.decodable.toSet(),
      encodable: s.encodable.toSet(),
      hdrDisplay: s.hdrDisplay,
      wallpaperTargets: {
        for (final t in s.wallpaperTargets) WallpaperTarget.values[t.index],
      },
      print: s.print,
      faces: s.faces,
    );
  });

  @override
  Future<PlatformImage> decode(
    Uri uri, {
    int? maxEdge,
    Rect? region,
    int frame = 0,
    bool keepHdr = false,
  }) => _call(
    () async => _image(
      await _api.decode(
        DecodeRequestMsg(
          uri: '$uri',
          maxEdge: maxEdge,
          region: region == null
              ? null
              : ImageRegionMsg(
                  left: region.left,
                  top: region.top,
                  right: region.right,
                  bottom: region.bottom,
                ),
          frame: frame,
          keepHdr: keepHdr,
        ),
      ),
    ),
    uri,
  );

  @override
  Future<PlatformImage?> thumbnail(Uri uri, int size) => _call(() async {
    final t = await _api.thumbnail('$uri', size);
    return t == null ? null : _image(t);
  }, uri);

  @override
  Future<Uint8List> encode(
    PlatformImage image,
    String format, {
    int quality = 90,
    Uint8List? exif,
  }) => _call(
    () => _api.encode(
      PlatformImageMsg(
        width: image.width,
        height: image.height,
        pixels: image.pixels,
        f16: image.f16,
        frames: image.frames,
        hdr: image.hdr,
      ),
      format,
      quality,
      exif,
    ),
  );

  @override
  Future<HdrImageView?> openHdrView(Uri uri) => _call(() async {
    final type = await _api.openHdrView('$uri');
    return type == null ? null : _HdrView(type, _api);
  }, uri);

  @override
  Future<void> setWallpaper(Uri image, WallpaperTarget target) => _call(
    () => _api.setWallpaper('$image', switch (target) {
      WallpaperTarget.home => WallpaperTargetMsg.home,
      WallpaperTarget.lock => WallpaperTargetMsg.lock,
      WallpaperTarget.both => WallpaperTargetMsg.both,
      WallpaperTarget.desktop => throw UnsupportedError(
        'A desktop wallpaper does not exist on Android.',
      ),
    }),
    image,
  );

  @override
  Future<bool> printImages(List<Uri> images, PrintLayout layout) => _call(
    () => _api.printImages(
      [for (final i in images) '$i'],
      PrintLayoutMsg(
        perPage: layout.perPage,
        fill: layout.fill,
        captions: layout.captions,
      ),
    ),
  );

  @override
  Future<void> copyImage(Uri image) =>
      _call(() => _api.copyImage('$image'), image);

  @override
  Future<List<DetectedFace>> detectFaces(Uri image) => _call(() async {
    final faces = await _api.detectFaces('$image');
    return [
      for (final f in faces)
        DetectedFace(Rect.fromLTRB(f.left, f.top, f.right, f.bottom)),
    ];
  }, image);

  @override
  Future<void> configureScreensaver(
    ScreensaverConfig config, {
    bool openSettings = false,
  }) async => throw const PlatformCapabilityUnavailable('screensaver');

  @override
  Future<Uri> noBackupDirectory(String name) =>
      _call(() async => Uri.parse(await _api.noBackupDirectory(name)));

  static PlatformImage _image(PlatformImageMsg m) => PlatformImage(
    width: m.width,
    height: m.height,
    pixels: m.pixels,
    f16: m.f16,
    frames: m.frames,
    hdr: m.hdr,
  );
}

final class _HdrView implements HdrImageView {
  _HdrView(this.viewType, this._api);

  @override
  final String viewType;

  final ImagingHostApi _api;

  /// Flutter lays the platform view out itself on Android.
  @override
  Future<void> setFrame(Rect logicalRect) async {}

  @override
  Future<void> close() => _call(_api.closeHdrView);
}

Future<T> _call<T>(Future<T> Function() op, [Uri? uri]) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    final path = e.details is String ? e.details as String : '${uri ?? ''}';
    final message = e.message ?? e.code;
    if (e.code == 'unsupported') throw UnsupportedError(message);
    throw switch (e.code) {
      'notFound' => PathNotFoundException(path, OSError(message), message),
      'permissionDenied' => PathAccessException(
        path,
        OSError(message),
        message,
      ),
      _ => FileSystemException(message, path),
    };
  }
}
