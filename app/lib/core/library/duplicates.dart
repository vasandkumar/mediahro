import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:meta/meta.dart';

enum DuplicateKind { exact, perceptualImage, acousticAudio, videoDurationSize }

/// A set of items that look like copies of one another. The finder never
/// deletes: the user reviews each group and chooses (LIB-014).
@immutable
final class DuplicateGroup {
  const DuplicateGroup(this.kind, this.items, {this.similarity = 1});

  final DuplicateKind kind;
  final List<ItemRow> items;

  /// 1.0 for exact; otherwise the weakest pairwise similarity in the group.
  final double similarity;

  /// Suggested keeper: largest resolution, then largest file, then oldest.
  ItemRow get suggestedKeep {
    final sorted = [...items]
      ..sort((a, b) {
        final pa = (a.width ?? 0) * (a.height ?? 0);
        final pb = (b.width ?? 0) * (b.height ?? 0);
        if (pa != pb) return pb.compareTo(pa);
        if (a.size != b.size) return b.size.compareTo(a.size);
        return a.addedAt.compareTo(b.addedAt);
      });
    return sorted.first;
  }
}

/// Computes what the finder needs but the index lacks yet.
abstract interface class DuplicateInputs {
  /// xxh3 content hash (scanner/probe queue).
  Future<String?> contentHash(ItemRow item);

  /// 32×32 8-bit greyscale thumbnail from the image pipeline.
  Future<Uint8List?> grey32(ItemRow item);

  /// Raw chromaprint fingerprint (uint32 words) for an audio item.
  Future<Uint32List?> fingerprint(ItemRow item);
}

/// Duplicate finder (LIB-014): exact by content hash, perceptual by pHash
/// for images, acoustic by chromaprint for audio, duration + size for video.
final class DuplicateFinder {
  DuplicateFinder(
    this.db, {
    this.inputs,
    this.maxPhashDistance = 6,
    this.minAudioSimilarity = 0.85,
    this.videoDurationTolerance = const Duration(seconds: 1),
    this.videoSizeTolerance = 0.01,
  });

  final LibraryDatabase db;
  final DuplicateInputs? inputs;
  final int maxPhashDistance;
  final double minAudioSimilarity;
  final Duration videoDurationTolerance;
  final double videoSizeTolerance;

  Future<List<DuplicateGroup>> find(Set<DuplicateKind> kinds) async {
    final out = <DuplicateGroup>[];
    if (kinds.contains(DuplicateKind.exact)) out.addAll(await exact());
    if (kinds.contains(DuplicateKind.perceptualImage)) {
      out.addAll(await images());
    }
    if (kinds.contains(DuplicateKind.acousticAudio)) out.addAll(await audio());
    if (kinds.contains(DuplicateKind.videoDurationSize)) {
      out.addAll(await videos());
    }
    return out;
  }

  /// Same bytes. Hashes are computed only for files that share a size.
  Future<List<DuplicateGroup>> exact() async {
    final rows = await db
        .customSelect(
          'SELECT * FROM item WHERE missing = 0 AND size > 0 AND size IN '
          '(SELECT size FROM item WHERE missing = 0 GROUP BY size HAVING count(*) > 1) '
          'ORDER BY size',
          readsFrom: {db.items},
        )
        .get();
    final items = [for (final r in rows) db.items.map(r.data)];
    final byHash = <String, List<ItemRow>>{};
    for (final i in items) {
      var h = i.contentHash;
      if (h == null && inputs != null) {
        h = await inputs!.contentHash(i);
        if (h != null) {
          await (db.update(db.items)..where((x) => x.id.equals(i.id))).write(
            ItemsCompanion(contentHash: Value(h)),
          );
        }
      }
      if (h == null) continue;
      (byHash['$h:${i.size}'] ??= []).add(i);
    }
    return [
      for (final g in byHash.values)
        if (g.length > 1) DuplicateGroup(DuplicateKind.exact, g),
    ];
  }

