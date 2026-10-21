import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:meta/meta.dart';

/// What this device remembers about one Audiobookshelf item (POD-003): its
/// own speed and silence setting, the place it was left (with whether the
/// server has been told), and the address of its offline copy. The server
/// stays the source of truth for the place once it has been told.
@immutable
final class AbsItemState {
  const AbsItemState({
    this.speed,
    this.skipSilence = false,
    this.position = Duration.zero,
    this.synced = true,
    this.syncedAt,
    this.downloadUri,
  });

  factory AbsItemState.fromJson(Map<String, Object?> j) => AbsItemState(
    speed: j['speed'] is num ? (j['speed']! as num).toDouble() : null,
    skipSilence: j['skip'] == true,
    position: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    synced: j['synced'] != false,
    syncedAt: j['syncedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            j['syncedAt']! as int,
            isUtc: true,
          )
        : null,
    downloadUri: j['dl'] as String?,
  );

  final double? speed;
  final bool skipSilence;
  final Duration position;

  /// The server has this position.
  final bool synced;

  /// When the server was last told a place.
  final DateTime? syncedAt;
  final String? downloadUri;

  AbsItemState copyWith({
    double? speed,
    bool? skipSilence,
    Duration? position,
    bool? synced,
    DateTime? syncedAt,
    String? downloadUri,
    bool clearDownload = false,
  }) => AbsItemState(
    speed: speed ?? this.speed,
    skipSilence: skipSilence ?? this.skipSilence,
    position: position ?? this.position,
    synced: synced ?? this.synced,
    syncedAt: syncedAt ?? this.syncedAt,
    downloadUri: clearDownload ? null : (downloadUri ?? this.downloadUri),
  );

  Map<String, Object?> toJson() => {
    'speed': speed,
    'skip': skipSilence,
    'ms': position.inMilliseconds,
    'synced': synced,
    'syncedAt': syncedAt?.toUtc().millisecondsSinceEpoch,
    'dl': downloadUri,
  };
}

/// Per-item notes in the library's settings table, so they travel with
/// backups (CORE-013).
final class AbsStore {
  AbsStore(this.prefs);

  final MusicPrefs prefs;

  String _key(String accountId, String itemId) => 'abs.i.$accountId.$itemId';

  Future<AbsItemState> item(String accountId, String itemId) async {
    final j = await prefs.readMap(_key(accountId, itemId));
    return j == null ? const AbsItemState() : AbsItemState.fromJson(j);
  }

  Future<void> save(String accountId, String itemId, AbsItemState s) =>
      prefs.write(_key(accountId, itemId), s.toJson());

  /// The speed an item with none of its own starts at: the last one chosen.
  Future<double> lastSpeed() async =>
      (jsonDouble(await prefs.read('abs.lastSpeed')) ?? 1).clamp(0.5, 3.0);

  Future<void> setLastSpeed(double speed) =>
      prefs.write('abs.lastSpeed', speed);
}
