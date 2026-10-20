import 'dart:convert';
import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/mp4.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';

/// ilst atom of a canonical key, for keys with a native atom.
final Map<String, String> _atomFor = {
  for (final e in mp4TextAtoms.entries) e.value: e.key,
};

/// Freeform (`----:com.apple.iTunes:<name>`) names written for other keys.
const Map<String, String> _freeformFor = {
  TagField.mbRecordingId: 'MusicBrainz Track Id',
  TagField.mbAlbumId: 'MusicBrainz Album Id',
  TagField.mbArtistId: 'MusicBrainz Artist Id',
  TagField.mbAlbumArtistId: 'MusicBrainz Album Artist Id',
  TagField.mbReleaseGroupId: 'MusicBrainz Release Group Id',
  TagField.mbReleaseTrackId: 'MusicBrainz Release Track Id',
  TagField.trackGain: 'replaygain_track_gain',
  TagField.trackPeak: 'replaygain_track_peak',
  TagField.albumGain: 'replaygain_album_gain',
  TagField.albumPeak: 'replaygain_album_peak',
  TagField.conductor: 'CONDUCTOR',
  TagField.lyricist: 'LYRICIST',
  TagField.label: 'LABEL',
  TagField.isrc: 'ISRC',
  TagField.discSubtitle: 'DISCSUBTITLE',
  TagField.originalDate: 'ORIGINALDATE',
  TagField.acoustIdId: 'Acoustid Id',
};

/// Item atom types a canonical key controls.
Set<String> _atomsOf(String key) => switch (key) {
  TagField.trackNumber || TagField.trackTotal => {'trkn'},
  TagField.discNumber || TagField.discTotal => {'disk'},
  TagField.genre => {'©gen', 'gnre'},
  TagField.compilation => {'cpil'},
  TagField.bpm => {'tmpo'},
  _ => {?_atomFor[key]},
};

List<int> _atom(String type, List<int> body) => [
  ..._u32(body.length + 8),
  ...latin1.encode(type),
  ...body,
];

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _data(int type, List<int> value) =>
    _atom('data', [..._u32(type), ..._u32(0), ...value]);

List<int> _numberPair(int n, int total) => [
  0, 0, (n >> 8) & 0xFF, n & 0xFF, (total >> 8) & 0xFF, total & 0xFF, 0, 0, //
];

