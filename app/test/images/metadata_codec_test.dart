import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/images/image_format.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/metadata/bytes.dart';
import 'package:mediahro/images/metadata/iptc.dart';
import 'package:mediahro/images/metadata/iso_bmff.dart';
import 'package:mediahro/images/metadata/jpeg.dart';
import 'package:mediahro/images/metadata/metadata_codec.dart';
import 'package:mediahro/images/metadata/png.dart';
import 'package:mediahro/images/metadata/tiff.dart';
import 'package:mediahro/images/metadata/webp.dart';

import 'fixtures.dart';

const _edit = ImageMetadataEdit(
  location: (48.8584, 2.2945),
  title: 'Eiffel Tower',
  description: 'Evening light on the tower',
  keywords: ['paris', 'landmark', 'night'],
  rating: 4,
);

Uint8List _tail(Uint8List b, int n) => Uint8List.sublistView(b, b.length - n);

void main() {
  group('IMG-001 format detection', () {
    test('IMG-001 sniffs the container formats from magic bytes', () {
      expect(sniffImageFormat(sampleJpeg()), ImageFormat.jpeg);
      expect(sniffImageFormat(samplePng()), ImageFormat.png);
      expect(sniffImageFormat(sampleWebp()), ImageFormat.webp);
      expect(sniffImageFormat(sampleHeic()), ImageFormat.heic);
      expect(sniffImageFormat(sampleTiff()), ImageFormat.tiff);
      expect(
        sniffImageFormat(Uint8List.fromList([0xFF, 0x0A, 0, 0])),
        ImageFormat.jxl,
      );
      expect(
        sniffImageFormat(Uint8List.fromList(utf8.encode('<svg xmlns="x"/>'))),
        ImageFormat.svg,
      );
      expect(sniffImageFormat(Uint8List(16)), ImageFormat.unknown);
    });

    test('IMG-001 TIFF magic with a RAW extension is RAW', () {
      final tiff = sampleTiff();
      expect(sniffImageFormat(tiff, extension: 'NEF'), ImageFormat.raw);
      expect(sniffImageFormat(tiff, extension: '.dng'), ImageFormat.raw);
      expect(sniffImageFormat(tiff, extension: 'tif'), ImageFormat.tiff);
    });

    test('IMG-001 avif and heic are told apart by brand', () {
      final avif = Uint8List.fromList([
        0,
        0,
        0,
        0x18,
        ...'ftypavif'.codeUnits,
        0,
        0,
        0,
        0,
        ...'mif1'.codeUnits, //
        ...'avif'.codeUnits,
      ]);
      expect(sniffImageFormat(avif), ImageFormat.avif);
    });
  });

  group('IMG-006 reading', () {
    test('IMG-006 JPEG EXIF: camera, lens, time, GPS, orientation', () {
      final p = parseMetadata(sampleJpeg(exif: sampleExif()));
      final m = p.metadata;
      expect(m.cameraMake, 'Samsung');
      expect(m.cameraModel, 'SM-M176B');
      expect(m.lens, 'Main 5.4mm f/1.8');
      expect(m.captured, DateTime(2024, 5, 1, 10, 20, 30));
      expect(m.latitude, closeTo(12.975, 1e-6));
      expect(m.longitude, closeTo(77.595833, 1e-5));
      expect(p.orientation, 6);
      expect(p.blocks.width, 4);
      expect(p.blocks.height, 2);
      expect(m.exif['EXIF:Make'], 'Samsung');
      expect(m.exif['EXIF:Orientation'], 'Rotate 90 CW');
    });

    test('IMG-006 little-endian EXIF reads the same as big-endian', () {
      final be = parseMetadata(sampleJpeg(exif: sampleExif()));
      final le = parseMetadata(sampleJpeg(exif: sampleExif(bigEndian: false)));
      expect(le.metadata.latitude, be.metadata.latitude);
      expect(le.metadata.captured, be.metadata.captured);
    });

    test('IMG-006 an EXIF capture offset gives the UTC instant', () {
      final exif = sampleExif();
      final edited = writeMetadata(
        sampleJpeg(exif: exif),
        ImageMetadataEdit(captured: DateTime.utc(2024, 5, 1, 10, 20, 30)),
      ).file!;
      final read = parseMetadata(edited).metadata.captured!;
      expect(read.toUtc(), DateTime.utc(2024, 5, 1, 10, 20, 30));
    });

    test('IMG-006 the GPS "no fix" 0,0 placeholder is ignored', () {
      final exif = sampleExif();
      final zero = writeMetadata(
        sampleJpeg(exif: exif),
        const ImageMetadataEdit(location: (0, 0)),
      ).file!;
      expect(parseMetadata(zero).metadata.latitude, isNull);
    });

    test('IMG-006 XMP wins over IPTC and EXIF for titles and keywords', () {
      final iptc = IptcData([])
        ..put(IptcData.objectName, ['IPTC title'])
        ..put(IptcData.keywords, ['iptc-kw']);
      final ps = PhotoshopResources([])..iptc = iptc.encode();
      final xmp = xmpDoc(
        [
          '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">XMP title</rdf:li>',
          '</rdf:Alt></dc:title>',
          '<dc:subject><rdf:Bag><rdf:li>xmp-kw</rdf:li></rdf:Bag></dc:subject>',
          '<xmp:Rating>5</xmp:Rating>',
        ].join(),
      );
      final p = parseMetadata(
        sampleJpeg(exif: sampleExif(), xmp: xmp, photoshop: ps.encode()),
      );
      expect(p.metadata.title, 'XMP title');
      expect(p.metadata.keywords, containsAll(['xmp-kw', 'iptc-kw']));
      expect(p.metadata.rating, 5);
    });

    test('IMG-006 IPTC fills in when there is no XMP', () {
      final iptc = IptcData([])
        ..put(IptcData.caption, ['A caption'])
        ..put(IptcData.dateCreated, ['20240501'])
        ..put(IptcData.timeCreated, ['101112']);
      final ps = PhotoshopResources([])..iptc = iptc.encode();
      final p = parseMetadata(sampleJpeg(photoshop: ps.encode()));
      expect(p.metadata.description, 'A caption');
      expect(p.metadata.captured, DateTime(2024, 5, 1, 10, 11, 12));
    });

    test('IMG-006 PNG eXIf and iTXt XMP are read', () {
      final xmp = xmpDoc('<xmp:Rating>3</xmp:Rating>');
      final p = parseMetadata(samplePng(exif: sampleExif(), xmp: xmp));
      expect(p.metadata.cameraModel, 'SM-M176B');
      expect(p.metadata.rating, 3);
      expect(p.blocks.width, 4);
    });

    test('IMG-006 WebP EXIF and XMP are read, size from the bitstream', () {
      final p = parseMetadata(sampleWebp(exif: sampleExif()));
      expect(p.metadata.cameraMake, 'Samsung');
      expect((p.blocks.width, p.blocks.height), (4, 2));
      final simple = parseMetadata(sampleWebp());
      expect((simple.blocks.width, simple.blocks.height), (4, 2));
    });

    test('IMG-006 HEIC Exif item (offset-prefixed) and XMP item are read', () {
      final xmp = xmpDoc('<xmp:Rating>2</xmp:Rating>');
      final p = parseMetadata(sampleHeic(exif: sampleExif(), xmp: xmp));
      expect(p.metadata.cameraModel, 'SM-M176B');
      expect(p.metadata.rating, 2);
      expect((p.blocks.width, p.blocks.height), (4, 2));
    });

    test('IMG-006 TIFF reads its own IFDs and embedded XMP', () {
      final xmp = xmpDoc('<xmp:Rating>1</xmp:Rating>');
      final tiff = sampleTiff(
        edit: (e) => e
          ..set(IfdKind.ifd0, e.values.ascii(TiffTag.make, 'Scanner'))
          ..set(
            IfdKind.ifd0,
            e.values.bytes(0x02BC, utf8.encode(xmp), type: TiffType.byte),
          ),
      );
      final p = parseMetadata(tiff);
      expect(p.metadata.cameraMake, 'Scanner');
      expect(p.metadata.rating, 1);
      expect((p.blocks.width, p.blocks.height), (1, 1));
    });

    test('IMG-006 Windows XP tags give title and keywords', () {
      final exif = (() {
        final e = TiffEditor.empty();
        e
          ..set(IfdKind.ifd0, e.values.xp(TiffTag.xpTitle, 'Ünïcode title'))
          ..set(IfdKind.ifd0, e.values.xp(TiffTag.xpKeywords, 'a; b;c'));
        return e.build();
      })();
      final m = parseMetadata(sampleJpeg(exif: exif)).metadata;
      expect(m.title, 'Ünïcode title');
      expect(m.keywords, ['a', 'b', 'c']);
    });

    test('IMG-006 ICC profile description is shown (JPEG APP2 chunks)', () {
      final icc = _iccProfile('Display P3');
      // Two APP2 chunks to cover reassembly.
      final half = icc.length ~/ 2;
      Uint8List chunk(int n, Uint8List d) => Uint8List.fromList([
        0xFF, 0xE2, ((d.length + 16) >> 8) & 0xFF, (d.length + 16) & 0xFF,
        ...'ICC_PROFILE'.codeUnits, 0, n, 2, ...d, //
      ]);
      final base = sampleJpeg();
      final withIcc = Uint8List.fromList([
        ...base.sublist(0, 2),
        ...chunk(1, icc.sublist(0, half)),
        ...chunk(2, icc.sublist(half)),
        ...base.sublist(2),
      ]);
      expect(parseMetadata(withIcc).metadata.iccProfileName, 'Display P3');
    });
  });

  group('IMG-001 panorama, Motion Photo and HDR flags', () {
    test('IMG-001 XMP GPano marks a panorama', () {
      final xmp = xmpDoc(
        ['<GPano:ProjectionType>equirectangular</GPano:ProjectionType>'].join(),
      );
      expect(parseMetadata(sampleJpeg(xmp: xmp)).isPanorama, isTrue);
      expect(parseMetadata(sampleJpeg()).isPanorama, isFalse);
    });

    test('IMG-001 Motion Photo: the trailing video length comes from XMP', () {
      final xmp = xmpDoc(
        [
          '<GCamera:MotionPhoto>1</GCamera:MotionPhoto>',
          '<Container:Directory><rdf:Seq>',
          '<rdf:li><Container:Item Item:Semantic="Primary" Item:Mime="image/jpeg"/></rdf:li>',
          '<rdf:li><Container:Item Item:Semantic="MotionPhoto" Item:Mime="video/mp4" ',
          'Item:Length="12345"/></rdf:li>',
          '</rdf:Seq></Container:Directory>',
        ].join(),
      );
      expect(parseMetadata(sampleJpeg(xmp: xmp)).motionVideoLength, 12345);
    });

    test('IMG-001 legacy MicroVideo offset is honoured', () {
      final xmp = xmpDoc(
        [
          '<GCamera:MicroVideo>1</GCamera:MicroVideo>',
          '<GCamera:MicroVideoOffset>777</GCamera:MicroVideoOffset>',
        ].join(),
      );
      expect(parseMetadata(sampleJpeg(xmp: xmp)).motionVideoLength, 777);
    });

    test('IMG-002 a gain-map directory item marks Ultra HDR', () {
      final xmp = xmpDoc(
        [
          '<Container:Directory><rdf:Seq>',
          '<rdf:li><Container:Item Item:Semantic="Primary"/></rdf:li>',
          '<rdf:li><Container:Item Item:Semantic="GainMap" Item:Mime="image/jpeg" ',
          'Item:Length="900"/></rdf:li></rdf:Seq></Container:Directory>',
        ].join(),
      );
      expect(parseMetadata(sampleJpeg(xmp: xmp)).hasGainMap, isTrue);
      expect(parseMetadata(sampleJpeg()).hasGainMap, isFalse);
    });

    test('IMG-002 hdrgm:Version marks a gain-map image', () {
      final xmp = xmpDoc('<hdrgm:Version>1.0</hdrgm:Version>');
      expect(parseMetadata(sampleJpeg(xmp: xmp)).hasGainMap, isTrue);
    });
  });

  group('IMG-006 writing', () {
    test('IMG-006 JPEG: edits round-trip and the scan data is untouched', () {
      final src = sampleJpeg(exif: sampleExif());
      final r = writeMetadata(
        src,
        ImageMetadataEdit(
          captured: DateTime(2023, 12, 25, 8, 30),
          location: _edit.location,
          title: _edit.title,
          description: _edit.description,
          keywords: _edit.keywords,
          rating: _edit.rating,
        ),
      );
      final out = r.file!;
      final m = parseMetadata(out).metadata;
      expect(m.captured, DateTime(2023, 12, 25, 8, 30));
      expect(m.latitude, closeTo(48.8584, 1e-5));
      expect(m.longitude, closeTo(2.2945, 1e-5));
      expect(m.title, 'Eiffel Tower');
      expect(m.description, 'Evening light on the tower');
      expect(m.keywords, containsAll(['paris', 'landmark', 'night']));
      expect(m.rating, 4);
      // Everything after the header, including the scan, is byte-identical.
      expect(_tail(out, scanData.length + 2), _tail(src, scanData.length + 2));
      // The image still parses as a JPEG of the same size.
      final j = JpegFile.parse(out);
      expect((j.width, j.height), (4, 2));
      // Camera data the edit did not touch survives.
      expect(m.cameraModel, 'SM-M176B');
      expect(m.lens, 'Main 5.4mm f/1.8');
    });

    test('IMG-006 JPEG without any metadata gets EXIF, XMP and IPTC', () {
      final out = writeMetadata(sampleJpeg(), _edit).file!;
      final j = JpegFile.parse(out);
      expect(j.exif, isNotNull);
      expect(j.xmp, isNotNull);
      expect(j.photoshop, isNotNull);
      expect(
        IptcData.parse(PhotoshopResources.parse(j.photoshop!).iptc!)
            .first(IptcData.objectName),
        'Eiffel Tower',
      );
      // JFIF stays the first segment.
      expect(j.segments.first.marker, 0xE0);
    });

    test('IMG-006 JPEG without JFIF puts EXIF right after SOI', () {
      final out = writeMetadata(sampleJpeg(jfif: false), _edit).file!;
      final j = JpegFile.parse(out);
      expect(j.segments.first.marker, 0xE1);
    });

    test(
      'IMG-006 MakerNote keeps its offsets (out-of-line data is not moved)',
      () {
        final exif = sampleExif();
        final before = TiffStructure.parse(exif);
        final noteBefore = before.entry(IfdKind.exif, TiffTag.makerNote)!;
        final out = writeMetadata(
          sampleJpeg(exif: exif),
          const ImageMetadataEdit(rating: 2),
        ).file!;
        final after = TiffStructure.parse(JpegFile.parse(out).exif!);
        final noteAfter = after.entry(IfdKind.exif, TiffTag.makerNote)!;
        expect(noteAfter.offset, noteBefore.offset);
        expect(noteAfter.raw, noteBefore.raw);
      },
    );

    test('IMG-006 clearing the location removes GPS from EXIF and XMP', () {
      final withGps = writeMetadata(
        sampleJpeg(exif: sampleExif()),
        _edit,
      ).file!;
      expect(parseMetadata(withGps).metadata.latitude, isNotNull);
      final cleared = writeMetadata(
        withGps,
        const ImageMetadataEdit(clearLocation: true),
      ).file!;
      final m = parseMetadata(cleared).metadata;
      expect(m.latitude, isNull);
      expect(m.longitude, isNull);
      final j = JpegFile.parse(cleared);
      expect(j.xmp, isNot(contains('GPSLatitude')));
    });

    test('IMG-006 an empty string clears title, description and keywords', () {
      final tagged = writeMetadata(sampleJpeg(), _edit).file!;
      final cleared = writeMetadata(
        tagged,
        const ImageMetadataEdit(title: '', description: '', keywords: []),
      ).file!;
      final m = parseMetadata(cleared).metadata;
      expect(m.title, isNull);
      expect(m.description, isNull);
      expect(m.keywords, isEmpty);
    });

    test('IMG-005 a colour label is written to XMP and can be removed', () {
      final labelled = writeMetadata(
        sampleJpeg(),
        const ImageMetadataEdit(label: 'Red', rating: 3),
      ).file!;
      final p = parseMetadata(labelled);
      expect(p.label, 'Red');
      expect(p.metadata.rating, 3);
      final cleared = writeMetadata(
        labelled,
        const ImageMetadataEdit(label: ''),
      ).file!;
      expect(parseMetadata(cleared).label, isNull);
      expect(parseMetadata(cleared).metadata.rating, 3);
    });

    test('IMG-008 rejected is XMP rating -1 and survives a round trip', () {
      final out = writeMetadata(
        sampleJpeg(),
        const ImageMetadataEdit(rating: -1),
      ).file!;
      expect(parseMetadata(out).metadata.rating, -1);
      final back = writeMetadata(out, const ImageMetadataEdit(rating: 0)).file!;
      expect(parseMetadata(back).metadata.rating, 0);
    });

    test('IMG-006 unrelated XMP properties survive an edit', () {
      final xmp = xmpDoc(
        ['<GPano:ProjectionType>equirectangular</GPano:ProjectionType>'].join(),
      );
      final out = writeMetadata(
        sampleJpeg(xmp: xmp),
        const ImageMetadataEdit(rating: 5),
      ).file!;
      final p = parseMetadata(out);
      expect(p.isPanorama, isTrue);
      expect(p.metadata.rating, 5);
    });

    test(
      'IMG-006 an EXIF block near the segment limit is compacted on edit',
      () {
        final big = TiffEditor(TiffStructure.parse(sampleExif()));
        big.set(
          IfdKind.exif,
          big.values.bytes(TiffTag.makerNote, List.filled(65000, 7)),
        );
        final exif = big.build();
        expect(exif.length, lessThanOrEqualTo(jpegMaxSegmentData - 6));
        final out = writeMetadata(
          sampleJpeg(exif: exif),
          const ImageMetadataEdit(rating: 1, title: 'x'),
        ).file!;
        final after = JpegFile.parse(out).exif!;
        expect(after.length, lessThanOrEqualTo(jpegMaxSegmentData - 6));
        final note = TiffStructure.parse(after)
            .entry(IfdKind.exif, TiffTag.makerNote)!;
        expect(note.raw, hasLength(65000));
        expect(parseMetadata(out).metadata.rating, 1);
      },
    );

    test('IMG-006 PNG: edits round-trip, IDAT untouched, CRCs valid', () {
      final src = samplePng();
      final out = writeMetadata(src, _edit).file!;
      final m = parseMetadata(out).metadata;
      expect(m.title, 'Eiffel Tower');
      expect(m.latitude, closeTo(48.8584, 1e-5));
      final p = PngFile.parse(out);
      expect(
        p.chunks.map((c) => c.type),
        containsAllInOrder(['IHDR', 'eXIf', 'iTXt', 'IDAT', 'IEND']),
      );
      for (final c in p.chunks) {
        final stored = ByteView(out).u32(c.dataStart + c.dataLength);
        expect(
          crc32(out.sublist(c.start + 4, c.dataStart + c.dataLength)),
          stored,
          reason: c.type,
        );
      }
    });

    test('IMG-006 PNG: replacing keeps one eXIf and one XMP chunk', () {
      final once = writeMetadata(samplePng(), _edit).file!;
      final twice = writeMetadata(
        once,
        const ImageMetadataEdit(rating: 2),
      ).file!;
      final types = PngFile.parse(twice).chunks.map((c) => c.type).toList();
      expect(types.where((t) => t == 'eXIf'), hasLength(1));
      expect(types.where((t) => t == 'iTXt'), hasLength(1));
      expect(parseMetadata(twice).metadata.rating, 2);
      expect(parseMetadata(twice).metadata.title, 'Eiffel Tower');
    });

    test('IMG-006 WebP: a simple file becomes extended with correct flags', () {
      final out = writeMetadata(sampleWebp(), _edit).file!;
      final w = WebpFile.parse(out);
      expect(w.chunks.map((c) => c.type), ['VP8X', 'VP8L', 'EXIF', 'XMP ']);
      expect(out[20] & 0x0C, 0x0C);
      expect(w.size, (4, 2));
      expect(ByteView(out, bigEndian: false).u32(4), out.length - 8);
      expect(parseMetadata(out).metadata.title, 'Eiffel Tower');
    });

    test('IMG-006 WebP: an extended file is edited in place of its chunks', () {
      final src = sampleWebp(exif: sampleExif());
      final out = writeMetadata(src, const ImageMetadataEdit(rating: 3)).file!;
      final m = parseMetadata(out).metadata;
      expect(m.rating, 3);
      expect(m.cameraMake, 'Samsung');
    });

    test('IMG-006 TIFF: edits are appended and IFD0 redirected', () {
      final src = sampleTiff();
      final out = writeMetadata(src, _edit).file!;
      expect(out.sublist(8, src.length), src.sublist(8));
      final m = parseMetadata(out).metadata;
      expect(m.title, 'Eiffel Tower');
      expect(m.keywords, contains('night'));
      expect(m.latitude, closeTo(48.8584, 1e-5));
    });

    test('IMG-006 HEIC: the Exif item is retargeted, no other byte moves', () {
      final src = sampleHeic(exif: sampleExif());
      final out = writeMetadata(src, _edit).file!;
      // The original file is a prefix apart from the patched iloc fields.
      expect(out.length, greaterThan(src.length));
      var differing = 0;
      for (var i = 0; i < src.length; i++) {
        if (src[i] != out[i]) differing++;
      }
      expect(differing, lessThanOrEqualTo(8));
      final m = parseMetadata(out).metadata;
      expect(m.title, 'Eiffel Tower');
      expect(m.latitude, closeTo(48.8584, 1e-5));
      expect(m.cameraModel, 'SM-M176B');
      // The new file is still valid ISO BMFF.
      final iso = IsoFile.parse(out);
      expect(iso.size, (4, 2));
    });

    test('IMG-006 HEIC with an XMP item rewrites both items', () {
      final src = sampleHeic(
        exif: sampleExif(),
        xmp: xmpDoc('<xmp:Rating>1</xmp:Rating>'),
      );
      final out = writeMetadata(src, const ImageMetadataEdit(rating: 5)).file!;
      expect(parseMetadata(out).metadata.rating, 5);
    });

    test('IMG-006 HEIC without an Exif item falls back to an XMP sidecar', () {
      final r = writeMetadata(sampleHeic(), _edit);
      expect(r.file, isNull);
      expect(r.sidecar, contains('Eiffel Tower'));
    });

    test('IMG-006 JPEG XL container: Exif and xml boxes are added', () {
      const sig = [
        0,
        0,
        0,
        0x0C,
        0x4A,
        0x58,
        0x4C,
        0x20,
        0x0D,
        0x0A,
        0x87,
        0x0A,
      ];
      final bare = Uint8List.fromList([0xFF, 0x0A, 1, 2, 3, 4]);
      final wrapped = writeMetadata(bare, _edit).file!;
      expect(wrapped.sublist(0, 12), sig);
      final m = parseMetadata(wrapped).metadata;
      expect(m.title, 'Eiffel Tower');
      // Writing again replaces rather than duplicates.
      final again = writeMetadata(
        wrapped,
        const ImageMetadataEdit(rating: 2),
      ).file!;
      final f = JxlFile.parse(again);
      expect(f.boxes.where((b) => b.type == 'Exif'), hasLength(1));
      expect(f.boxes.where((b) => b.type == 'xml '), hasLength(1));
      expect(parseMetadata(again).metadata.title, 'Eiffel Tower');
    });

    test('IMG-006 RAW gets an XMP sidecar and the file is never rewritten', () {
      final raw = sampleTiff();
      final r = writeMetadata(raw, _edit, extension: 'nef');
      expect(r.file, isNull);
      final p = parseMetadata(sampleJpeg(xmp: r.sidecar));
      expect(p.metadata.title, 'Eiffel Tower');
      expect(p.metadata.rating, 4);
    });

    test('IMG-006 a RAW sidecar edit keeps what the existing sidecar had', () {
      final first = writeMetadata(
        sampleTiff(),
        _edit,
        extension: 'cr2',
      ).sidecar!;
      final second = writeMetadata(
        sampleTiff(),
        const ImageMetadataEdit(rating: 1),
        extension: 'cr2',
        existingSidecar: first,
      ).sidecar!;
      final m = parseMetadata(sampleJpeg(xmp: second)).metadata;
      expect(m.rating, 1);
      expect(m.title, 'Eiffel Tower');
    });

    test('IMG-006 unknown data is not rewritten', () {
      final r = writeMetadata(Uint8List(64), _edit);
      expect(r.file, isNull);
      expect(r.sidecar, isNotNull);
    });
  });

  group('IMG-006 strip metadata on share', () {
    test('IMG-006 JPEG: GPS, XMP and IPTC go, orientation stays', () {
      final tagged = writeMetadata(sampleJpeg(exif: sampleExif()), _edit).file!;
      final out = stripMetadata(tagged)!;
      final p = parseMetadata(out);
      expect(p.metadata.latitude, isNull);
      expect(p.metadata.title, isNull);
      expect(p.metadata.cameraMake, isNull);
      expect(p.orientation, 6);
      final j = JpegFile.parse(out);
      expect(j.xmp, isNull);
      expect(j.photoshop, isNull);
      expect(
        _tail(out, scanData.length + 2),
        _tail(tagged, scanData.length + 2),
      );
    });

    test('IMG-006 strip can also drop the orientation', () {
      final out = stripMetadata(
        sampleJpeg(exif: sampleExif()),
        keepOrientation: false,
      )!;
      expect(JpegFile.parse(out).exif, isNull);
    });

    test('IMG-006 PNG and WebP are stripped', () {
      final png = stripMetadata(samplePng(exif: sampleExif(orientation: 1)))!;
      expect(PngFile.parse(png).exif, isNull);
      final webp = stripMetadata(sampleWebp(exif: sampleExif(orientation: 1)))!;
      expect(WebpFile.parse(webp).exif, isNull);
    });

    test('IMG-006 PNG: every text chunk and the modification time go', () {
      final text = [
        ('tEXt', [...'Author'.codeUnits, 0, ...'Jane Doe'.codeUnits]),
        (
          'zTXt',
          [...'Comment'.codeUnits, 0, 0, 0x78, 0x9C, 0x03, 0x00, 0, 0, 0, 1],
        ),
        (
          'iTXt',
          [
            ...'Raw profile type iptc'.codeUnits,
            0, 0, 0, 0, 0,
            ...'location secret'.codeUnits, //
          ],
        ),
        ('tIME', [0x07, 0xE8, 10, 21, 9, 30, 0]),
      ];
      final source = samplePng(
        exif: sampleExif(orientation: 1),
        xmp: xmpDoc('<xmp:Rating>3</xmp:Rating>'),
        extra: text,
      );
      final before = PngFile.parse(source).chunks.map((c) => c.type).toList();
      expect(before, containsAll(['tEXt', 'zTXt', 'iTXt', 'tIME']));
      final out = stripMetadata(source)!;
      final types = PngFile.parse(out).chunks.map((c) => c.type).toList();
      expect(types, ['IHDR', 'IDAT', 'IEND']);
      expect(String.fromCharCodes(out), isNot(contains('Jane Doe')));
      expect(String.fromCharCodes(out), isNot(contains('location secret')));
    });

    test('IMG-006 PNG: orientation stays in a fresh eXIf chunk', () {
      final out = stripMetadata(
        samplePng(
          exif: sampleExif(),
          extra: const [
            ('tEXt', [0x41, 0, 0x42]),
          ],
        ),
      )!;
      expect(PngFile.parse(out).exif, isNotNull);
      expect(parseMetadata(out).orientation, 6);
    });

    test('IMG-006 JPEG: comment segments go with the rest', () {
      final source = sampleJpeg(
        exif: sampleExif(),
        comments: ['shot at the secret cabin', 'Edited with SuperApp'],
      );
      expect(String.fromCharCodes(source), contains('secret cabin'));
      final out = stripMetadata(source)!;
      expect(String.fromCharCodes(out), isNot(contains('secret cabin')));
      expect(String.fromCharCodes(out), isNot(contains('SuperApp')));
      final markers = JpegFile.parse(out).segments.map((s) => s.marker);
      expect(markers, isNot(contains(0xFE)));
      expect(
        _tail(out, scanData.length + 2),
        _tail(source, scanData.length + 2),
      );
    });

    test('IMG-006 TIFF loses GPS and text tags', () {
      final tiff = writeMetadata(sampleTiff(), _edit).file!;
      final m = parseMetadata(stripMetadata(tiff)!).metadata;
      expect(m.latitude, isNull);
      expect(m.title, isNull);
    });

    test('IMG-006 HEIC cannot be stripped in place (caller re-encodes)', () {
      expect(stripMetadata(sampleHeic(exif: sampleExif())), isNull);
    });
  });

  group('PRIV-005 hostile metadata', () {
    test('PRIV-005 truncated and garbled files never throw', () {
      final fixtures = <Uint8List>[
        sampleJpeg(
          exif: sampleExif(),
          xmp: xmpDoc('<xmp:Rating>3</xmp:Rating>'),
        ),
        samplePng(exif: sampleExif()),
        sampleWebp(exif: sampleExif()),
        sampleHeic(
          exif: sampleExif(),
          xmp: xmpDoc('<xmp:Rating>3</xmp:Rating>'),
        ),
        sampleTiff(),
      ];
      final rnd = Random(7);
      for (final f in fixtures) {
        for (var cut = 0; cut < f.length; cut += max(1, f.length ~/ 40)) {
          expect(
            () => parseMetadata(Uint8List.sublistView(f, 0, cut)),
            returnsNormally,
          );
        }
        for (var i = 0; i < 150; i++) {
          final g = Uint8List.fromList(f);
          for (var k = 0; k < 4; k++) {
            g[rnd.nextInt(g.length)] = rnd.nextInt(256);
          }
          expect(() => parseMetadata(g), returnsNormally);
          expect(() => writeMetadata(g, _edit), returnsNormally);
          expect(() => stripMetadata(g), returnsNormally);
        }
      }
    });

    test('PRIV-005 an IFD pointer loop terminates', () {
      final b = ByteSink()
        ..ascii('MM')
        ..u16(42)
        ..u32(8)
        ..u16(0)
        ..u32(8); // next IFD is itself
      final s = TiffStructure.parse(b.take());
      expect(s.chain, hasLength(1));
    });

    test('PRIV-005 a huge IFD entry count is rejected', () {
      final b = ByteSink()
        ..ascii('MM')
        ..u16(42)
        ..u32(8)
        ..u16(0xFFFF)
        ..bytes(List.filled(32, 0));
      final s = TiffStructure.parse(b.take());
      expect(s.chain, isEmpty);
    });

    test('PRIV-005 a tag value that points outside the file is skipped', () {
      final b = ByteSink()
        ..ascii('MM')
        ..u16(42)
        ..u32(8)
        ..u16(1)
        ..u16(TiffTag.make)
        ..u16(2)
        ..u32(100)
        ..u32(0x7FFFFFF0)
        ..u32(0);
      final s = TiffStructure.parse(b.take());
      expect(s.entry(IfdKind.ifd0, TiffTag.make), isNull);
    });

    test('PRIV-005 malformed XMP is ignored, not fatal', () {
      final p = parseMetadata(sampleJpeg(xmp: '<x:xmpmeta><broken'));
      expect(p.metadata.title, isNull);
    });
  });
}

/// A minimal ICC profile with a v2 `desc` tag.
Uint8List _iccProfile(String description) {
  final s = ByteSink();
  final desc = ByteSink()
    ..ascii('desc')
    ..u32(0)
    ..u32(description.length + 1)
    ..ascii(description)
    ..u8(0);
  final descBytes = desc.take();
  s
    ..bytes(List.filled(128, 0))
    ..u32(1)
    ..ascii('desc')
    ..u32(144)
    ..u32(descBytes.length)
    ..bytes(descBytes);
  return s.take();
}
