import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

/// Draws SVG pictures for the viewer, the thumbnails and the editor
/// (IMG-001) with `flutter_svg`'s compiler.
///
/// An SVG is only ever read from bytes the app already holds (from a file or
/// source through the virtual file system): this class takes no URL, uses
/// `SvgBytesLoader` and never `SvgNetworkLoader`, and the compiler loads no
/// external resource (an `<image>` whose href is not an inline `data:` URI is
/// skipped), so opening an SVG never reaches the network (PRIV-004). A check
/// in `tools/lints/check_rules.dart` keeps it that way.
///
/// Vector pictures have no pixel size, so the picture gets a virtual canvas:
/// its own size scaled so the long edge is at least [minEdge] (and at most
/// [maxEdge]). The viewer treats that as the source size, which makes zooming
/// into regions crisp.
final class SvgRasteriser {
  SvgRasteriser({
    this.maxBytes = 8 << 20,
    this.minEdge = 2048,
    this.maxEdge = 8192,
    this.maxPixels = 64 << 20,
  });

  /// Largest file drawn; bigger ones are refused (the parser runs on the
  /// file's text).
  final int maxBytes;
  final int minEdge;
  final int maxEdge;

  /// Largest picture rendered at once.
  final int maxPixels;

  final LinkedHashMap<String, PictureInfo> _cache = LinkedHashMap();

  /// Whether [bytes] look like an SVG document: an `<svg` element in the
  /// first kibibyte (after an optional byte-order mark, XML declaration,
  /// comments or doctype).
  static bool looksLikeSvg(Uint8List bytes) {
    final n = bytes.length < 1024 ? bytes.length : 1024;
    return String.fromCharCodes(bytes, 0, n).contains('<svg');
  }

  Future<PictureInfo> _load(Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw const CodecUnsupported('the SVG is too large to draw');
    }
    final key = '${bytes.length}:${sha1.convert(bytes)}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final PictureInfo info;
    try {
      info = await vg.loadPicture(SvgBytesLoader(bytes), null);
    } on Object catch (e) {
      throw CodecUnsupported('cannot read this SVG: $e');
    }
    if (!info.size.width.isFinite ||
        !info.size.height.isFinite ||
        info.size.width <= 0 ||
        info.size.height <= 0) {
      info.picture.dispose();
      throw const CodecUnsupported('the SVG has no size');
    }
    _cache[key] = info;
    while (_cache.length > 3) {
      _cache.remove(_cache.keys.first)?.picture.dispose();
    }
    return info;
  }

  /// The virtual canvas size of the picture in [bytes].
  Future<(int width, int height)> size(Uint8List bytes) async {
    final s = (await _load(bytes)).size;
    return _virtual(s.width, s.height);
  }

  (int, int) _virtual(double w, double h) {
    final long = w > h ? w : h;
    final target = long < minEdge ? minEdge : (long > maxEdge ? maxEdge : long);
    final k = target / long;
    return (
      (w * k).round().clamp(1, maxEdge),
      (h * k).round().clamp(1, maxEdge),
    );
  }

  /// Draws the picture (or [region] of its virtual canvas) reduced by
  /// [scale] (at most 1).
  Future<PixelFrame> render(
    Uint8List bytes, {
    ImageRegion? region,
    double scale = 1,
  }) async {
    final info = await _load(bytes);
    final (vw, vh) = _virtual(info.size.width, info.size.height);
    final r = region ?? ImageRegion(0, 0, vw, vh);
    final s = scale.clamp(0.0001, 1.0);
    final ow = (r.width * s).ceil().clamp(1, maxEdge);
    final oh = (r.height * s).ceil().clamp(1, maxEdge);
    if (ow * oh > maxPixels) {
      throw const CodecUnsupported('the SVG would be drawn too large');
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(ow / r.width, oh / r.height)
      ..translate(-r.left.toDouble(), -r.top.toDouble())
      ..scale(vw / info.size.width, vh / info.size.height)
      ..drawPicture(info.picture);
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(ow, oh);
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) throw const CodecUnsupported('SVG drawing failed');
      return PixelFrame(
        width: ow,
        height: oh,
        rgba: Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
        sourceWidth: vw,
        sourceHeight: vh,
      );
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  /// Drops the parsed pictures held in memory.
  void dispose() {
    for (final i in _cache.values) {
      i.picture.dispose();
    }
    _cache.clear();
  }
}
