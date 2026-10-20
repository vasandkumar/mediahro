import 'dart:convert';
import 'dart:io';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/library_views.dart';
import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/library/music_playlists.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:meta/meta.dart';

/// Localised titles for the car tree (resolved once from AppLocalizations).
@immutable
final class MusicBrowseLabels {
  const MusicBrowseLabels({
    required this.queue,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.folders,
    required this.songs,
    required this.unknownArtist,
  });

  final String queue;
  final String playlists;
  final String albums;
  final String artists;
  final String folders;
  final String songs;
  final String unknownArtist;
}

/// The Android Auto / CarPlay browse tree and voice search (MUS-013):
/// queue, playlists, albums, artists and folders, paged; playing a song
/// plays its list from that song. Podcasts join with POD-002.
final class MusicBrowseTree implements MediaBrowseProvider {
  MusicBrowseTree({
    required this.db,
    required this.library,
    required this.playlists,
    required this.views,
    required this.player,
    required this.art,
    required this.labels,
    this.pageSize = 100,
  });

  final LibraryDatabase db;
  final MusicLibrary library;
  final MusicPlaylists playlists;
  final LibraryViews views;
  final MusicPlayer player;
  final ArtworkStore art;
  final MusicBrowseLabels labels;
  final int pageSize;

  static const queueId = 'queue';
  static const playlistsId = 'playlists';
  static const albumsId = 'albums';
  static const artistsId = 'artists';
  static const foldersId = 'folders';

  @override
  Future<List<MediaBrowseNode>> children(String nodeId, {int page = 0}) async {
    final all = await _children(nodeId);
    final from = page * pageSize;
    if (from >= all.length) return const [];
    return all.sublist(from, (from + pageSize).clamp(0, all.length));
  }

  Future<List<MediaBrowseNode>> _children(String id) async {
    if (id == MediaBrowseNode.rootId) {
      return [
        _folder(queueId, labels.queue),
        _folder(playlistsId, labels.playlists),
        _folder(albumsId, labels.albums),
        _folder(artistsId, labels.artists),
        _folder(foldersId, labels.folders),
      ];
    }
    final p = _Id.parse(id);
    switch (p.kind) {
      case queueId:
        final q = player.state.queue;
        return [for (final (i, t) in q.indexed) await _track('q:$i', t)];
      case playlistsId:
        return [
          for (final pl in await playlists.all())
            MediaBrowseNode(
              id: 'pl:${pl.id}',
              title: pl.name,
              subtitle: labels.songs,
              playable: pl.count > 0,
              browsable: true,
            ),
        ];
      case 'pl':
        final tracks = await playlists.tracks(int.parse(p.a));
        return [
          for (final t in tracks) await _track('plt:${p.a}:${t.itemId}', t),
        ];
      case albumsId:
        return [
          for (final a in await library.albums())
            MediaBrowseNode(
              id: 'al:${_enc(a.groupKey)}',
              title: a.title,
              subtitle: a.displayArtist ?? labels.unknownArtist,
              artworkUri: await _artUri(a.coverItemId),
              playable: true,
              browsable: true,
            ),
        ];
      case 'al':
        final tracks = await library.albumTracks(_dec(p.a));
        return [
          for (final t in tracks) await _track('alt:${p.a}:${t.itemId}', t),
        ];
      case artistsId:
        return [
          for (final g in await library.groups(GroupField.albumArtist))
            MediaBrowseNode(
              id: 'ar:${_enc(g.name)}',
              title: g.name,
              artworkUri: await _artUri(g.coverItemId),
              playable: true,
              browsable: true,
            ),
        ];
      case 'ar':
        final tracks = await library.groupTracks(
          GroupField.albumArtist,
          _dec(p.a),
        );
        return [
          for (final t in tracks) await _track('art:${p.a}:${t.itemId}', t),
        ];
      case foldersId:
        final sources = await (db.select(
          db.sources,
        )..where((s) => s.enabled.equals(true))).get();
        return [
          for (final s in sources)
            if (s.includeMusic)
              MediaBrowseNode(
                id: 'fo:${s.id}:${_enc('')}',
                title: s.name,
                playable: false,
                browsable: true,
              ),
        ];
      case 'fo':
        final sid = int.parse(p.a);
        final path = _dec(p.b);
        final folders = await views.folders(sid, path, LibraryMode.music);
        final tracks = await library.folderTracks(sid, path);
        return [
          for (final f in folders)
            MediaBrowseNode(
              id: 'fo:$sid:${_enc(f.path)}',
              title: f.name,
              playable: false,
              browsable: true,
            ),
          for (final t in tracks)
            await _track('fot:$sid:${p.b}:${t.itemId}', t),
        ];
    }
    return const [];
  }

