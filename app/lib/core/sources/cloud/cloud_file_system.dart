import 'dart:async';

import 'package:mediahro/core/sources/cloud/cloud_providers.dart';
import 'package:mediahro/core/sources/http/http_file.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// A cloud drive as a path-addressed, read-only file system
/// (`cloud://<provider>/<account>/<path>`, NET-007). Names map to provider
/// ids by listing; listings are cached for [cacheFor]. Files stream with
/// range requests (seek and cache via [HttpVirtualFile]).
final class CloudFileSystem implements VirtualFileSystem {
  CloudFileSystem({
    required this.provider,
    required this.api,
    required this.downloadSession,
    this.cacheFor = const Duration(minutes: 2),
  });

  final CloudProvider provider;
  final CloudCalls api;

  /// Session for file bytes: no stored credentials; per-request headers
  /// carry the bearer only for the provider's own API host.
  final HttpSession downloadSession;
  final Duration cacheFor;
  final _cache = <String, (DateTime, List<CloudEntry>)>{};

  @override
  Set<String> get schemes => const {'cloud'};

  @override
  Set<VirtualFsCapability> get capabilities => const {VirtualFsCapability.list};

  CloudEntry get _root => CloudEntry(
    id: provider.rootId,
    name: '',
    isFolder: true,
    path: provider.id == 'yandex' ? 'disk:/' : '',
  );

  /// `cloud://gdrive/<account>/Films/a.mkv` → `['Films', 'a.mkv']` (the
  /// first segment names the account).
  static List<String> _segments(Uri uri) =>
      uri.pathSegments.where((s) => s.isNotEmpty).skip(1).toList();

  Future<List<CloudEntry>> _children(CloudEntry folder) async {
    final key = folder.id;
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < cacheFor) {
      return hit.$2;
    }
    final list = await provider.list(api, folder);
    _cache[key] = (DateTime.now(), list);
    return list;
  }

  Future<CloudEntry> _resolve(Uri uri) async {
    var cur = _root;
    for (final name in _segments(uri)) {
      final next = (await _children(cur))
          .where((e) => e.name == name)
          .firstOrNull;
      if (next == null) {
        throw VirtualFileException(VirtualFileError.notFound, uri);
      }
      cur = next;
    }
    return cur;
  }

  @override
  Stream<VirtualEntry> list(Uri directory) async* {
    final dir = await _resolve(directory);
    if (!dir.isFolder) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        directory,
        'not a folder',
      );
    }
    for (final e in await _children(dir)) {
      yield VirtualEntry(
        uri: directory.replace(
          pathSegments: [
            ...directory.pathSegments.where((s) => s.isNotEmpty),
            e.name,
            if (e.isFolder) '',
          ],
        ),
        name: e.name,
        isDirectory: e.isFolder,
        size: e.size,
        modified: e.modified,
      );
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) async {
    final e = await _resolve(uri);
    return VirtualEntry(
      uri: uri,
      name: e.name,
      isDirectory: e.isFolder,
      size: e.size,
      modified: e.modified,
    );
  }

  @override
  Future<VirtualFile> open(Uri uri) async {
    final e = await _resolve(uri);
    if (e.isFolder) {
      throw VirtualFileException(VirtualFileError.notFound, uri, 'is a folder');
    }
    final (url, headers) = await provider.download(api, e);
    final session = HttpSession(
      downloadSession.gateway,
      headers: {...downloadSession.headers, ...headers},
    );
    return await HttpVirtualFile.open(url, session, knownLength: e.size);
  }

  void invalidate() => _cache.clear();
}