  Future<List<DuplicateGroup>> images() async {
    final rows =
        await (db.select(db.items).join([
              leftOuterJoin(
                db.imageMeta,
                db.imageMeta.itemId.equalsExp(db.items.id),
              ),
            ])..where(
              db.items.kind.equalsValue(ItemKind.image) &
                  db.items.missing.equals(false),
            ))
            .get();
    final hashes = <(ItemRow, int)>[];
    for (final r in rows) {
      final item = r.readTable(db.items);
      var hex = r.readTableOrNull(db.imageMeta)?.phash;
      if (hex == null && inputs != null) {
        final grey = await inputs!.grey32(item);
        if (grey != null) {
          final h = await phashIsolated(grey);
          hex = phashHex(h);
          await db
              .into(db.imageMeta)
              .insertOnConflictUpdate(
                ImageMetaCompanion.insert(
                  itemId: Value(item.id),
                  phash: Value(hex),
                ),
              );
        }
      }
      if (hex != null) hashes.add((item, _parseHex(hex)));
    }
    return _cluster(hashes, (a, b) {
      final d = hamming64(a, b);
      return d <= maxPhashDistance ? 1 - d / 64 : null;
    }, DuplicateKind.perceptualImage);
  }

  Future<List<DuplicateGroup>> audio() async {
    final rows =
        await (db.select(db.items).join([
              leftOuterJoin(
                db.audioMeta,
                db.audioMeta.itemId.equalsExp(db.items.id),
              ),
            ])..where(
              db.items.kind.equalsValue(ItemKind.audio) &
                  db.items.missing.equals(false),
            ))
            .get();
    final prints = <(ItemRow, Uint32List)>[];
    for (final r in rows) {
      final item = r.readTable(db.items);
      final stored = r.readTableOrNull(db.audioMeta)?.fingerprint;
      var fp = stored == null ? null : decodeFingerprint(stored);
      if (fp == null && inputs != null) {
        fp = await inputs!.fingerprint(item);
        if (fp != null) {
          await db
              .into(db.audioMeta)
              .insertOnConflictUpdate(
                AudioMetaCompanion.insert(
                  itemId: Value(item.id),
                  fingerprint: Value(encodeFingerprint(fp)),
                ),
              );
        }
      }
      if (fp != null && fp.isNotEmpty) prints.add((item, fp));
    }
    return _cluster(prints, (a, b) {
      final s = fingerprintSimilarity(a, b);
      return s >= minAudioSimilarity ? s : null;
    }, DuplicateKind.acousticAudio);
  }

  Future<List<DuplicateGroup>> videos() async {
    final items =
        await (db.select(db.items)
              ..where(
                (i) =>
                    i.kind.equalsValue(ItemKind.video) &
                    i.missing.equals(false) &
                    i.durationMs.isNotNull(),
              )
              ..orderBy([(i) => OrderingTerm.asc(i.durationMs)]))
            .get();
    final pairs = [for (final i in items) (i, i)];
    final tol = videoDurationTolerance.inMilliseconds;
    return _cluster(pairs, (a, b) {
      final dd = (a.durationMs! - b.durationMs!).abs();
      if (dd > tol) return null;
      final big = math.max(a.size, b.size);
      final ds = big == 0 ? 0.0 : (a.size - b.size).abs() / big;
      if (ds > videoSizeTolerance) return null;
      return 1 - ds;
    }, DuplicateKind.videoDurationSize);
  }

