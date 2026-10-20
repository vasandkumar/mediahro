import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/images/metadata/bytes.dart';
import 'package:meta/meta.dart';

/// One IPTC-IIM dataset (record:dataset = value bytes).
@immutable
final class IptcDataset {
  const IptcDataset(this.record, this.dataset, this.value);

  final int record;
  final int dataset;
  final Uint8List value;
}

/// IPTC IIM (IPTC 4.2) reader-writer. Datasets the app does not manage are
/// kept byte for byte.
final class IptcData {
  IptcData(this.datasets);

  factory IptcData.parse(Uint8List b) {
    final out = <IptcDataset>[];
    var p = 0;
    while (p + 5 <= b.length && out.length < 10000) {
      if (b[p] != 0x1C) {
        p++;
        continue;
      }
      final rec = b[p + 1];
      final ds = b[p + 2];
      var len = (b[p + 3] << 8) | b[p + 4];
      var start = p + 5;
      if (len & 0x8000 != 0) {
        // Extended dataset: the low bits give the length of the length.
        final n = len & 0x7fff;
        if (n > 4 || start + n > b.length) break;
        len = 0;
        for (var i = 0; i < n; i++) {
          len = (len << 8) | b[start + i];
        }
        start += n;
      }
      if (start + len > b.length) break;
      out.add(
        IptcDataset(rec, ds, Uint8List.fromList(b.sublist(start, start + len))),
      );
      p = start + len;
    }
    return IptcData(out);
  }

  final List<IptcDataset> datasets;

  static const objectName = 5;
  static const keywords = 25;
  static const dateCreated = 55;
  static const timeCreated = 60;
  static const byline = 80;
  static const city = 90;
  static const country = 101;
  static const headline = 105;
  static const credit = 110;
  static const copyright = 116;
  static const caption = 120;

  /// 1:90 = ESC % G declares UTF-8.
  bool get isUtf8 => datasets.any(
    (d) =>
        d.record == 1 &&
        d.dataset == 90 &&
        d.value.length >= 3 &&
        d.value[0] == 0x1B &&
        d.value[1] == 0x25 &&
        d.value[2] == 0x47,
  );

  String _decode(Uint8List v) {
    if (isUtf8) return utf8.decode(v, allowMalformed: true);
    try {
      return utf8.decode(v);
    } on FormatException {
      return latin1.decode(v);
    }
  }

  List<String> all(int dataset) => [
    for (final d in datasets)
      if (d.record == 2 && d.dataset == dataset) _decode(d.value).trim(),
  ];

  String? first(int dataset) {
    final a = all(dataset);
    return a.isEmpty ? null : a.first;
  }

  /// Replaces record-2 [dataset] with [values] (none removes it).
  void put(int dataset, List<String> values) {
    datasets.removeWhere((d) => d.record == 2 && d.dataset == dataset);
    for (final v in values) {
      datasets.add(IptcDataset(2, dataset, Uint8List.fromList(utf8.encode(v))));
    }
  }

  Uint8List encode() {
    // Switch the block to UTF-8 so the values we write decode correctly.
    datasets.removeWhere((d) => d.record == 1 && d.dataset == 90);
    // Records in ascending order, datasets in their original order.
    final records = {for (final d in datasets) d.record}.toList()..sort();
    final sorted = [
      for (final r in {1, ...records})
        if (r == 1) ...[
          IptcDataset(1, 90, Uint8List.fromList(const [0x1B, 0x25, 0x47])),
          ...datasets.where((d) => d.record == 1),
        ] else
          ...datasets.where((d) => d.record == r),
    ];
    final s = ByteSink();
    if (!sorted.any((d) => d.record == 2 && d.dataset == 0)) {
      // 2:00 RecordVersion must lead record 2.
      final at = sorted.indexWhere((d) => d.record == 2);
      if (at >= 0) {
        sorted.insert(at, IptcDataset(2, 0, Uint8List.fromList(const [0, 4])));
      }
    }
    for (final d in sorted) {
      s
        ..u8(0x1C)
        ..u8(d.record)
        ..u8(d.dataset);
      if (d.value.length < 0x8000) {
        s.u16(d.value.length);
      } else {
        s
          ..u16(0x8004)
          ..u32(d.value.length);
      }
      s.bytes(d.value);
    }
    return s.take();
  }

  Map<String, String> displayMap() {
    const names = {
      objectName: 'ObjectName',
      keywords: 'Keywords',
      dateCreated: 'DateCreated',
      timeCreated: 'TimeCreated',
      byline: 'By-line',
      city: 'City',
      country: 'Country-PrimaryLocationName',
      headline: 'Headline',
      credit: 'Credit',
      copyright: 'CopyrightNotice',
      caption: 'Caption-Abstract',
    };
    return {
      for (final e in names.entries)
        if (all(e.key).isNotEmpty) 'IPTC:${e.value}': all(e.key).join(', '),
    };
  }
}

/// Photoshop image resource block ("8BIM" records in JPEG APP13).
final class PhotoshopResources {
  PhotoshopResources(this.records);

  factory PhotoshopResources.parse(Uint8List b) {
    final out = <(int, Uint8List, Uint8List)>[];
    final v = ByteView(b);
    var p = 0;
    while (p + 12 <= b.length && out.length < 4096) {
      if (!v.startsWith(const [0x38, 0x42, 0x49, 0x4D], p)) break; // 8BIM
      final id = v.u16(p + 4);
      final nameLen = b[p + 6];
      var q = p + 7 + nameLen;
      if ((nameLen + 1).isOdd) q++;
      if (q + 4 > b.length) break;
      final name = b.sublist(p + 6, q);
      final size = v.u32(q);
      q += 4;
      if (q + size > b.length) break;
      out.add((id, Uint8List.fromList(name), b.sublist(q, q + size)));
      p = q + size + (size.isOdd ? 1 : 0);
    }
    return PhotoshopResources(out);
  }

  static const iptcId = 0x0404;

  /// (resource id, padded Pascal name, data).
  final List<(int, Uint8List, Uint8List)> records;

  Uint8List? get iptc {
    for (final r in records) {
      if (r.$1 == iptcId) return r.$3;
    }
    return null;
  }

  set iptc(Uint8List? data) {
    final at = records.indexWhere((r) => r.$1 == iptcId);
    if (data == null) {
      if (at >= 0) records.removeAt(at);
      return;
    }
    final rec = (iptcId, Uint8List.fromList(const [0, 0]), data);
    if (at >= 0) {
      records[at] = rec;
    } else {
      records.add(rec);
    }
  }

  Uint8List encode() {
    final s = ByteSink();
    for (final (id, name, data) in records) {
      s
        ..ascii('8BIM')
        ..u16(id)
        ..bytes(name)
        ..u32(data.length)
        ..bytes(data);
      if (data.length.isOdd) s.u8(0);
    }
    return s.take();
  }
}
