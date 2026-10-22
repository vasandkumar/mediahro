import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// The address a podcast download is queued under: the episode's address with
/// a `podcast-` scheme (`podcast-https://cdn.example/a.mp3`). Only podcast code
/// makes such addresses, so the download manager can open them with
/// [HttpUrlFileSystem] alone: no source the listener added (a WebDAV share on
/// the same host, with their credentials) can serve an address a feed chose.
Uri podcastDownloadUri(Uri episode) =>
    episode.replace(scheme: 'podcast-${episode.scheme}');

/// The episode address behind [queued] (see [podcastDownloadUri]), or null for
/// any other address.
Uri? podcastEpisodeUri(Uri queued) =>
    queued.scheme == 'podcast-http' || queued.scheme == 'podcast-https'
    ? queued.replace(scheme: queued.scheme.substring('podcast-'.length))
    : null;

/// Reads one http(s) address as a file (podcast enclosures), through
/// [PodcastHttp]: every hop, and every read, is checked and allowed for that
/// file only. Only `open` is supported: an episode is a single file, not a
/// folder. Download addresses (`podcast-https:`) read the episode they stand
/// for.
final class HttpUrlFileSystem implements VirtualFileSystem {
  HttpUrlFileSystem(this.http, {required this.trustedFor});

  final PodcastHttp http;

  /// The private-network hosts an episode's file may reach: its feed's own
  /// host when the listener gave one on their own network (empty for a feed
  /// on the internet).
  final Future<Set<String>> Function(Uri episode) trustedFor;

  @override
  Set<String> get schemes => const {
    'http',
    'https',
    'podcast-http',
    'podcast-https',
  };

  @override
  Set<VirtualFsCapability> get capabilities => const {};

  @override
  Future<VirtualFile> open(Uri uri) async {
    final episode = podcastEpisodeUri(uri) ?? uri;
    if (episode.scheme != 'http' && episode.scheme != 'https') {
      throw VirtualFileException(
        VirtualFileError.unsupported,
        uri,
        'only web addresses',
      );
    }
    try {
      return await http.openFile(episode, trusted: await trustedFor(episode));
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
/// resumable, with a size quota, listed on the Downloads screen too. Episodes
/// are queued under [podcastDownloadUri] and always opened by
/// [HttpUrlFileSystem], never by a mounted source.
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

  /// Makes [queued] (a [podcastDownloadUri]) openable by the download
  /// manager: its host is mounted on [fileSystem] under the podcast scheme.
  void _mount(Uri queued) {
    mounts.mount(
      Uri(
        scheme: queued.scheme,
        host: queued.host,
        port: queued.hasPort ? queued.port : null,
      ),
      fileSystem,
    );
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
      if (u != null && podcastEpisodeUri(u) != null) _mount(u);
    }
  }

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {
    final queued = podcastDownloadUri(url);
    _mount(queued);
    await manager.enqueue(queued, title: title, knownSize: size);
  }

  Future<DownloadRow?> _row(Uri url) =>
      (_db.select(_db.downloads)..where(
            (d) => d.remoteUri.equals(podcastDownloadUri(url).toString()),
          ))
          .getSingleOrNull();

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
