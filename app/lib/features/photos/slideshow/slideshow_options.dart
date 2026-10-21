import 'dart:math';

import 'package:mediahro/features/settings/settings_store.dart';
import 'package:meta/meta.dart';

/// How one picture gives way to the next (IMG-012).
enum SlideChange { none, fade, slide, zoom }

/// Where a slideshow's music comes from (IMG-012).
enum SlideMusicSource { none, library, playlist }

/// What the user chose for a slideshow. Remembered between slideshows.
@immutable
final class SlideshowOptions {
  const SlideshowOptions({
    this.interval = 5,
    this.transition = SlideChange.fade,
    this.kenBurns = false,
    this.random = false,
    this.loop = true,
    this.music = SlideMusicSource.none,
    this.playlistId,
    this.speed = 1,
  });

  /// Seconds each picture stays at speed 1.
  final double interval;
  final SlideChange transition;

  /// A slow zoom and drift over each picture.
  final bool kenBurns;
  final bool random;
  final bool loop;
  final SlideMusicSource music;

  /// The playlist when [music] is [SlideMusicSource.playlist].
  final int? playlistId;

  /// Speed multiplier, 0.25 to 4: the time a picture stays is
  /// [interval] / [speed].
  final double speed;

  static const double minInterval = 2;
  static const double maxInterval = 60;
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4;

  /// How long a picture stays on screen.
  Duration get slideDuration => Duration(
    milliseconds: (interval / speed.clamp(minSpeed, maxSpeed) * 1000).round(),
  );

  SlideshowOptions copyWith({
    double? interval,
    SlideChange? transition,
    bool? kenBurns,
    bool? random,
    bool? loop,
    SlideMusicSource? music,
    int? playlistId,
    double? speed,
  }) => SlideshowOptions(
    interval: (interval ?? this.interval).clamp(minInterval, maxInterval),
    transition: transition ?? this.transition,
    kenBurns: kenBurns ?? this.kenBurns,
    random: random ?? this.random,
    loop: loop ?? this.loop,
    music: music ?? this.music,
    playlistId: playlistId ?? this.playlistId,
    speed: (speed ?? this.speed).clamp(minSpeed, maxSpeed),
  );

  @override
  bool operator ==(Object other) =>
      other is SlideshowOptions &&
      other.interval == interval &&
      other.transition == transition &&
      other.kenBurns == kenBurns &&
      other.random == random &&
      other.loop == loop &&
      other.music == music &&
      other.playlistId == playlistId &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(
    interval,
    transition,
    kenBurns,
    random,
    loop,
    music,
    playlistId,
    speed,
  );
}

/// The remembered slideshow choices (Settings store, lane C3).
abstract final class SlideshowSettings {
  static final SettingKey<double> interval = SettingKey.decimal(
    'photos.slideshow.interval',
    defaultValue: 5,
    min: SlideshowOptions.minInterval,
    max: SlideshowOptions.maxInterval,
  );
  static final SettingKey<SlideChange> transition =
      SettingKey.enumeration<SlideChange>(
        'photos.slideshow.transition',
        SlideChange.values,
        defaultValue: SlideChange.fade,
      );
  static final SettingKey<bool> kenBurns = SettingKey.boolean(
    'photos.slideshow.kenBurns',
    defaultValue: false,
  );
  static final SettingKey<bool> random = SettingKey.boolean(
    'photos.slideshow.random',
    defaultValue: false,
  );
  static final SettingKey<bool> loop = SettingKey.boolean(
    'photos.slideshow.loop',
    defaultValue: true,
  );
  static final SettingKey<SlideMusicSource> music =
      SettingKey.enumeration<SlideMusicSource>(
        'photos.slideshow.music',
        SlideMusicSource.values,
        defaultValue: SlideMusicSource.none,
      );
  static final SettingKey<int> playlist = SettingKey.integer(
    'photos.slideshow.playlist',
    defaultValue: 0,
    min: 0,
  );
  static final SettingKey<double> speed = SettingKey.decimal(
    'photos.slideshow.speed',
    defaultValue: 1,
    min: SlideshowOptions.minSpeed,
    max: SlideshowOptions.maxSpeed,
  );

  static SlideshowOptions read(SettingsStore s) => SlideshowOptions(
    interval: s.get(interval),
    transition: s.get(transition),
    kenBurns: s.get(kenBurns),
    random: s.get(random),
    loop: s.get(loop),
    music: s.get(music),
    playlistId: s.get(playlist) == 0 ? null : s.get(playlist),
    speed: s.get(speed),
  );

  static void write(SettingsStore s, SlideshowOptions o) {
    s
      ..set(interval, o.interval)
      ..set(transition, o.transition)
      ..set(kenBurns, o.kenBurns)
      ..set(random, o.random)
      ..set(loop, o.loop)
      ..set(music, o.music)
      ..set(playlist, o.playlistId ?? 0)
      ..set(speed, o.speed);
  }
}

/// Which picture comes after which (IMG-012): the given order, or a shuffle
/// that starts at the chosen picture and shows each once before it repeats.
final class SlideOrder {
  SlideOrder({
    required this.count,
    required this.start,
    required this.random,
    required this.loop,
    Random? rng,
  }) : assert(count > 0, 'a slideshow needs a picture'),
       _order = _build(count, start, random, rng ?? Random());

  final int count;
  final int start;
  final bool random;
  final bool loop;
  final List<int> _order;
  int _at = 0;

  static List<int> _build(int count, int start, bool random, Random rng) {
    final s = start.clamp(0, count - 1);
    if (!random) return [for (var i = 0; i < count; i++) (s + i) % count];
    final rest = [
      for (var i = 0; i < count; i++)
        if (i != s) i,
    ]..shuffle(rng);
    return [s, ...rest];
  }

  /// Index in the photo list of the picture now showing.
  int get current => _order[_at];

  /// 1-based place in the run, for "3 of 40".
  int get place => _at + 1;

  bool get hasNext => loop || _at < count - 1;
  bool get hasPrevious => loop || _at > 0;

  /// The picture that follows, or null at the end of a run that does not loop.
  int? get peekNext {
    if (_at < count - 1) return _order[_at + 1];
    return loop ? _order[0] : null;
  }

  /// Moves on; false at the end of a run that does not loop.
  bool next() {
    if (_at < count - 1) {
      _at++;
      return true;
    }
    if (!loop) return false;
    _at = 0;
    return true;
  }

  /// Steps back; false at the start of a run that does not loop.
  bool previous() {
    if (_at > 0) {
      _at--;
      return true;
    }
    if (!loop) return false;
    _at = count - 1;
    return true;
  }
}
