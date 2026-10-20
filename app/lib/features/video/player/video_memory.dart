import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/core/providers.dart';

/// A user bookmark with an optional note (VID-063).
@immutable
final class VideoBookmark {
  const VideoBookmark({required this.position, this.note = ''});

  factory VideoBookmark.fromJson(Map<String, Object?> j) => VideoBookmark(
    position: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    note: j['note'] as String? ?? '',
  );

  final Duration position;
  final String note;

  Map<String, Object?> toJson() => {
    'ms': position.inMilliseconds,
    if (note.isNotEmpty) 'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is VideoBookmark &&
      other.position == position &&
      other.note == note;

  @override
  int get hashCode => Object.hash(position, note);
}

/// What the player remembers about one item (VID-062…066).
@immutable
final class ItemMemory {
  const ItemMemory({
    this.position,
    this.duration,
    this.rate,
    this.bookmarks = const [],
    this.audioLanguage,
    this.subtitleLanguage,
    this.subtitlesOff = false,
    this.subtitleDelay,
    this.audioDelay,
    this.updatedAt,
  });

  factory ItemMemory.fromJson(Map<String, Object?> j) {
    Duration? ms(String k) => switch (j[k]) {
      final num v => Duration(milliseconds: v.toInt()),
      _ => null,
    };
    return ItemMemory(
      position: ms('pos'),
      duration: ms('dur'),
      rate: (j['rate'] as num?)?.toDouble(),
      bookmarks: [
        for (final b in (j['bm'] as List?) ?? const [])
          if (b is Map) VideoBookmark.fromJson(b.cast<String, Object?>()),
      ],
      audioLanguage: j['aLang'] as String?,
      subtitleLanguage: j['sLang'] as String?,
      subtitlesOff: j['sOff'] == true,
      subtitleDelay: ms('sDelay'),
      audioDelay: ms('aDelay'),
      updatedAt: switch (j['at']) {
        final int v => DateTime.fromMillisecondsSinceEpoch(v),
        _ => null,
      },
    );
  }

  /// Resume point; null when the item finished or never got far enough.
  final Duration? position;
  final Duration? duration;

  /// Per-item speed (VID-062).
  final double? rate;
  final List<VideoBookmark> bookmarks;
  final String? audioLanguage;
  final String? subtitleLanguage;
  final bool subtitlesOff;
  final Duration? subtitleDelay;
  final Duration? audioDelay;
  final DateTime? updatedAt;

  bool get isEmpty =>
      position == null &&
      rate == null &&
      bookmarks.isEmpty &&
      audioLanguage == null &&
      subtitleLanguage == null &&
      !subtitlesOff &&
      subtitleDelay == null &&
      audioDelay == null;