/// The new `ilst` body: edited items plus every original item not
/// controlled by the edit.
List<int> _ilst(Uint8List? oldIlst, AudioTags t, TagEdit edit) {
  final replaced = <String>{};
  final replacedFreeform = <String>{};
  for (final k in edit.fields.keys) {
    replaced.addAll(_atomsOf(k));
    final ff = _freeformFor[k];
    if (ff != null) replacedFreeform.add(ff.toLowerCase());
    if (_atomsOf(k).isEmpty && ff == null) {
      replacedFreeform.add(k.toLowerCase());
    }
  }
  if (edit.pictures != null) replaced.add('covr');
  final out = <int>[];
  if (oldIlst != null) {
    for (final a in mp4Children(MemoryByteReader(oldIlst), 0, oldIlst.length)) {
      if (replaced.contains(a.type)) continue;
      if (a.type == '----') {
        final name = _freeformName(oldIlst, a)?.toLowerCase();
        final canonical = name == null ? null : userFieldAliases[name];
        if (name != null &&
            (replacedFreeform.contains(name) ||
                (canonical != null && edit.fields.containsKey(canonical)))) {
          continue;
        }
      }
      out.addAll(Uint8List.sublistView(oldIlst, a.offset, a.end));
    }
  }
  for (final k in edit.fields.keys) {
    final v = t.values(k);
    switch (k) {
      case TagField.trackNumber || TagField.trackTotal:
        if (k == TagField.trackTotal &&
            edit.fields.containsKey(TagField.trackNumber)) {
          continue;
        }
        final n = t.trackNumber ?? 0;
        final total = t.trackTotal ?? 0;
        if (n > 0 || total > 0) {
          out.addAll(_atom('trkn', _data(0, _numberPair(n, total))));
        }
      case TagField.discNumber || TagField.discTotal:
        if (k == TagField.discTotal &&
            edit.fields.containsKey(TagField.discNumber)) {
          continue;
        }
        final n = t.discNumber ?? 0;
        final total = t.discTotal ?? 0;
        if (n > 0 || total > 0) {
          out.addAll(
            _atom('disk', _data(0, _numberPair(n, total).sublist(0, 6))),
          );
        }
      case TagField.compilation:
        if (v.isNotEmpty) {
          out.addAll(_atom('cpil', _data(21, [if (t.compilation) 1 else 0])));
        }
      case TagField.bpm:
        final bpm = int.tryParse(v.isEmpty ? '' : v.first);
        if (bpm != null) {
          out.addAll(_atom('tmpo', _data(21, [(bpm >> 8) & 0xFF, bpm & 0xFF])));
        }
      default:
        if (v.isEmpty) continue;
        final atom = _atomFor[k];
        if (atom != null) {
          out.addAll(
            _atom(atom, [for (final s in v) ..._data(1, utf8.encode(s))]),
          );
        } else {
          final name = _freeformFor[k] ?? k;
          out.addAll(
            _atom('----', [
              ..._atom('mean', [
                0,
                0,
                0,
                0,
                ...utf8.encode('com.apple.iTunes'),
              ]),
              ..._atom('name', [0, 0, 0, 0, ...utf8.encode(name)]),
              for (final s in v) ..._data(1, utf8.encode(s)),
            ]),
          );
        }
    }
  }
  if (edit.pictures != null && t.pictures.isNotEmpty) {
    out.addAll(
      _atom('covr', [
        for (final p in t.pictures)
          ..._data(
            p.mimeType == 'image/png'
                ? 14
                : p.mimeType == 'image/bmp'
                ? 27
                : 13,
            p.bytes,
          ),
      ]),
    );
  }
  return out;
}

String? _freeformName(Uint8List ilst, Mp4Atom item) {
  for (final k in mp4Children(
    MemoryByteReader(ilst),
    item.dataOffset,
    item.end,
  )) {
    if (k.type == 'name' && k.dataSize >= 4) {
      return utf8.decode(
        Uint8List.sublistView(ilst, k.dataOffset + 4, k.end),
        allowMalformed: true,
      );
    }
  }
  return null;
}

/// MP4/M4A/M4B: rebuilds `moov` with a new `udta/meta/ilst`, keeping every
/// other atom. When `moov` sits before `mdat`, chunk offsets (`stco`,
/// `co64`) are shifted by the size change.
WritePlan planMp4(ByteReader r, AudioTags after, TagEdit edit) {
  final top = mp4Children(r, 0, r.length);
  final moov = top.where((a) => a.type == 'moov').firstOrNull;
  if (moov == null) throw const TagFormatException('no moov');
  if (moov.size > 64 * 1024 * 1024) {
    throw const TagWriteUnsupported('moov too large');
  }
  final moovBytes = readExact(r, moov.offset, moov.size);
  final mr = MemoryByteReader(moovBytes);
  final kids = mp4Children(mr, moov.headerSize, moovBytes.length);
  final newMoovBody = <int>[];
  var hadUdta = false;
  for (final k in kids) {
    if (k.type == 'udta') {
      hadUdta = true;
      newMoovBody.addAll(_udta(moovBytes, k, after, edit));
    } else {
      newMoovBody.addAll(Uint8List.sublistView(moovBytes, k.offset, k.end));
    }
  }
  if (!hadUdta) newMoovBody.addAll(_udta(null, null, after, edit));
  var newMoov = Uint8List.fromList(_atom('moov', newMoovBody));
  final delta = newMoov.length - moov.size;
  final mdatAfter = top.any((a) => a.type == 'mdat' && a.offset > moov.offset);
  if (delta != 0 && mdatAfter) {
    newMoov = _shiftChunkOffsets(newMoov, moov.end, delta);
  }
  return WritePlan([
    RangePart(0, moov.offset),
    BytesPart(newMoov),
    RangePart(moov.end, r.length - moov.end),
  ]);
}

