import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/core/parsers/xml_lite.dart' show XmlFormatException;
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/bytes.dart';
import 'package:mediahro/images/metadata/exif_tags.dart';
import 'package:mediahro/images/metadata/icc.dart';
import 'package:mediahro/images/metadata/iptc.dart';
import 'package:mediahro/images/metadata/iso_bmff.dart';
import 'package:mediahro/images/metadata/jpeg.dart';
import 'package:mediahro/images/metadata/png.dart';
import 'package:mediahro/images/metadata/tiff.dart';
import 'package:mediahro/images/metadata/webp.dart';
import 'package:mediahro/images/metadata/xmp.dart';
import 'package:meta/meta.dart';

const _tiffXmp = 0x02BC;
const _tiffIptc = 0x83BB;
const _tiffIcc = 0x8773;

/// The metadata blocks found in one image file, still undecoded.
@immutable
final class MetadataBlocks {
  const MetadataBlocks({
    required this.format,
    this.width = 0,
    this.height = 0,
    this.exif,
    this.xmp,
    this.photoshop,
    this.iptc,
    this.icc,
    this.animated = false,
    this.hasMpf = false,
  });

  final ImageFormat format;
  final int width;
  final int height;

  /// A TIFF structure: the EXIF block, or the whole file for TIFF and RAW.
  final Uint8List? exif;
  final String? xmp;

  /// JPEG APP13 payload (Photoshop resources) holding the IPTC block.
  final Uint8List? photoshop;

  /// IPTC-IIM records.
  final Uint8List? iptc;
  final Uint8List? icc;
  final bool animated;

  /// JPEG Multi-Picture Format directory (gain-map / Ultra HDR files).
  final bool hasMpf;
}

/// Runs [f] over untrusted bytes (PRIV-005). A hostile file makes a parser
/// throw [MetadataFormatException] or, where it indexes bytes directly, a
/// [RangeError]; both mean "no result" and never crash the caller.
T? _guard<T extends Object>(T? Function() f) {
  try {
    return f();
    // Parsers index untrusted data; a bad offset is an expected input here.
    // ignore: avoid_catching_errors
  } on RangeError {
    return null;
  } on MetadataFormatException {
    return null;
  }
}

/// Finds the metadata blocks of [bytes] without decoding pixels.
MetadataBlocks readMetadataBlocks(Uint8List bytes, {String? extension}) {
  final head = Uint8List.sublistView(
    bytes,
    0,
    bytes.length < 1024 ? bytes.length : 1024,
  );
  final format = sniffImageFormat(head, extension: extension);
  return _guard(
        () => switch (format) {
          ImageFormat.jpeg => _jpeg(bytes),
          ImageFormat.png => _png(bytes),
          ImageFormat.webp => _webp(bytes),
          ImageFormat.heic || ImageFormat.avif => _iso(bytes, format),
          ImageFormat.jxl => _jxl(bytes),
          ImageFormat.tiff || ImageFormat.raw => _tiff(bytes, format),
          _ => MetadataBlocks(format: format),
        },
      ) ??
      MetadataBlocks(format: format);
}

MetadataBlocks _jpeg(Uint8List b) {
  final j = JpegFile.parse(b);
  final ps = j.photoshop;
  return MetadataBlocks(
    format: ImageFormat.jpeg,
    width: j.width,
    height: j.height,
    exif: j.exif,
    xmp: j.xmp,
    photoshop: ps,
    iptc: ps == null ? null : PhotoshopResources.parse(ps).iptc,
    icc: j.icc,
    hasMpf: j.hasMpf,
  );
}

MetadataBlocks _png(Uint8List b) {
  final p = PngFile.parse(b);
  return MetadataBlocks(
    format: ImageFormat.png,
    width: p.width,
    height: p.height,
    exif: p.exif,
    xmp: p.xmp,
    icc: p.icc,
    animated: p.isAnimated,
  );
}

MetadataBlocks _webp(Uint8List b) {
  final w = WebpFile.parse(b);
  final (width, height) = w.size;
  return MetadataBlocks(
    format: ImageFormat.webp,
    width: width,
    height: height,
    exif: w.exif,
    xmp: w.xmp,
    icc: w.icc,
    animated: w.isAnimated,
  );
}