  @override
  Future<List<MediaBrowseNode>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    // "song by artist" (voice) searches both parts.
    final by = RegExp(
      r'^(.*)\s+by\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(q);
    final hits = await _search(
      by?.group(1)?.trim() ?? q,
      artist: by?.group(2)?.trim(),
    );
    return [for (final t in hits) await _track('s:${t.itemId}', t)];
  }

  Future<List<MusicTrack>> _search(String text, {String? artist}) async {
    final all = await library.songs(limit: 5000);
    final t = text.toLowerCase();
    final a = artist?.toLowerCase();
    bool matches(MusicTrack x) {
      final fields = [
        x.title,
        ?x.artist,
        ?x.albumArtist,
        ?x.album,
      ].map((s) => s.toLowerCase());
      final textOk = t.isEmpty || fields.any((f) => f.contains(t));
      final artistOk =
          a == null ||
          (x.artist ?? x.albumArtist ?? '').toLowerCase().contains(a);
      return textOk && artistOk;
    }

    return all.where(matches).take(50).toList();
  }

  @override
  Future<void> play(String nodeId) async {
    final p = _Id.parse(nodeId);
    switch (p.kind) {
      case 'q':
        await player.jumpTo(int.parse(p.a));
      case 'pl':
        await player.playTracks(await playlists.tracks(int.parse(p.a)));
      case 'plt':
        await _playFrom(await playlists.tracks(int.parse(p.a)), p.b);
      case 'al':
        await player.playTracks(await library.albumTracks(_dec(p.a)));
      case 'alt':
        await _playFrom(await library.albumTracks(_dec(p.a)), p.b);
      case 'ar':
        await player.playTracks(
          await library.groupTracks(GroupField.albumArtist, _dec(p.a)),
        );
      case 'art':
        await _playFrom(
          await library.groupTracks(GroupField.albumArtist, _dec(p.a)),
          p.b,
        );
      case 'fot':
        await _playFrom(
          await library.folderTracks(int.parse(p.a), _dec(p.b)),
          p.c,
        );
      case 's':
        final t = await library.track(int.parse(p.a));
        if (t != null) await player.playTracks([t]);
    }
  }

  Future<void> _playFrom(List<MusicTrack> list, String itemId) async {
    final id = int.parse(itemId);
    final i = list.indexWhere((t) => t.itemId == id);
    await player.playTracks(list, start: i < 0 ? 0 : i);
  }

  MediaBrowseNode _folder(String id, String title) =>
      MediaBrowseNode(id: id, title: title, playable: false, browsable: true);

  Future<MediaBrowseNode> _track(String id, MusicTrack t) async =>
      MediaBrowseNode(
        id: id,
        title: t.title,
        subtitle: t.artist ?? t.albumArtist ?? labels.unknownArtist,
        artworkUri: await _artUri(t.itemId),
        playable: true,
        browsable: false,
      );

  Future<Uri?> _artUri(int itemId) async {
    final path = await art.coverPath(itemId);
    return path == null ? null : File(path).uri;
  }

  static String _enc(String s) =>
      base64Url.encode(utf8.encode(s)).replaceAll('=', '');

  static String _dec(String s) {
    final pad = (4 - s.length % 4) % 4;
    return utf8.decode(base64Url.decode(s + '=' * pad));
  }
}

/// `kind:a:b:c` node ids (parts are base64url when they hold free text).
final class _Id {
  _Id(this.kind, this.a, this.b, this.c);

  factory _Id.parse(String id) {
    final p = id.split(':');
    String at(int i) => i < p.length ? p[i] : '';
    return _Id(p.first, at(1), at(2), at(3));
  }

  final String kind;
  final String a;
  final String b;
  final String c;
}
