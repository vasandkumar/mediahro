import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/photo_files.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:meta/meta.dart';

/// A photo in the app's recycle bin (IMG-014).
@immutable
final class TrashedPhoto {
  const TrashedPhoto({
    required this.id,
    required this.name,
    required this.origin,
    required this.size,
    required this.deletedAt,
    required this.itemId,
    required this.isVideo,
  });

  /// Names the bin's copy of the file.
  final String id;
  final String name;

  /// Where the file was; restoring puts it back there.
  final Uri origin;
  final int size;
  final DateTime deletedAt;

  /// The library row of the original, so ratings and tags come back.
  final int itemId;
  final bool isVideo;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'origin': origin.toString(),
    'size': size,
    'at': deletedAt.millisecondsSinceEpoch,
    'item': itemId,
    'video': isVideo,
  };

  static TrashedPhoto? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final origin = j['origin'];
    final size = j['size'];
    final at = j['at'];
    final item = j['item'];
    if (id is! String ||
        name is! String ||
        origin is! String ||
        size is! int ||
        at is! int ||
        item is! int) {
      return null;
    }
    return TrashedPhoto(
      id: id,
      name: name,
      origin: Uri.parse(origin),
      size: size,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(at),
      itemId: item,
      isVideo: j['video'] == true,
    );
  }
}

/// What a move to the bin did.
@immutable
final class TrashOutcome {
  const TrashOutcome({
    this.moved = const [],
    this.tooBig = const [],
    this.failed = const [],
  });

  final List<TrashedPhoto> moved;

  /// Not taken by the bin (larger than its limit): the caller sends them to
  /// the system trash instead.
  final List<PhotoEntry> tooBig;

  /// Could not be moved; left where they were.
  final List<String> failed;
}

/// The recycle bin as the screens see it; faked in widget tests.
abstract interface class PhotoTrash {
  /// How long a photo is kept.
  Duration get keepFor;

  /// Everything in the bin, newest first.
  Future<List<TrashedPhoto>> list();

  /// The bin's copy of [t], for showing it.
  File fileOf(TrashedPhoto t);

  Future<TrashOutcome> moveToTrash(List<PhotoEntry> photos);

  /// Puts photos back where they were; returns how many came back.
  Future<int> restore(List<TrashedPhoto> items);

  Future<void> deleteForever(List<TrashedPhoto> items);

  Future<void> empty();

  /// Drops what is too old or over the size limit.
  Future<int> purge();
}

