import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/walker.dart';

/// Maps index items to URIs and back (playlists, backup restore, open-with).
final class ItemLocator {
  ItemLocator(this.db);

  final LibraryDatabase db;
  List<SourceRow>? _sources;

  Future<List<SourceRow>> _all() async =>
      _sources ??= await db.select(db.sources).get();

  /// Forget cached sources after sources change.
  void invalidate() => _sources = null;

  Future<Uri> uriOf(ItemRow item) async {
    final s = (await _all()).firstWhere((s) => s.id == item.sourceId);
    return childUri(Uri.parse(s.rootUri), item.relPath);
  }

  /// The indexed item at [uri], if a source root contains it.
  Future<ItemRow?> itemFor(Uri uri) async {
    final target = _norm(uri);
    for (final s in await _all()) {
      final root = _norm(Uri.parse(s.rootUri));
      final prefix = root.endsWith('/') ? root : '$root/';
      if (!target.startsWith(prefix)) continue;
      final rel = Uri.decodeComponent(target.substring(prefix.length));
      final row =
          await (db.select(db.items)
                ..where((i) => i.sourceId.equals(s.id) & i.relPath.equals(rel)))
              .getSingleOrNull();
      if (row != null) return row;
    }
    return null;
  }

  // Case-insensitive on Windows drive letters; decoded consistently.
  static String _norm(Uri u) {
    final s = u.toString();
    return u.scheme == 'file'
        ? s.replaceFirstMapped(
            RegExp('^file:///([A-Za-z]):'),
            (m) => 'file:///${m.group(1)!.toUpperCase()}:',
          )
        : s;
  }
}