  ItemMemory copyWith({
    Duration? Function()? position,
    Duration? Function()? duration,
    double? Function()? rate,
    List<VideoBookmark>? bookmarks,
    String? Function()? audioLanguage,
    String? Function()? subtitleLanguage,
    bool? subtitlesOff,
    Duration? Function()? subtitleDelay,
    Duration? Function()? audioDelay,
    DateTime? updatedAt,
  }) => ItemMemory(
    position: position == null ? this.position : position(),
    duration: duration == null ? this.duration : duration(),
    rate: rate == null ? this.rate : rate(),
    bookmarks: bookmarks ?? this.bookmarks,
    audioLanguage: audioLanguage == null ? this.audioLanguage : audioLanguage(),
    subtitleLanguage: subtitleLanguage == null
        ? this.subtitleLanguage
        : subtitleLanguage(),
    subtitlesOff: subtitlesOff ?? this.subtitlesOff,
    subtitleDelay: subtitleDelay == null ? this.subtitleDelay : subtitleDelay(),
    audioDelay: audioDelay == null ? this.audioDelay : audioDelay(),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    if (position != null) 'pos': position!.inMilliseconds,
    if (duration != null) 'dur': duration!.inMilliseconds,
    if (rate != null) 'rate': rate,
    if (bookmarks.isNotEmpty) 'bm': [for (final b in bookmarks) b.toJson()],
    if (audioLanguage != null) 'aLang': audioLanguage,
    if (subtitleLanguage != null) 'sLang': subtitleLanguage,
    if (subtitlesOff) 'sOff': true,
    if (subtitleDelay != null) 'sDelay': subtitleDelay!.inMilliseconds,
    if (audioDelay != null) 'aDelay': audioDelay!.inMilliseconds,
    if (updatedAt != null) 'at': updatedAt!.millisecondsSinceEpoch,
  };
}

/// Where [VideoMemory] keeps its JSON.
abstract interface class VideoMemoryPersistence {
  Future<String?> read();
  Future<void> write(String json);
}

final class MemoryVideoMemoryPersistence implements VideoMemoryPersistence {
  MemoryVideoMemoryPersistence([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// `video_memory.json` in the app data directory, replaced atomically.
final class FileVideoMemoryPersistence implements VideoMemoryPersistence {
  FileVideoMemoryPersistence(this.file);

  final File file;

  @override
  Future<String?> read() async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }
}

/// Per-item and per-series player memory (VID-062 speed, VID-063 bookmarks,
/// VID-064 resume, VID-065 tracks, VID-066 delays and per-device volume).
///
/// Bounded to [maxItems] (least recently used first out) so the file stays
/// small. Writes are coalesced; call [flush] before the app exits.
final class VideoMemory extends ChangeNotifier {
  VideoMemory._(
    this._persistence, {
    required this.maxItems,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static Future<VideoMemory> open(
    VideoMemoryPersistence persistence, {
    int maxItems = 5000,
    DateTime Function()? clock,
  }) async {
    final m = VideoMemory._(persistence, maxItems: maxItems, clock: clock);
    await m._load();
    return m;
  }

  final VideoMemoryPersistence _persistence;
  final DateTime Function() _clock;
  final int maxItems;
  final Map<String, ItemMemory> _items = {};
  final Map<String, ItemMemory> _series = {};
  final Map<String, double> _deviceVolume = {};
  double? _globalRate;
  Timer? _pending;
  Future<void>? _writing;

  Future<void> _load() async {
    final raw = await _persistence.read();
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      for (final MapEntry(:key, :value)
          in ((j['items'] as Map?) ?? {}).entries) {
        if (key is String && value is Map) {
          _items[key] = ItemMemory.fromJson(value.cast<String, Object?>());
        }
      }
      for (final MapEntry(:key, :value)
          in ((j['series'] as Map?) ?? {}).entries) {
        if (key is String && value is Map) {
          _series[key] = ItemMemory.fromJson(value.cast<String, Object?>());
        }
      }
      for (final MapEntry(:key, :value)
          in ((j['volume'] as Map?) ?? {}).entries) {
        if (key is String && value is num) {
          _deviceVolume[key] = value.toDouble();
        }
      }
      _globalRate = (j['rate'] as num?)?.toDouble();
    } on FormatException {
      // A corrupt file starts empty rather than blocking playback.
    }
  }

  ItemMemory item(String key) => _items[key] ?? const ItemMemory();

  ItemMemory series(String key) => _series[key] ?? const ItemMemory();

  /// Last speed chosen anywhere (VID-062 global memory).
  double? get globalRate => _globalRate;

  double? deviceVolume(String deviceId) => _deviceVolume[deviceId];

  void updateItem(String key, ItemMemory Function(ItemMemory m) change) {
    final next = change(item(key)).copyWith(updatedAt: _clock());
    if (next.isEmpty) {
      _items.remove(key);
    } else {
      _items
        ..remove(key)
        ..[key] = next;
      while (_items.length > maxItems) {
        _items.remove(_items.keys.first);
      }
    }
    _changed();
  }

  void updateSeries(String key, ItemMemory Function(ItemMemory m) change) {
    _series[key] = change(series(key)).copyWith(updatedAt: _clock());
    _changed();
  }

  set globalRate(double? rate) {
    _globalRate = rate;
    _changed();
  }

  void setDeviceVolume(String deviceId, double volume) {
    _deviceVolume[deviceId] = volume;
    _changed();
  }

  void _changed() {
    notifyListeners();
    _pending ??= Timer(const Duration(milliseconds: 500), () {
      _pending = null;
      unawaited(flush());
    });
  }

  String _encode() => jsonEncode({
    'v': 1,
    if (_globalRate != null) 'rate': _globalRate,
    'items': {for (final e in _items.entries) e.key: e.value.toJson()},
    'series': {for (final e in _series.entries) e.key: e.value.toJson()},
    'volume': _deviceVolume,
  });

  /// Writes pending changes now.
  Future<void> flush() async {
    _pending?.cancel();
    _pending = null;
    await _writing;
    final w = _persistence.write(_encode());
    _writing = w;
    await w;
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }
}

/// Opened once by the player; override with a memory store in tests.
final videoMemoryProvider = FutureProvider<VideoMemory>((ref) async {
  final dir = ref.watch(appDataDirectoryProvider);
  final m = await VideoMemory.open(
    FileVideoMemoryPersistence(File('${dir.path}/video_memory.json')),
  );
  ref.onDispose(() {
    unawaited(m.flush());
    m.dispose();
  });
  return m;
});
