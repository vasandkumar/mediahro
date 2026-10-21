import 'dart:async';
import 'dart:math' as math;

import 'package:mediahro/core/net/persistent_network_policy.dart'
    show FeedHostRegistry;
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:meta/meta.dart';

/// A user-added internet radio station (MUS-014): an HTTP/ICY stream, an
/// HLS playlist, or a station playlist URL (.pls/.m3u). No directory and no
/// curated lists (docs/07).
@immutable
final class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.headers = const {},
    this.favourite = false,
  });

  final String id;
  final String name;
  final Uri url;

  /// Custom request headers (e.g. `User-Agent`), NET-006 style.
  final Map<String, String> headers;
  final bool favourite;

  RadioStation copyWith({String? name, Uri? url, bool? favourite}) =>
      RadioStation(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        headers: headers,
        favourite: favourite ?? this.favourite,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url.toString(),
    if (headers.isNotEmpty) 'headers': headers,
    if (favourite) 'favourite': true,
  };

  static RadioStation? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'];
    final name = j['name'];
    final url = Uri.tryParse(j['url'] is String ? j['url']! as String : '');
    if (id is! String || name is! String || url == null || !isStreamUrl(url)) {
      return null;
    }
    return RadioStation(
      id: id,
      name: name,
      url: url,
      headers: {
        if (j['headers'] case final Map<String, Object?> h)
          for (final e in h.entries)
            if (e.value is String) e.key: e.value! as String,
      },
      favourite: j['favourite'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RadioStation &&
      other.id == id &&
      other.name == name &&
      other.url == url &&
      other.favourite == favourite;

  @override
  int get hashCode => Object.hash(id, name, url, favourite);
}

/// Schemes a station may use.
bool isStreamUrl(Uri u) =>
    const {'http', 'https', 'icy', 'rtsp', 'rtmp', 'mms'}.contains(u.scheme) &&
    u.host.isNotEmpty;

/// The user's stations, stored as `music.radio` in the library settings.
final class RadioStations {
  RadioStations(this.prefs, {this.hosts, math.Random? random})
    : _random = random ?? math.Random();

  final MusicPrefs prefs;

  /// Where a station's host is recorded as the user's own choice (PRIV-004),
  /// listed in the privacy dashboard and removed with the station.
  final FeedHostRegistry? hosts;
  final math.Random _random;
  final _changes = StreamController<List<RadioStation>>.broadcast();
  List<RadioStation>? _cache;

  Stream<List<RadioStation>> get changes => _changes.stream;

  Future<List<RadioStation>> all() async => _cache ??= [
    for (final j in await prefs.readList('radio') ?? const <Object?>[])
      ?RadioStation.fromJson(j),
  ];

  String newId() =>
      'st-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}';

  /// Adds or replaces [s] (same id).
  Future<void> save(RadioStation s) async {
    final list = [...await all()];
    final i = list.indexWhere((x) => x.id == s.id);
    if (i < 0) {
      list.add(s);
    } else {
      list[i] = s;
    }
    await _store(list);
  }

  Future<void> delete(String id) async => await _store([
    for (final s in await all())
      if (s.id != id) s,
  ]);

  /// Stations from an M3U/PLS/XSPF playlist; entries that are not stream
  /// URLs are skipped. Returns how many were added.
  Future<int> importPlaylist(ParsedPlaylist p) async {
    final list = [...await all()];
    final known = {for (final s in list) s.url.toString()};
    var added = 0;
    for (final e in p.entries) {
      final url = Uri.tryParse(e.location);
      if (url == null || !isStreamUrl(url) || !known.add(url.toString())) {
        continue;
      }
      list.add(
        RadioStation(
          id: newId(),
          name: (e.title?.trim().isNotEmpty ?? false)
              ? e.title!.trim()
              : url.host,
          url: url,
          headers: e.headers,
        ),
      );
      added++;
    }
    await _store(list);
    return added;
  }

  /// The stations as an M3U playlist (export, sharing between devices).
  Future<String> exportM3u() async {
    final b = StringBuffer('#EXTM3U\n');
    for (final s in await all()) {
      b
        ..writeln('#EXTINF:-1,${s.name.replaceAll('\n', ' ')}')
        ..writeln(s.url);
    }
    return b.toString();
  }

  Future<void> _store(List<RadioStation> list) async {
    final before = _cache ?? const <RadioStation>[];
    _cache = list;
    await prefs.write('radio', [for (final s in list) s.toJson()]);
    final kept = {for (final s in list) s.id};
    for (final s in before) {
      if (!kept.contains(s.id)) await hosts?.removeFeedOwner(owner(s.id));
    }
    await _recordHosts(list);
    if (!_changes.isClosed) _changes.add(list);
  }

  /// The owner name a station's host is recorded under.
  static String owner(String id) => 'radio:$id';

  Future<void> _recordHosts(List<RadioStation> list) async {
    final h = hosts;
    if (h == null) return;
    for (final s in list) {
      await h.addFeedHost(s.url, owner: owner(s.id), label: s.name);
    }
  }

  /// Records the hosts of the stations the user added before hosts were
  /// recorded (they were added by the user, so this is their choice).
  Future<void> syncHosts() async => _recordHosts(await all());

  Future<void> dispose() => _changes.close();
}