/// The app's own recycle bin for photos (IMG-014): deleted photos stay here
/// for [keepFor], at most [capBytes] together, and can be restored to where
/// they were. The system trash is used for what does not fit
/// (`FileOperations.delete`, FILE-002).
final class AppTrash implements PhotoTrash {
  AppTrash({
    required this.directory,
    required this.files,
    required this.io,
    required this.db,
    this.keepFor = const Duration(days: 30),
    this.capBytes = 2 << 30,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;
  final PhotoFileOpener files;
  final ImageIo io;
  final LibraryDatabase db;
  @override
  final Duration keepFor;
  final int capBytes;
  final DateTime Function() _clock;

  File get _index =>
      File('${directory.path}${Platform.pathSeparator}index.json');

  File _file(TrashedPhoto t) =>
      File('${directory.path}${Platform.pathSeparator}${t.id}.bin');

  @override
  File fileOf(TrashedPhoto t) => _file(t);

  /// Everything in the bin, newest first.
  @override
  Future<List<TrashedPhoto>> list() async {
    try {
      if (!_index.existsSync()) return <TrashedPhoto>[];
      final data = jsonDecode(await _index.readAsString());
      if (data is! List) return <TrashedPhoto>[];
      return [
        for (final j in data)
          if (TrashedPhoto.fromJson(j) case final TrashedPhoto t)
            if (_file(t).existsSync()) t,
      ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    } on Object {
      return <TrashedPhoto>[];
    }
  }

  Future<void> _save(List<TrashedPhoto> all) async {
    await directory.create(recursive: true);
    final part = File('${_index.path}.part');
    await part.writeAsString(
      jsonEncode([for (final t in all) t.toJson()]),
      flush: true,
    );
    await part.rename(_index.path);
  }

  /// Moves [photos] into the bin: each is copied in, then removed from where
  /// it was. A photo whose original cannot be removed stays where it is.
  @override
  Future<TrashOutcome> moveToTrash(List<PhotoEntry> photos) async {
    final all = await list();
    final moved = <TrashedPhoto>[];
    final tooBig = <PhotoEntry>[];
    final failed = <String>[];
    await directory.create(recursive: true);
    for (final p in photos) {
      if (p.size > capBytes ~/ 2) {
        tooBig.add(p);
        continue;
      }
      final id = '${_clock().microsecondsSinceEpoch}_${p.id}';
      final origin = await files.uriOf(p);
      final t = TrashedPhoto(
        id: id,
        name: p.name,
        origin: origin,
        size: p.size,
        deletedAt: _clock(),
        itemId: p.id,
        isVideo: p.isVideo,
      );
      try {
        await _copyIn(p, _file(t));
        await io.delete(origin);
      } on Object {
        if (_file(t).existsSync()) _file(t).deleteSync();
        failed.add(p.name);
        continue;
      }
      await (db.update(db.items)..where((i) => i.id.equals(p.id))).write(
        const ItemsCompanion(missing: Value(true)),
      );
      moved.add(t);
    }
    all.addAll(moved);
    await _save(all);
    await purge();
    return TrashOutcome(moved: moved, tooBig: tooBig, failed: failed);
  }

  /// Copies the original into the bin, forces it to disk and reads it back
  /// (length and last megabyte) before the caller removes the original.
  Future<void> _copyIn(PhotoEntry p, File to) async {
    final src = await files.open(p);
    try {
      final length = await src.file.length() ?? 0;
      final out = await to.open(mode: FileMode.write);
      try {
        for (var at = 0; at < length; at += 1 << 20) {
          final n = (length - at).clamp(0, 1 << 20);
          await out.writeFrom(await src.file.read(at, n));
        }
        await out.flush();
      } finally {
        await out.close();
      }
      if (to.lengthSync() != length) {
        throw FileSystemException('short copy', to.path);
      }
      if (length > 0) {
        final at = length > (1 << 20) ? length - (1 << 20) : 0;
        final want = await src.file.read(at, length - at);
        final raf = await to.open();
        try {
          await raf.setPosition(at);
          final got = await raf.read(length - at);
          if (got.length != want.length) {
            throw FileSystemException('short copy', to.path);
          }
          for (var k = 0; k < got.length; k++) {
            if (got[k] != want[k]) {
              throw FileSystemException('copy differs', to.path);
            }
          }
        } finally {
          await raf.close();
        }
      }
    } finally {
      await src.file.close();
    }
  }

  /// Puts photos back where they were (a name that is taken again gets
  /// `_restored`). Returns how many came back.
  @override
  Future<int> restore(List<TrashedPhoto> items) async {
    final all = await list();
    var restored = 0;
    for (final t in items) {
      final f = _file(t);
      if (!f.existsSync()) continue;
      try {
        final target = await _freeName(t.origin);
        await io.create(target, await f.readAsBytes());
        f.deleteSync();
        all.removeWhere((x) => x.id == t.id);
        if (target == t.origin) {
          await (db.update(db.items)..where((i) => i.id.equals(t.itemId)))
              .write(const ItemsCompanion(missing: Value(false)));
        }
        restored++;
      } on Object {
        // Left in the bin; the caller says how many came back.
      }
    }
    await _save(all);
    return restored;
  }

  Future<Uri> _freeName(Uri origin) async {
    if (!await io.exists(origin)) return origin;
    final segments = [...origin.pathSegments];
    final name = Uri.decodeComponent(segments.removeLast());
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    for (var n = 1; ; n++) {
      final suffix = n == 1 ? '_restored' : '_restored_$n';
      final candidate = origin.replace(
        pathSegments: [...segments, '$stem$suffix$ext'],
      );
      if (!await io.exists(candidate)) return candidate;
    }
  }

  /// Deletes [items] for good, with their library rows (tags, ratings,
  /// places and the search entry go with them), so nothing about a photo that
  /// is gone stays in the library database.
  @override
  Future<void> deleteForever(List<TrashedPhoto> items) async {
    final all = await list();
    for (final t in items) {
      final f = _file(t);
      if (f.existsSync()) f.deleteSync();
      all.removeWhere((x) => x.id == t.id);
    }
    await _save(all);
    final ids = [for (final t in items) t.itemId];
    if (ids.isNotEmpty) {
      await (db.delete(
        db.items,
      )..where((i) => i.id.isIn(ids) & i.missing.equals(true))).go();
    }
  }

  @override
  Future<void> empty() async => await deleteForever(await list());

  /// Drops what is older than [keepFor], then the oldest until the bin fits
  /// [capBytes]. Returns how many photos went.
  @override
  Future<int> purge() async {
    final all = await list();
    final cutoff = _clock().subtract(keepFor);
    final gone = <TrashedPhoto>[
      for (final t in all)
        if (t.deletedAt.isBefore(cutoff)) t,
    ];
    final left = all.where((t) => !gone.contains(t)).toList();
    var total = left.fold<int>(0, (a, t) => a + t.size);
    // Oldest first.
    for (final t in left.reversed) {
      if (total <= capBytes) break;
      gone.add(t);
      total -= t.size;
    }
    if (gone.isNotEmpty) await deleteForever(gone);
    return gone.length;
  }
}