  /// Single-link clustering with union-find; O(n²) only within the sets
  /// handed in (images, audio, videos), which the UI pages through.
  List<DuplicateGroup> _cluster<T>(
    List<(ItemRow, T)> xs,
    double? Function(T a, T b) similar,
    DuplicateKind kind,
  ) {
    final parent = List<int>.generate(xs.length, (i) => i);
    int find(int i) {
      var r = i;
      while (parent[r] != r) {
        r = parent[r] = parent[parent[r]];
      }
      return r;
    }

    final minSim = List<double>.filled(xs.length, 1);
    for (var i = 0; i < xs.length; i++) {
      for (var j = i + 1; j < xs.length; j++) {
        final s = similar(xs[i].$2, xs[j].$2);
        if (s == null) continue;
        final a = find(i);
        final b = find(j);
        final m = math.min(math.min(minSim[a], minSim[b]), s);
        if (a != b) parent[b] = a;
        minSim[a] = m;
      }
    }
    final groups = <int, List<ItemRow>>{};
    for (var i = 0; i < xs.length; i++) {
      (groups[find(i)] ??= []).add(xs[i].$1);
    }
    return [
      for (final e in groups.entries)
        if (e.value.length > 1)
          DuplicateGroup(kind, e.value, similarity: minSim[e.key]),
    ];
  }
}

/// [phash64] on a worker isolate. A top-level function so the closure
/// captures only the pixels (never the database).
Future<int> phashIsolated(Uint8List grey32) =>
    Isolate.run(() => phash64(grey32));

/// DCT-II perceptual hash over a 32×32 greyscale image: low 8×8
/// frequencies without DC, thresholded at their median.
int phash64(Uint8List grey32) {
  if (grey32.length != 1024) {
    throw ArgumentError.value(grey32.length, 'grey32', 'need 32×32 pixels');
  }
  final cos = List<List<double>>.generate(
    8,
    (u) => List<double>.generate(
      32,
      (x) => math.cos((2 * x + 1) * u * math.pi / 64),
    ),
  );
  final coeffs = List<double>.filled(64, 0);
  for (var u = 0; u < 8; u++) {
    for (var v = 0; v < 8; v++) {
      var sum = 0.0;
      for (var y = 0; y < 32; y++) {
        final cy = cos[v][y];
        for (var x = 0; x < 32; x++) {
          sum += grey32[y * 32 + x] * cos[u][x] * cy;
        }
      }
      coeffs[v * 8 + u] = sum;
    }
  }
  final ac = coeffs.sublist(1)..sort();
  final median = (ac[31] + ac[32]) / 2;
  var h = 0;
  for (var i = 0; i < 64; i++) {
    if (coeffs[i] > median) h |= 1 << i;
  }
  return h;
}

int hamming64(int a, int b) {
  var x = a ^ b;
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

String phashHex(int h) =>
    (h >>> 32).toRadixString(16).padLeft(8, '0') +
    (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

int _parseHex(String hex) =>
    (int.parse(hex.substring(0, 8), radix: 16) << 32) |
    int.parse(hex.substring(8), radix: 16);

String encodeFingerprint(Uint32List fp) =>
    base64Encode(fp.buffer.asUint8List(fp.offsetInBytes, fp.lengthInBytes));

Uint32List decodeFingerprint(String b64) {
  final bytes = base64Decode(b64);
  final out = Uint32List(bytes.length ~/ 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getUint32(i * 4, Endian.little);
  }
  return out;
}

/// Chromaprint comparison: best alignment within ±[maxOffset] words, share
/// of equal bits over the overlap (1.0 = identical).
double fingerprintSimilarity(Uint32List a, Uint32List b, {int maxOffset = 80}) {
  var best = 0.0;
  for (var off = -maxOffset; off <= maxOffset; off++) {
    var bits = 0;
    var total = 0;
    for (var i = 0; i < a.length; i++) {
      final j = i + off;
      if (j < 0 || j >= b.length) continue;
      bits += hamming64(a[i], b[j]);
      total += 32;
    }
    // Require a meaningful overlap (≥ 1/2 of the shorter print).
    if (total < 16 * math.min(a.length, b.length)) continue;
    final s = 1 - bits / total;
    if (s > best) best = s;
  }
  return best;
}
