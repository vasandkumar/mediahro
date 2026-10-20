import 'dart:typed_data';

import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:meta/meta.dart';

/// Changes to a file's tags (MUS-003). Keys are canonical [TagField] names;
/// an empty list removes the field. [pictures] null keeps the pictures.
@immutable
final class TagEdit {
  const TagEdit({this.fields = const {}, this.pictures});

  factory TagEdit.fromJson(Map<String, Object?> j) => TagEdit(
    fields: {
      if (j['fields'] case final Map<String, Object?> m)
        for (final e in m.entries)
          e.key: [
            if (e.value case final List<Object?> l)
              for (final v in l)
                if (v is String) v,
          ],
    },
  );

  final Map<String, List<String>> fields;
  final List<EmbeddedPicture>? pictures;

  bool get isEmpty => fields.isEmpty && pictures == null;

  /// The tags after the edit, from the tags before it.
  AudioTags applyTo(AudioTags before) {
    final f = {for (final e in before.fields.entries) e.key: e.value};
    fields.forEach((k, v) {
      final clean = [
        for (final s in v)
          if (s.trim().isNotEmpty) s.trim(),
      ];
      if (clean.isEmpty) {
        f.remove(k);
      } else {
        f[k] = clean;
      }
    });
    return before.copyWith(fields: f, pictures: pictures ?? before.pictures);
  }

  /// The edit that restores [before] for the keys this edit touches (undo).
  TagEdit inverse(AudioTags before) => TagEdit(
    fields: {for (final k in fields.keys) k: before.values(k)},
    pictures: pictures == null ? null : before.pictures,
  );

  Map<String, Object?> toJson() => {'fields': fields};
}

/// A piece of the rewritten file: new bytes, or a range copied from the
/// original (audio is streamed through, never loaded whole).
sealed class FilePart {
  const FilePart();
  int get length;
}

final class BytesPart extends FilePart {
  const BytesPart(this.bytes);
  final Uint8List bytes;

  @override
  int get length => bytes.length;
}

final class RangePart extends FilePart {
  const RangePart(this.offset, this.length);
  final int offset;

  @override
  final int length;
}

/// The new file as parts.
@immutable
final class WritePlan {
  const WritePlan(this.parts);

  final List<FilePart> parts;

  int get length => parts.fold(0, (a, p) => a + p.length);
}

/// Thrown when a container can't hold the edit (e.g. a non-audio file).
final class TagWriteUnsupported implements Exception {
  const TagWriteUnsupported(this.reason);
  final String reason;

  @override
  String toString() => 'TagWriteUnsupported($reason)';
}

/// Appends big-endian / little-endian integers.
extension ByteBuilderX on BytesBuilder {
  void u8(int v) => addByte(v & 0xFF);
  void u16be(int v) => add([(v >> 8) & 0xFF, v & 0xFF]);
  void u16le(int v) => add([v & 0xFF, (v >> 8) & 0xFF]);
  void u24be(int v) => add([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  void u32be(int v) =>
      add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  void u32le(int v) =>
      add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u64be(int v) {
    u32be(v >> 32);
    u32be(v & 0xFFFFFFFF);
  }

  void u64le(int v) {
    u32le(v & 0xFFFFFFFF);
    u32le(v >> 32);
  }

  void syncSafe(int v) =>
      add([(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F]);

  void ascii(String s) => add(s.codeUnits);
}

/// Canonical "n/total" for ID3 TRCK/TPOS from separate fields.
String? numberWithTotal(AudioTags t, String numberKey, String totalKey) {
  final n = t.first(numberKey);
  if (n == null) return null;
  final num = RegExp(r'^\s*(\d+)').firstMatch(n)?.group(1) ?? n;
  final total =
      t.first(totalKey) ?? RegExp(r'/\s*(\d+)').firstMatch(n)?.group(1);
  return total == null ? num : '$num/$total';
}

/// Latin-1 bytes of [s]; characters outside Latin-1 become `?`.
Uint8List latin1Bytes(String s) => Uint8List.fromList([
  for (final u in s.codeUnits)
    if (u <= 0xFF) u else 0x3F,
]);