MetadataBlocks _iso(Uint8List b, ImageFormat format) {
  final f = IsoFile.parse(b);
  final (w, h) = f.size;
  return MetadataBlocks(
    format: format,
    width: w,
    height: h,
    exif: f.exif,
    xmp: f.xmp,
  );
}

MetadataBlocks _jxl(Uint8List b) {
  final f = JxlFile.parse(b);
  return MetadataBlocks(format: ImageFormat.jxl, exif: f.exif, xmp: f.xmp);
}

MetadataBlocks _tiff(Uint8List b, ImageFormat format) {
  final t = TiffStructure.parse(b);
  final xmp = t.entry(IfdKind.ifd0, _tiffXmp);
  final iptc = t.entry(IfdKind.ifd0, _tiffIptc);
  final icc = t.entry(IfdKind.ifd0, _tiffIcc);
  var w = t.intValue(IfdKind.ifd0, 0x0100) ?? 0;
  var h = t.intValue(IfdKind.ifd0, 0x0101) ?? 0;
  if (format == ImageFormat.raw) {
    // RAW pixel size comes from LibRaw; the EXIF size tags are the fallback.
    w = t.intValue(IfdKind.exif, 0xA002) ?? w;
    h = t.intValue(IfdKind.exif, 0xA003) ?? h;
  }
  return MetadataBlocks(
    format: format,
    width: w,
    height: h,
    exif: b,
    xmp: xmp == null ? null : utf8.decode(xmp.raw, allowMalformed: true),
    iptc: iptc?.raw,
    icc: icc?.raw,
  );
}

/// Everything the viewer and the info sheet need from one file.
@immutable
final class ParsedMetadata {
  const ParsedMetadata({
    required this.blocks,
    required this.metadata,
    this.orientation = 1,
    this.isPanorama = false,
    this.hasGainMap = false,
    this.motionVideoLength,
  });

  final MetadataBlocks blocks;
  final ImageMetadata metadata;

  /// EXIF orientation 1–8.
  final int orientation;
  final bool isPanorama;

  /// Gain-map HDR (IMG-002): hdrgm XMP, or an MPF directory next to it.
  final bool hasGainMap;

  /// Size in bytes of the Motion Photo video appended to the file, if any.
  final int? motionVideoLength;
}

