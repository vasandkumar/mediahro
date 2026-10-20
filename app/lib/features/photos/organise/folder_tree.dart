import 'package:mediahro/features/photos/timeline/timeline_model.dart';

/// One folder of one source, with the photos directly in it and its
/// sub-folders (IMG-005 "Folders"): built in memory from the timeline's
/// entries, so browsing folders needs no extra queries.
final class FolderNode {
  FolderNode(this.sourceId, this.path, this.name);

  final int sourceId;

  /// Path relative to the source root (`''` for the root), `/`-separated.
  final String path;
  final String name;
  final List<PhotoEntry> photos = [];
  final Map<String, FolderNode> children = {};

  /// Photos here and in every folder below.
  int get total =>
      photos.length + children.values.fold<int>(0, (n, c) => n + c.total);

  /// Sub-folders by name, case-insensitively sorted.
  List<FolderNode> get sortedChildren =>
      children.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The node at [relative] below this one, or null.
  FolderNode? find(String relative) {
    if (relative.isEmpty) return this;
    var node = this;
    for (final seg in relative.split('/')) {
      final next = node.children[seg];
      if (next == null) return null;
      node = next;
    }
    return node;
  }
}

/// The folder trees of every source in [entries], by source id.
Map<int, FolderNode> buildFolderTrees(Iterable<PhotoEntry> entries) {
  final roots = <int, FolderNode>{};
  for (final e in entries) {
    var node = roots.putIfAbsent(
      e.sourceId,
      () => FolderNode(e.sourceId, '', ''),
    );
    final slash = e.relPath.lastIndexOf('/');
    if (slash > 0) {
      var path = '';
      for (final seg in e.relPath.substring(0, slash).split('/')) {
        path = path.isEmpty ? seg : '$path/$seg';
        node = node.children.putIfAbsent(
          seg,
          () => FolderNode(e.sourceId, path, seg),
        );
      }
    }
    node.photos.add(e);
  }
  return roots;
}
