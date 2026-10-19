import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Finds the file system that serves a URI: the mounted source whose root
/// is the longest prefix, or the local file system for `file:` URIs.
final class MountedFileSystems {
  MountedFileSystems({this._local = const LocalFileSystem()});

  final VirtualFileSystem _local;
  final _mounts = <(Uri, VirtualFileSystem)>[];

  void mount(Uri root, VirtualFileSystem fs) {
    unmount(root);
    _mounts.add((root, fs));
  }

  void unmount(Uri root) => _mounts.removeWhere((m) => m.$1 == root);

  /// Throws [VirtualFileException] (unsupported) when nothing serves [uri].
  VirtualFileSystem forUri(Uri uri) {
    (Uri, VirtualFileSystem)? best;
    for (final m in _mounts) {
      if (_contains(m.$1, uri) &&
          (best == null || m.$1.path.length > best.$1.path.length)) {
        best = m;
      }
    }
    if (best != null) return best.$2;
    if (uri.scheme == 'file') return _local;
    throw VirtualFileException(
      VirtualFileError.unsupported,
      uri,
      'no source mounted',
    );
  }

  static bool _contains(Uri root, Uri uri) {
    if (root.scheme != uri.scheme ||
        root.host.toLowerCase() != uri.host.toLowerCase() ||
        root.port != uri.port) {
      return false;
    }
    final r = root.pathSegments.where((s) => s.isNotEmpty).toList();
    final u = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (u.length < r.length) return false;
    for (var i = 0; i < r.length; i++) {
      if (r[i] != u[i]) return false;
    }
    return true;
  }
}