List<int> _udta(Uint8List? moov, Mp4Atom? udta, AudioTags t, TagEdit edit) {
  final body = <int>[];
  var hadMeta = false;
  if (moov != null && udta != null) {
    final mr = MemoryByteReader(moov);
    for (final k in mp4Children(mr, udta.dataOffset, udta.end)) {
      if (k.type != 'meta') {
        body.addAll(Uint8List.sublistView(moov, k.offset, k.end));
        continue;
      }
      hadMeta = true;
      final childStart = metaChildrenStart(mr, k);
      final versioned = childStart != k.dataOffset;
      final metaBody = <int>[
        if (versioned) ...Uint8List.sublistView(moov, k.dataOffset, childStart),
      ];
      var hadIlst = false;
      var hadHdlr = false;
      for (final c in mp4Children(mr, childStart, k.end)) {
        if (c.type == 'ilst') {
          hadIlst = true;
          metaBody.addAll(
            _atom(
              'ilst',
              _ilst(Uint8List.sublistView(moov, c.dataOffset, c.end), t, edit),
            ),
          );
        } else if (c.type == 'free') {
          continue; // padding is re-created by readers that need it
        } else {
          if (c.type == 'hdlr') hadHdlr = true;
          metaBody.addAll(Uint8List.sublistView(moov, c.offset, c.end));
        }
      }
      if (!hadHdlr) metaBody.insertAll(versioned ? 4 : 0, _hdlr());
      if (!hadIlst) metaBody.addAll(_atom('ilst', _ilst(null, t, edit)));
      body.addAll(_atom('meta', metaBody));
    }
  }
  if (!hadMeta) {
    body.addAll(
      _atom('meta', [
        0,
        0,
        0,
        0,
        ..._hdlr(),
        ..._atom('ilst', _ilst(null, t, edit)),
      ]),
    );
  }
  return _atom('udta', body);
}

List<int> _hdlr() => _atom('hdlr', [
  ...List.filled(8, 0),
  ...'mdir'.codeUnits,
  ...'appl'.codeUnits,
  ...List.filled(9, 0),
]);

/// Adds [delta] to every `stco`/`co64` entry pointing at or after [from].
Uint8List _shiftChunkOffsets(Uint8List moov, int from, int delta) {
  final r = MemoryByteReader(moov);
  void walk(int start, int end, int depth) {
    if (depth > TagLimits.maxDepth) return;
    for (final a in mp4Children(r, start, end)) {
      switch (a.type) {
        case 'trak' || 'mdia' || 'minf' || 'stbl' || 'edts':
          walk(a.dataOffset, a.end, depth + 1);
        case 'stco':
          final n = moov.u32be(a.dataOffset + 4);
          for (var i = 0; i < n; i++) {
            final at = a.dataOffset + 8 + i * 4;
            if (at + 4 > a.end) break;
            final v = moov.u32be(at);
            if (v >= from) {
              final nv = v + delta;
              moov.setRange(at, at + 4, _u32(nv));
            }
          }
        case 'co64':
          final n = moov.u32be(a.dataOffset + 4);
          for (var i = 0; i < n; i++) {
            final at = a.dataOffset + 8 + i * 8;
            if (at + 8 > a.end) break;
            final v = moov.u64be(at);
            if (v >= from) {
              final nv = v + delta;
              moov.setRange(at, at + 8, [
                ..._u32(nv >> 32),
                ..._u32(nv & 0xFFFFFFFF),
              ]);
            }
          }
      }
    }
  }

  walk(8, moov.length, 0);
  return moov;
}
