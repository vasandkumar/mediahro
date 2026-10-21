import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Reads one http(s) address as a file (podcast enclosures), through
/// [PodcastHttp]: every hop, and every read, is checked and allowed for that
/// file only. Only `open` is supported: an episode is a single file, not a
/// folder.
final class HttpUrlFileSystem implements VirtualFileSystem {
  HttpUrlFileSystem(this.http, {required this.trustedFor});

  final PodcastHttp http;

  /// The private-network hosts an episode's file may reach: its feed's own
  /// host, which the listener gave (empty for a feed on the internet).
  final Future<Set<String>> Function(Uri episode) trustedFor;

  @override
  Set<String> get schemes => const {'http', 'https'};

  @override
  Set<VirtualFsCapability> get capabilities => const {};

  @override
  Future<VirtualFile> open(Uri uri) async {
    try {
      return await http.openFile(uri, trusted: await trustedFor(uri));
    } on PodcastHttpException catch (e) {
      throw VirtualFileException(
        VirtualFileError.permissionDenied,
        uri,
        e.reason,
      );
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

  @override
  Future<VirtualFile> openStream(Uri url) => fileSystem.open(url);
}