/// Reads and merges EXIF, IPTC, XMP and ICC (IMG-006). Precedence follows
/// the usual photo-app rule: XMP over IPTC over EXIF for titles, captions,
/// keywords and ratings; EXIF GPS over XMP GPS; EXIF capture time over XMP.
ParsedMetadata parseMetadata(Uint8List bytes, {String? extension}) {
  final blocks = readMetadataBlocks(bytes, extension: extension);
  final exifBlock = blocks.exif;
  final tiff = exifBlock == null
      ? null
      : _guard(() => TiffStructure.parse(exifBlock));
  XmpPacket? xmp;
  if (blocks.xmp != null) {
    try {
      xmp = XmpPacket.parse(blocks.xmp!.trim());
    } on XmlFormatException {
      xmp = null;
    }
  }
  final iptc = blocks.iptc == null ? null : IptcData.parse(blocks.iptc!);

  String? ifd0(int tag) => tiff?.string(IfdKind.ifd0, tag);
  final exifDate = tiff == null ? null : _exifCaptured(tiff);
  final iptcDate = iptc == null ? null : _iptcDate(iptc);
  String? xp(int tag) => tiff?.string(IfdKind.ifd0, tag);

  final keywords = <String>{
    ...?xmp?.keywords,
    ...?iptc?.all(IptcData.keywords),
    for (final k in (xp(TiffTag.xpKeywords) ?? '').split(';'))
      if (k.trim().isNotEmpty) k.trim(),
  }.toList();

  final description =
      xmp?.description ??
      iptc?.first(IptcData.caption) ??
      _nonEmpty(ifd0(TiffTag.imageDescription));
  final title =
      xmp?.title ??
      iptc?.first(IptcData.objectName) ??
      _nonEmpty(xp(TiffTag.xpTitle));

  var rating = xmp?.rating;
  if (rating == null && tiff != null) {
    rating = tiff.intValue(IfdKind.ifd0, TiffTag.rating);
    if (rating == null) {
      final pct = tiff.intValue(IfdKind.ifd0, TiffTag.ratingPercent);
      if (pct != null) {
        rating = pct == 0 ? 0 : (pct / 25).ceil().clamp(1, 5);
      }
    }
  }

  final gps = tiff == null ? null : _exifGps(tiff);
  final fix = gps ?? xmp?.location;
  final loc = fix != null && fix.$1 == 0 && fix.$2 == 0 ? null : fix;

  final make = _nonEmpty(ifd0(TiffTag.make));
  final model = _nonEmpty(ifd0(TiffTag.model));
  final lens = _nonEmpty(tiff?.string(IfdKind.exif, TiffTag.lensModel));

  final display = <String, String>{
    if (tiff != null) ...exifDisplayMap(tiff),
    ...?iptc?.displayMap(),
    ...?xmp?.displayMap(),
  };

  final icc = blocks.icc == null ? null : iccDescription(blocks.icc!);

  final metadata = ImageMetadata(
    captured: (exifDate ?? xmp?.captured ?? iptcDate)?.toLocal(),
    latitude: loc?.$1,
    longitude: loc?.$2,
    title: _nonEmpty(title),
    description: _nonEmpty(description),
    keywords: keywords,
    rating: rating,
    cameraMake: make,
    cameraModel: model,
    lens: lens,
    exif: display,
    iccProfileName: icc,
  );
  final hdr = xmp?.hasGainMap ?? false;
  return ParsedMetadata(
    blocks: blocks,
    metadata: metadata,
    orientation: (tiff?.intValue(IfdKind.ifd0, TiffTag.orientation) ?? 1).clamp(
      1,
      8,
    ),
    isPanorama: xmp?.isPanorama ?? false,
    hasGainMap: hdr,
    motionVideoLength: xmp?.motionPhotoVideoLength,
  );
}

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

DateTime? _iptcDate(IptcData d) {
  final date = d.first(IptcData.dateCreated);
  if (date == null || date.length != 8) return null;
  final time = d.first(IptcData.timeCreated) ?? '000000';
  final t = time.length >= 6 ? time.substring(0, 6) : '000000';
  return DateTime.tryParse(
    '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}'
    'T${t.substring(0, 2)}:${t.substring(2, 4)}:${t.substring(4, 6)}',
  );
}

/// `2024:05:01 10:20:30` plus an optional `+02:00` offset; with an offset the
/// result is the UTC instant, without it the wall-clock time as local.
DateTime? parseExifDate(String? s, {String? offset}) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(s);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (p[0] == 0 || p[1] == 0 || p[2] == 0) return null;
  final o = offset == null
      ? null
      : RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(offset.trim());
  if (o == null) return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  final mins = int.parse(o.group(2)!) * 60 + int.parse(o.group(3)!);
  final utc = DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]);
  return utc.subtract(Duration(minutes: o.group(1) == '-' ? -mins : mins));
}

DateTime? _exifCaptured(TiffStructure t) {
  final original = t.string(IfdKind.exif, TiffTag.dateTimeOriginal);
  final off = t.string(IfdKind.exif, 0x9011);
  return parseExifDate(original, offset: off) ??
      parseExifDate(t.string(IfdKind.exif, TiffTag.dateTimeDigitized)) ??
      parseExifDate(t.string(IfdKind.ifd0, TiffTag.dateTime));
}

