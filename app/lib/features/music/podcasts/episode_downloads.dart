import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/core/sources/http/http_file.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Reads one http(s) address as a file (podcast enclosures), through the
/// network gateway. Only `open` is supported: an episode is a single file,
/// not a folder.
final class HttpUrlFileSystem implements VirtualFileSystem {
  HttpUrlFileSystem(this._session, this.http, {this.openInner});

  final HttpSession Function() _session;

  /// Opens the address the redirects ended at (tests).
  @visibleForTesting
  final Future<VirtualFile> Function(Uri uri)? openInner;

  /// Follows the redirect chain of an address when it is opened, allowing
  /// each host only while the file is open (and refusing a hop to the
  /// listener's own network unless a subscription is on that host).
  final PodcastHttp http;

  @override
  Set<String> get schemes => const {'http', 'https'};

  @override
  Set<VirtualFsCapability> get capabilities => const {};

  @override
  Future<VirtualFile> open(Uri uri) async {
    final ({Uri uri, ChainAllowance chain}) opened;
    try {
      opened = await http.openChain(uri);
    } on PodcastHttpException catch (e) {
      throw VirtualFileException(
        VirtualFileError.permissionDenied,
        uri,
        e.reason,
      );
    }
    try {
      final file =
          await (openInner?.call(opened.uri) ??
              HttpVirtualFile.open(opened.uri, _session()));
      return _ScopedFile(uri, file, opened.chain.close);
    } on Object {
      opened.chain.close();
      rethrow;
    }
  }

  @override
  Future<VirtualEntry> stat(Uri uri) => throw VirtualFileException(
    VirtualFileError.unsupported,
    uri,
    'episodes are single files',
  );

  @override
  Stream<VirtualEntry> list(Uri directory) => Stream.error(
    VirtualFileException(
      VirtualFileError.unsupported,
      directory,
      'episodes are single files',
    ),
  );
}

/// A file whose network allowance ends when it is closed. It reports the
/// address it was asked for; the reads go to where the redirects ended.
final class _ScopedFile implements VirtualFile {
  _ScopedFile(this.uri, this._inner, this._release);

  @override
  final Uri uri;
  final VirtualFile _inner;
  final void Function() _release;

  @override
  bool get isSeekable => _inner.isSeekable;

  @override
  Future<int?> length() => _inner.length();

  @override
  Future<Uint8List> read(int offset, int length) => _inner.read(offset, length);

  @override
  Future<void> close() async {
    _release();
    await _inner.close();
  }
}

/// Offline copies of episodes on the app's download manager (NET-018):
/// resumable, with a size quota, listed on the Downloads screen too.
final class ManagerEpisodeDownloads implements EpisodeDownloads {
  ManagerEpisodeDownloads({
    required this.manager,
    required this.mounts,
    required this.fileSystem,
  });

  final DownloadManager manager;
  final MountedFileSystems mounts;
  final HttpUrlFileSystem fileSystem;

  LibraryDatabase get _db => manager.db;

  /// Makes [url] openable by the download manager: its web address is
  /// mounted unless a source already serves it.
  void _mount(Uri url) {
    try {
      mounts.forUri(url);
    } on VirtualFileException {
      mounts.mount(
        Uri(
          scheme: url.scheme,
          host: url.host,
          port: url.hasPort ? url.port : null,
        ),
        fileSystem,
      );
    }
  }

  /// Mounts the addresses of downloads still waiting, so they resume after
  /// a restart.
  Future<void> resumePending() async {
    final rows =
        await (_db.select(_db.downloads)..where(
              (d) =>
                  d.state.equalsValue(DownloadState.done).not() &
                  d.state.equalsValue(DownloadState.expired).not(),
            ))
            .get();
    for (final r in rows) {
      final u = Uri.tryParse(r.remoteUri);
      if (u != null && (u.scheme == 'http' || u.scheme == 'https')) _mount(u);
    }
  }

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {
    _mount(url);
    await manager.enqueue(url, title: title, knownSize: size);
  }

  Future<DownloadRow?> _row(Uri url) => (_db.select(
    _db.downloads,
  )..where((d) => d.remoteUri.equals(url.toString()))).getSingleOrNull();

  @override
  Future<EpisodeDownload?> status(Uri url) async {
    final r = await _row(url);
    if (r == null || r.state == DownloadState.expired) return null;
    final file = File(r.localPath);
    return EpisodeDownload(
      r.state,
      received: r.receivedBytes,
      total: r.totalBytes,
      file: r.state == DownloadState.done && file.existsSync() ? file : null,
    );
  }

  @override
  Future<void> remove(Uri url) async {
    final r = await _row(url);
    if (r != null) await manager.remove(r.id);
  }
}