(double, double)? _exifGps(TiffStructure t) {
  double? coord(int tag, int refTag) {
    final v = t.doublesOf(IfdKind.gps, tag);
    if (v == null || v.isEmpty) return null;
    var d = v[0];
    if (v.length > 1) d += v[1] / 60;
    if (v.length > 2) d += v[2] / 3600;
    final ref = t.string(IfdKind.gps, refTag) ?? '';
    return ref == 'S' || ref == 'W' ? -d : d;
  }

  final lat = coord(TiffTag.gpsLat, TiffTag.gpsLatRef);
  final lon = coord(TiffTag.gpsLon, TiffTag.gpsLonRef);
  if (lat == null || lon == null) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  if (lat == 0 && lon == 0) return null; // the "no fix" placeholder
  return (lat, lon);
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// What an edit produced: the rewritten file, or XMP for a sidecar when the
/// format cannot carry the change (RAW, a HEIC without the needed item).
@immutable
final class MetadataWriteResult {
  const MetadataWriteResult.file(Uint8List this.file) : sidecar = null;
  const MetadataWriteResult.sidecar(String this.sidecar) : file = null;

  final Uint8List? file;
  final String? sidecar;
}

String _exifDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}:${two(d.month)}:${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String _exifOffset(DateTime d) {
  final off = d.isUtc ? Duration.zero : d.timeZoneOffset;
  final m = off.inMinutes.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${off.isNegative ? '-' : '+'}${two(m ~/ 60)}:${two(m % 60)}';
}

/// Applies [edit] to an EXIF editor.
void _applyExif(TiffEditor e, ImageMetadataEdit edit) {
  final v = e.values;
  final captured = edit.captured;
  if (captured != null) {
    final s = _exifDate(captured);
    final off = _exifOffset(captured);
    e
      ..set(IfdKind.exif, v.ascii(TiffTag.dateTimeOriginal, s))
      ..set(IfdKind.exif, v.ascii(TiffTag.dateTimeDigitized, s))
      ..set(IfdKind.exif, v.ascii(0x9011, off))
      ..set(IfdKind.exif, v.ascii(0x9012, off))
      ..remove(IfdKind.exif, TiffTag.subSecTimeOriginal)
      ..remove(IfdKind.exif, 0x9292);
  }
  if (edit.clearLocation) {
    e.drop(IfdKind.gps);
  } else if (edit.location != null) {
    final (lat, lon) = edit.location!;
    List<double> dms(double x) {
      final a = x.abs();
      final d = a.floorToDouble();
      final mf = (a - d) * 60;
      final m = mf.floorToDouble();
      return [d, m, (mf - m) * 60];
    }

    e
      ..set(
        IfdKind.gps,
        v.bytes(TiffTag.gpsVersion, [2, 2, 0, 0], type: TiffType.byte),
      )
      ..set(IfdKind.gps, v.ascii(TiffTag.gpsLatRef, lat < 0 ? 'S' : 'N'))
      ..set(IfdKind.gps, v.rationals(TiffTag.gpsLat, dms(lat), den: 1000000))
      ..set(IfdKind.gps, v.ascii(TiffTag.gpsLonRef, lon < 0 ? 'W' : 'E'))
      ..set(IfdKind.gps, v.rationals(TiffTag.gpsLon, dms(lon), den: 1000000));
  }
  void textOrRemove(
    IfdKind k,
    int tag,
    String? text,
    TiffEntry Function(String) make,
  ) {
    if (text == null) return;
    if (text.isEmpty) {
      e.remove(k, tag);
    } else {
      e.set(k, make(text));
    }
  }

  textOrRemove(
    IfdKind.ifd0,
    TiffTag.xpTitle,
    edit.title,
    (s) => v.xp(TiffTag.xpTitle, s),
  );
  textOrRemove(
    IfdKind.ifd0,
    TiffTag.imageDescription,
    edit.description,
    (s) => v.ascii(TiffTag.imageDescription, s),
  );
  final kw = edit.keywords;
  if (kw != null) {
    textOrRemove(
      IfdKind.ifd0,
      TiffTag.xpKeywords,
      kw.join(';'),
      (s) => v.xp(TiffTag.xpKeywords, s),
    );
  }
  final rating = edit.rating;
  if (rating != null) {
    final r = rating.clamp(0, 5);
    const pct = [0, 1, 25, 50, 75, 99];
    e
      ..set(IfdKind.ifd0, v.shorts(TiffTag.rating, [r]))
      ..set(IfdKind.ifd0, v.shorts(TiffTag.ratingPercent, [pct[r]]));
  }
}

/// Applies [edit] to an XMP packet.
void _applyXmp(XmpPacket x, ImageMetadataEdit edit) {
  final captured = edit.captured;
  if (captured != null) {
    final s = formatXmpDate(captured);
    x.setSimple('exif:DateTimeOriginal', s);
    for (final p in const ['photoshop:DateCreated', 'xmp:CreateDate']) {
      if (x.get(p) != null) x.setSimple(p, s);
    }
  }
  if (edit.clearLocation) {
    const [
      'exif:GPSLatitude',
      'exif:GPSLongitude',
      'exif:GPSAltitude',
      'exif:GPSAltitudeRef',
      'exif:GPSVersionID',
    ].forEach(x.remove);
  } else if (edit.location != null) {
    final (lat, lon) = edit.location!;
    x
      ..setSimple('exif:GPSVersionID', '2.2.0.0')
      ..setSimple('exif:GPSLatitude', formatXmpGps(lat, latitude: true))
      ..setSimple('exif:GPSLongitude', formatXmpGps(lon, latitude: false));
  }
  if (edit.title != null) {
    x.setAlt('dc:title', edit.title!.isEmpty ? null : edit.title);
  }
  if (edit.description != null) {
    x.setAlt(
      'dc:description',
      edit.description!.isEmpty ? null : edit.description,
    );
  }
  if (edit.keywords != null) x.setBag('dc:subject', edit.keywords);
  if (edit.rating != null) {
    x.setSimple('xmp:Rating', edit.rating!.clamp(0, 5).toString());
  }
}

bool _touchesIptc(ImageMetadataEdit e) =>
    e.title != null || e.description != null || e.keywords != null;

/// Applies [edit] to the IIM block; the result replaces the old one.
Uint8List _applyIptc(Uint8List? current, ImageMetadataEdit edit) {
  final d = current == null ? IptcData([]) : IptcData.parse(current);
  if (edit.title != null) {
    d.put(IptcData.objectName, edit.title!.isEmpty ? const [] : [edit.title!]);
  }
  if (edit.description != null) {
    d.put(
      IptcData.caption,
      edit.description!.isEmpty ? const [] : [edit.description!],
    );
  }
  if (edit.keywords != null) d.put(IptcData.keywords, edit.keywords!);
  return d.encode();
}

XmpPacket _xmpOf(String? text) {
  if (text == null) return XmpPacket.empty();
  try {
    return XmpPacket.parse(text.trim());
  } on XmlFormatException {
    return XmpPacket.empty();
  }
}

TiffEditor _exifEditorOf(Uint8List? exif) {
  final t = exif == null ? null : _guard(() => TiffStructure.parse(exif));
  return t == null ? TiffEditor.empty() : TiffEditor(t);
}

/// Largest EXIF block a JPEG APP1 segment can hold.
const int _jpegExifMax = jpegMaxSegmentData - 6;

Uint8List _exifBytesFor(TiffEditor e, {required bool jpeg}) {
  final full = e.build();
  if (!jpeg || full.length <= _jpegExifMax) return full;
  final compact = e.compact(dropThumbnail: true);
  if (compact.length > _jpegExifMax) {
    throw const MetadataFormatException('EXIF too large for a JPEG segment');
  }
  return compact;
}

String _xmpFor(XmpPacket x, {int limit = 1 << 22}) {
  final padded = x.serialize();
  return padded.length <= limit ? padded : x.serialize(padding: 0);
}

/// XMP sidecar text for [edit], starting from an existing sidecar when given
/// (RAW and formats the app does not write, IMG-006).
String sidecarFor(ImageMetadataEdit edit, {String? existing}) {
  final x = _xmpOf(existing);
  _applyXmp(x, edit);
  return x.serialize(padding: 0);
}

/// Writes [edit] into [bytes]. RAW and unsupported containers return a
/// sidecar; the file formats the spec lists (JPEG, PNG, WebP, TIFF, HEIC,
/// plus AVIF and JPEG XL) are rewritten in place of the original bytes.
MetadataWriteResult writeMetadata(
  Uint8List bytes,
  ImageMetadataEdit edit, {
  String? extension,
  String? existingSidecar,
}) {
  final head = Uint8List.sublistView(
    bytes,
    0,
    bytes.length < 1024 ? bytes.length : 1024,
  );
  final format = sniffImageFormat(head, extension: extension);
  MetadataWriteResult sidecar() =>
      MetadataWriteResult.sidecar(sidecarFor(edit, existing: existingSidecar));
  MetadataWriteResult? write() {
    switch (format) {
      case ImageFormat.jpeg:
        final j = JpegFile.parse(bytes);
        final ed = _exifEditorOf(j.exif);
        _applyExif(ed, edit);
        final x = _xmpOf(j.xmp);
        _applyXmp(x, edit);
        Patch<Uint8List>? ps;
        if (_touchesIptc(edit)) {
          final res = j.photoshop == null
              ? PhotoshopResources([])
              : PhotoshopResources.parse(j.photoshop!);
          res.iptc = _applyIptc(res.iptc, edit);
          ps = Patch.set(res.encode());
        }
        // JPEG segments are small, so the padding goes first when too big.
        final xmpText = _xmpFor(x, limit: jpegMaxSegmentData - 40);
        return MetadataWriteResult.file(
          j.rewrite(
            exif: Patch.set(_exifBytesFor(ed, jpeg: true)),
            xmp: Patch.set(xmpText),
            photoshop: ps,
          ),
        );
      case ImageFormat.png:
        final p = PngFile.parse(bytes);
        final ed = _exifEditorOf(p.exif);
        _applyExif(ed, edit);
        final x = _xmpOf(p.xmp);
        _applyXmp(x, edit);
        return MetadataWriteResult.file(
          p.rewrite(
            exif: Patch.set(_exifBytesFor(ed, jpeg: false)),
            xmp: Patch.set(_xmpFor(x)),
          ),
        );
      case ImageFormat.webp:
        final w = WebpFile.parse(bytes);
        final ed = _exifEditorOf(w.exif);
        _applyExif(ed, edit);
        final x = _xmpOf(w.xmp);
        _applyXmp(x, edit);
        return MetadataWriteResult.file(
          w.rewrite(
            exif: Patch.set(_exifBytesFor(ed, jpeg: false)),
            xmp: Patch.set(_xmpFor(x)),
          ),
        );
      case ImageFormat.jxl:
        final f = JxlFile.parse(bytes);
        final ed = _exifEditorOf(f.exif);
        _applyExif(ed, edit);
        final x = _xmpOf(f.xmp);
        _applyXmp(x, edit);
        return MetadataWriteResult.file(
          f.rewrite(
            exif: Patch.set(_exifBytesFor(ed, jpeg: false)),
            xmp: Patch.set(_xmpFor(x)),
          ),
        );
      case ImageFormat.heic || ImageFormat.avif:
        final f = IsoFile.parse(bytes);
        if (!f.canWriteExif) return sidecar();
        final ed = _exifEditorOf(f.exif);
        _applyExif(ed, edit);
        XmpPacket? x;
        if (f.canWriteXmp) {
          x = _xmpOf(f.xmp);
          _applyXmp(x, edit);
        }
        final out = f.rewrite(
          exif: _exifBytesFor(ed, jpeg: false),
          xmp: x == null ? null : _xmpFor(x),
        );
        return out == null ? sidecar() : MetadataWriteResult.file(out);
      case ImageFormat.tiff:
        final t = TiffStructure.parse(bytes);
        final ed = TiffEditor(t);
        _applyExif(ed, edit);
        final x = _xmpOf(
          t.entry(IfdKind.ifd0, _tiffXmp) == null
              ? null
              : utf8.decode(
                  t.entry(IfdKind.ifd0, _tiffXmp)!.raw,
                  allowMalformed: true,
                ),
        );
        _applyXmp(x, edit);
        final xmpBytes = utf8.encode(_xmpFor(x));
        ed.set(
          IfdKind.ifd0,
          ed.values.bytes(_tiffXmp, xmpBytes, type: TiffType.byte),
        );
        if (_touchesIptc(edit)) {
          final cur = t.entry(IfdKind.ifd0, _tiffIptc)?.raw;
          ed.set(
            IfdKind.ifd0,
            ed.values.bytes(
              _tiffIptc,
              _applyIptc(cur, edit),
              type: TiffType.byte,
            ),
          );
        }
        return MetadataWriteResult.file(ed.build());
      case ImageFormat.gif ||
          ImageFormat.bmp ||
          ImageFormat.ico ||
          ImageFormat.svg ||
          ImageFormat.psd ||
          ImageFormat.exr ||
          ImageFormat.hdr ||
          ImageFormat.dds ||
          ImageFormat.tga ||
          ImageFormat.pnm ||
          ImageFormat.qoi ||
          ImageFormat.raw ||
          ImageFormat.unknown:
        return null;
    }
  }

  return _guard(write) ?? sidecar();
}

/// [bytes] with metadata stripped for sharing (IMG-006, IMG-015):
/// orientation and ICC stay so the image looks the same; everything else
/// (GPS, serials, dates, titles, XMP, IPTC, MakerNote, thumbnails) goes.
/// Returns null for containers that cannot be stripped in place (HEIC, AVIF,
/// RAW): the caller re-encodes the pixels without metadata instead.
Uint8List? stripMetadata(
  Uint8List bytes, {
  String? extension,
  bool keepOrientation = true,
}) {
  final head = Uint8List.sublistView(
    bytes,
    0,
    bytes.length < 1024 ? bytes.length : 1024,
  );
  final format = sniffImageFormat(head, extension: extension);
  Uint8List? keptExif(Uint8List? exif) {
    if (!keepOrientation || exif == null) return null;
    return _guard(() {
      final t = TiffStructure.parse(exif);
      final o = t.intValue(IfdKind.ifd0, TiffTag.orientation);
      if (o == null || o == 1) return null;
      final e = TiffEditor.empty();
      e.set(IfdKind.ifd0, e.values.shorts(TiffTag.orientation, [o]));
      return e.build();
    });
  }

  Patch<Uint8List> exifPatch(Uint8List? exif) {
    final k = keptExif(exif);
    return k == null ? const Patch.remove() : Patch.set(k);
  }

  Uint8List? strip() {
    switch (format) {
      case ImageFormat.jpeg:
        final j = JpegFile.parse(bytes);
        return j.rewrite(
          exif: exifPatch(j.exif),
          xmp: const Patch.remove(),
          photoshop: const Patch.remove(),
        );
      case ImageFormat.png:
        final p = PngFile.parse(bytes);
        return p.rewrite(exif: exifPatch(p.exif), xmp: const Patch.remove());
      case ImageFormat.webp:
        final w = WebpFile.parse(bytes);
        return w.rewrite(exif: exifPatch(w.exif), xmp: const Patch.remove());
      case ImageFormat.jxl:
        final f = JxlFile.parse(bytes);
        return f.rewrite(exif: exifPatch(f.exif), xmp: const Patch.remove());
      case ImageFormat.tiff:
        final t = TiffStructure.parse(bytes);
        final ed = TiffEditor(t)
          ..drop(IfdKind.gps)
          ..remove(IfdKind.ifd0, _tiffXmp)
          ..remove(IfdKind.ifd0, _tiffIptc)
          ..remove(IfdKind.ifd0, TiffTag.xpTitle)
          ..remove(IfdKind.ifd0, TiffTag.xpComment)
          ..remove(IfdKind.ifd0, TiffTag.xpKeywords)
          ..remove(IfdKind.ifd0, TiffTag.xpSubject)
          ..remove(IfdKind.ifd0, TiffTag.imageDescription)
          ..remove(IfdKind.ifd0, TiffTag.artist)
          ..remove(IfdKind.ifd0, TiffTag.copyright);
        return ed.build();
      case ImageFormat.gif ||
          ImageFormat.heic ||
          ImageFormat.avif ||
          ImageFormat.bmp ||
          ImageFormat.ico ||
          ImageFormat.svg ||
          ImageFormat.psd ||
          ImageFormat.exr ||
          ImageFormat.hdr ||
          ImageFormat.dds ||
          ImageFormat.tga ||
          ImageFormat.pnm ||
          ImageFormat.qoi ||
          ImageFormat.raw ||
          ImageFormat.unknown:
        return null;
    }
  }

  return _guard(strip);
}
