import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/speed.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// What the sleep timer waits for instead of a time (VID-069).
enum StopAfter { item, queue }

/// The "Next: …" card after an item ends (VID-064, docs/06 §3.1).
@immutable
final class NextUp {
  const NextUp(this.request, this.remaining);

  final PlayRequest request;

  /// Seconds left on the countdown.
  final int remaining;
}

/// Drives one [PlaybackEngine] for the video player screen: resume, speed
/// memory, precise seeking, frame step, A-B loop, chapters, bookmarks and
/// post-playback actions (VID-061…064).
///
/// Engine calls go through the frozen `PlaybackEngine` API only.
final class VideoPlayerController extends ChangeNotifier {
  VideoPlayerController({
    required this.engine,
    required this.memory,
    required this.settings,
    this.progress,
    this.onClose,
    this.systemLanguages = const [],
    this.sidecars,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _sub = engine.state.listen(_onState);
  }

  final PlaybackEngine engine;
  final VideoMemory memory;
  final SettingsStore settings;

  /// Library progress for indexed items (LIB-010); null without a library.
  final ProgressRepository? progress;

  /// Leaves the player (post-playback "close").
  final VoidCallback? onClose;

  /// Called when the sleep timer stopped playback at the end of an item.
  VoidCallback? onSleep;

  /// Subtitle files next to streamed videos (SUB-012); null skips them.
  final SidecarLoader? sidecars;

  /// The device's languages (BCP 47 primary subtags), last resort for the
  /// audio track default.
  final List<String> systemLanguages;
  final DateTime Function() _clock;

  /// Below this a position is not worth resuming (matches the library).
  static const minResume = Duration(seconds: 30);

  /// Played fraction after which the item counts as finished.
  static const watchedFraction = 0.9;

  /// How often the play head is saved while playing (CORE-011).
  static const saveInterval = Duration(seconds: 5);

  late final StreamSubscription<PlaybackState> _sub;
  PlaybackState _state = const PlaybackState();
  PlayRequest? _request;
  DateTime? _lastSave;
  Duration? _resumedFrom;
  Duration? _abA;
  Duration? _abB;
  int? _abCount;
  NextUp? _nextUp;
  Timer? _countdown;
  bool _deletePending = false;
  bool _endHandled = false;
  bool _disposed = false;

  PlaybackState get state => _state;
  PlayRequest? get request => _request;

  /// Where playback resumed, for the "Start over" prompt; null otherwise.
  Duration? get resumedFrom => _resumedFrom;
  Duration? get abA => _abA;
  Duration? get abB => _abB;

  /// Loop repetitions; null loops until cleared.
  int? get abCount => _abCount;
  NextUp? get nextUp => _nextUp;

  /// True while the "Delete this file?" confirmation should show.
  bool get deletePending => _deletePending;

  List<Chapter> get chapters =>
      _state.chapters.isNotEmpty ? _state.chapters : _request?.chapters ?? [];

  List<VideoBookmark> get bookmarks =>
      _request == null ? const [] : memory.item(_request!.memoryKey).bookmarks;

  bool get isPlaying => _state.status == PlaybackStatus.playing;

  // Last values sent to the engine: repeated key presses build on these,
  // not on a state snapshot that has not caught up yet.
  double? _rate;
  double? _volume;
  Duration? _subDelay;
  Duration? _audioDelay;

  double get rate => _rate ?? _state.rate;
  double get volume => _volume ?? _state.volume;
  Duration get subtitleDelay => _subDelay ?? _state.subtitleDelay;
  Duration get audioDelay => _audioDelay ?? _state.audioDelay;

  // ---------------------------------------------------------------- open

  /// Opens [request], resuming and restoring its speed per the settings.
  Future<void> open(PlayRequest request) async {
    await _saveNow();
    _cancelNextUp();
    _request = request;
    _deletePending = false;
    _endHandled = false;
    _abA = _abB = _abCount = null;
    _rate = _volume = null;
    _videoOffFrom = null;
    _subDelay = _audioDelay = _secondaryDelay = null;
    _subtitleFiles.clear();
    _lastSave = null;
    final m = memory.item(request.memoryKey);
    final resume = settings.get(VideoSettings.resume) == ResumeMode.always
        ? m.position
        : null;
    _resumedFrom = resume;
    notifyListeners();
    final tracks = _trackMemory(request);
    await engine.open(
      await request.mediaSource(),
      opts: OpenOptions(
        start: resume,
        chapters: request.chapters,
        preferredAudioLanguages: [
          ?tracks.audioLanguage,
          ...settings.get(VideoSettings.audioLanguages),
          ...systemLanguages,
        ],
        preferredSubtitleLanguages: [
          ?tracks.subtitleLanguage,
          ...settings.get(VideoSettings.subtitleLanguages),
        ],
      ),
    );
    if (tracks.subtitlesOff) await engine.selectTrack(TrackType.subtitle, null);
    if (m.subtitleDelay case final d?) await engine.setSubDelay(d);
    if (m.audioDelay case final d?) await engine.setAudioDelay(d);
    await _applyDeviceVolume(engine.current);
    if (m.subtitleCodepage case final cp?) {
      await engine.setSubtitleCodepage(cp);
    }
    if (m.subtitleSpeed case final sp?) await engine.setSubSpeed(sp);
    final rate = _initialRate(m);
    if (rate != 1) await engine.setRate(rate);
    unawaited(_loadSidecars(request));
  }

  /// Finds and adds the request's subtitle files (SUB-012): sidecars of
  /// videos the engine reads as streams, and the user's subtitle folder.
  /// Then picks the track: what the user chose before, else the preferred
  /// languages, else the first sidecar; "off" stays off.
  Future<void> _loadSidecars(PlayRequest r) async {
    final loader = sidecars;
    final locate = r.locate;
    if (loader == null || locate == null) return;
    final video = await locate();
    if (video == null || !identical(_request, r)) return;
    final folder = settings.get(VideoSettings.subtitleFolder);
    final found = await loader.find(
      video,
      ownFolder: video.scheme != 'file',
      userFolder: folder.isEmpty ? null : Uri.parse(folder),
    );
    if (found.isEmpty || !identical(_request, r) || _disposed) return;
    final before = _state.subtitleTrackId;
    for (final f in found) {
      await addSubtitleFile(
        f.file,
        title: f.title,
        language: f.language,
        source: f.source,
      );
    }
    final mem = _trackMemory(r);
    if (mem.subtitlesOff) {
      await engine.selectTrack(TrackType.subtitle, null);
      return;
    }
    if (before != null) {
      await engine.selectTrack(TrackType.subtitle, before);
      return;
    }
    final added = [
      for (final t in engine.current.tracks)
        if (t.type == TrackType.subtitle && t.isExternal) t,
    ];
    if (added.isEmpty) return;
    final wanted = [
      ?mem.subtitleLanguage,
      ...settings.get(VideoSettings.subtitleLanguages),
    ];
    Track? pick;
    for (final lang in wanted) {
      pick = added.where((t) => _sameLanguage(t.language, lang)).firstOrNull;
      if (pick != null) break;
    }
    pick ??= added.first;
    await engine.selectTrack(TrackType.subtitle, pick.id);
  }

  static bool _sameLanguage(String? a, String b) =>
      a != null &&
      a.toLowerCase().split(RegExp('[-_]')).first ==
          b.toLowerCase().split(RegExp('[-_]')).first;

  /// Adds a subtitle file (picked, dropped or found) as a track (SUB-012)
  /// and returns it once the engine lists it; [select] shows it.
  Future<Track?> addSubtitleFile(
    Uri file, {
    String? title,
    String? language,
    Uri? source,
    bool select = false,
  }) async {
    Set<int> subs(PlaybackState s) => {
      for (final t in s.tracks)
        if (t.type == TrackType.subtitle) t.id,
    };
    Track? added(PlaybackState s, Set<int> before) => s.tracks
        .where((t) => t.type == TrackType.subtitle && !before.contains(t.id))
        .lastOrNull;
    final before = subs(engine.current);
    await engine.addExternalTrack(
      TrackType.subtitle,
      file,
      title: title,
      language: language,
    );
    var track = added(engine.current, before);
    if (track == null) {
      try {
        final s = await engine.state
            .firstWhere((s) => added(s, before) != null)
            .timeout(const Duration(seconds: 3));
        track = added(s, before);
      } on TimeoutException {
        return null;
      }
    }
    if (track != null) _subtitleFiles[track.id] = (file, source, title);
    if (select && track != null) await selectSubtitle(track);
    return track;
  }

  final Map<int, (Uri, Uri?, String?)> _subtitleFiles = {};

  /// Subtitle tracks this player added from files, by track id: the local
  /// copy, where it came from (null for picked files) and its name
  /// (SUB-030 edits them).
  Map<int, (Uri, Uri?, String?)> get subtitleFiles =>
      Map.unmodifiable(_subtitleFiles);

  /// Sends the subtitle style (SUB-014); the screen recomputes it from the
  /// settings and the system caption style.
  Future<void> applySubtitleStyle(SubtitleStyle style) =>
      engine.setSubtitleStyle(style);

  /// Subtitle speed for frame-rate conversion (SUB-015), e.g. 25 / 23.976
  /// for subtitles timed for 23.976 fps on a 25 fps video; remembered per
  /// file.
  Future<void> setSubtitleSpeed(double speed) async {
    await engine.setSubSpeed(speed);
    final key = _request?.memoryKey;
    if (key != null) {
      memory.updateItem(
        key,
        (m) => m.copyWith(subtitleSpeed: () => speed == 1 ? null : speed),
      );
    }
    notifyListeners();
  }

  double get subtitleSpeed => _request == null
      ? 1
      : memory.item(_request!.memoryKey).subtitleSpeed ?? 1;

  // ------------------------------------------------- second subtitles

  /// Second subtitle track shown with the first (SUB-016); null hides it.
  Future<void> selectSecondarySubtitle(Track? t) =>
      selectSubtitle(t, slot: SubtitleSlot.secondary);

  Duration? _secondaryDelay;
  Duration get secondarySubtitleDelay =>
      _secondaryDelay ?? _state.secondarySubtitleDelay;

  /// The second line's own delay (SUB-016), same range as the first.
  Future<void> setSecondarySubtitleDelay(Duration d) async {
    final v = _snap(d, 50, 60000);
    _secondaryDelay = v;
    await engine.setSubDelay(v, slot: SubtitleSlot.secondary);
    notifyListeners();
  }

  /// Forces the subtitle character set, or null for detection (SUB-013);
  /// remembered per file.
  Future<void> setSubtitleCodepage(String? codepage) async {
    await engine.setSubtitleCodepage(codepage);
    final key = _request?.memoryKey;
    if (key != null) {
      memory.updateItem(
        key,
        (m) => m.copyWith(subtitleCodepage: () => codepage),
      );
    }
    notifyListeners();
  }

  /// Current forced character set of this item (SUB-013).
  String? get subtitleCodepage => _request == null
      ? null
      : memory.item(_request!.memoryKey).subtitleCodepage;

  /// Track choices for [r]: per series when it has one, else per item
  /// (VID-065).
  ItemMemory _trackMemory(PlayRequest r) => r.seriesKey != null
      ? memory.series(r.seriesKey!)
      : memory.item(r.memoryKey);

  void _rememberTracks(ItemMemory Function(ItemMemory m) change) {
    final r = _request;
    if (r == null) return;
    if (r.seriesKey != null) {
      memory.updateSeries(r.seriesKey!, change);
    } else {
      memory.updateItem(r.memoryKey, change);
    }
  }

  // --------------------------------------------------------------- tracks

  List<Track> tracksOf(TrackType type) => [
    for (final t in _state.tracks)
      if (t.type == type) t,
  ];

  /// Switches the audio track and remembers its language (VID-065).
  Future<void> selectAudio(Track t) async {
    await engine.selectTrack(TrackType.audio, t.id);
    if (t.language != null) {
      _rememberTracks((m) => m.copyWith(audioLanguage: () => t.language));
    }
  }

  /// Switches subtitles; null turns them off (VID-065).
  Future<void> selectSubtitle(
    Track? t, {
    SubtitleSlot slot = SubtitleSlot.primary,
  }) async {
    await engine.selectTrack(TrackType.subtitle, t?.id, slot: slot);
    if (slot != SubtitleSlot.primary) return;
    _rememberTracks(
      (m) => m.copyWith(
        subtitlesOff: t == null,
        subtitleLanguage: () => t?.language ?? m.subtitleLanguage,
      ),
    );
  }

  /// `S`: next subtitle track, then off.
  Future<void> cycleSubtitle() {
    final subs = tracksOf(TrackType.subtitle);
    if (subs.isEmpty) return Future.value();
    final i = subs.indexWhere((t) => t.id == _state.subtitleTrackId);
    return selectSubtitle(i + 1 < subs.length ? subs[i + 1] : null);
  }

  /// `A`: next audio track.
  Future<void> cycleAudio() {
    final a = tracksOf(TrackType.audio);
    if (a.length < 2) return Future.value();
    final i = a.indexWhere((t) => t.id == _state.audioTrackId);
    return selectAudio(a[(i + 1) % a.length]);
  }

  // ----------------------------------------------------------- video off

  int? _videoOffFrom;

  /// True while the video track is off (audio only, VID-068).
  bool get videoOff => _videoOffFrom != null;

  /// Turns the video track off to save power, or back on (VID-068).
  Future<void> setVideoOff({required bool off}) async {
    if (off) {
      if (_videoOffFrom != null) return;
      final id =
          _state.videoTrackId ?? tracksOf(TrackType.video).firstOrNull?.id;
      if (id == null) return;
      _videoOffFrom = id;
      notifyListeners();
      await engine.selectTrack(TrackType.video, null);
    } else {
      final id = _videoOffFrom;
      if (id == null) return;
      _videoOffFrom = null;
      notifyListeners();
      await engine.selectTrack(TrackType.video, id);
    }
  }

  // --------------------------------------------------------------- volume

  /// 0…1 from the volume gesture; the audio sheet boosts to 3 (VID-066).
  Future<void> setVolume(double v) {
    final x = v.clamp(0.0, 3.0);
    _volume = x;
    memory.setDeviceVolume(_deviceKey(_state), x);
    return engine.setVolume(x);
  }

  static String _deviceKey(PlaybackState s) => s.audio.device ?? 'default';

  /// Each output device keeps its own volume (VID-066): speakers quiet,
  /// headphones louder, a TV boosted.
  Future<void> _applyDeviceVolume(PlaybackState s) async {
    final v = memory.deviceVolume(_deviceKey(s));
    if (v == null || v == volume) return;
    _volume = v;
    await engine.setVolume(v);
  }

  Future<void> toggleMute() => engine.setMuted(muted: !_state.muted);

  // --------------------------------------------------------------- delays

  static Duration _snap(Duration d, int stepMs, int maxMs) {
    final ms = (d.inMilliseconds / stepMs).round() * stepMs;
    return Duration(milliseconds: ms.clamp(-maxMs, maxMs));
  }

  /// Subtitle delay, ±60 s in 50 ms steps, remembered per file (SUB-015).
  Future<void> setSubtitleDelay(Duration d) async {
    final v = _snap(d, 50, 60000);
    _subDelay = v;
    await engine.setSubDelay(v);
    final key = _request?.memoryKey;
    if (key != null) {
      memory.updateItem(
        key,
        (m) => m.copyWith(subtitleDelay: () => v == Duration.zero ? null : v),
      );
    }
  }

  /// Audio delay, ±5 s in 10 ms steps, remembered per file (VID-066).
  Future<void> setAudioDelay(Duration d) async {
    final v = _snap(d, 10, 5000);
    _audioDelay = v;
    await engine.setAudioDelay(v);
    final key = _request?.memoryKey;
    if (key != null) {
      memory.updateItem(
        key,
        (m) => m.copyWith(audioDelay: () => v == Duration.zero ? null : v),
      );
    }
  }

  double _initialRate(ItemMemory m) =>
      switch (settings.get(VideoSettings.speedMemory)) {
        SpeedMemory.perItem => m.rate ?? 1,
        SpeedMemory.global => memory.globalRate ?? 1,
        SpeedMemory.off => 1,
      };

  /// Restarts from the beginning (the "Start over" action).
  Future<void> startOver() async {
    _resumedFrom = null;
    notifyListeners();
    await engine.seek(Duration.zero, mode: SeekMode.exact);
  }

  void dismissResumed() {
    if (_resumedFrom == null) return;
    _resumedFrom = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ transport

  Future<void> togglePlay() async {
    if (_state.status == PlaybackStatus.ended) {
      _cancelNextUp();
      _endHandled = false;
      await engine.seek(Duration.zero, mode: SeekMode.exact);
      await engine.play();
    } else if (isPlaying) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Duration get _duration => _state.duration ?? Duration.zero;

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    final total = _duration;
    return total > Duration.zero && d > total ? total : d;
  }

  /// Seeks to [to], frame-accurately (VID-061). Keyframe seeks are not used:
  /// with long keyframe intervals they land seconds away from the target.
  Future<void> seekTo(Duration to) =>
      engine.seek(_clamp(to), mode: SeekMode.exact);

  Future<void> seekBy(Duration delta) => seekTo(_state.position + delta);

  /// Jumps to [percent] of the duration (keys 1–9).
  Future<void> jumpToPercent(int percent) =>
      seekTo(_duration * (percent / 100));

  Future<void> frameStep({bool backwards = false}) =>
      engine.frameStep(backwards: backwards);

  // ---------------------------------------------------------------- speed

  /// Sets the speed (VID-062) and remembers it per the speed-memory setting.
  Future<void> setRate(double rate) async {
    final r = PlaybackSpeed.normalize(rate);
    _rate = r;
    await engine.setRate(r);
    final key = _request?.memoryKey;
    switch (settings.get(VideoSettings.speedMemory)) {
      case SpeedMemory.perItem:
        if (key != null) {
          memory.updateItem(
            key,
            (m) => m.copyWith(rate: () => r == 1 ? null : r),
          );
        }
        memory.globalRate = r;
      case SpeedMemory.global:
        memory.globalRate = r;
      case SpeedMemory.off:
        break;
    }
    notifyListeners();
  }

  Future<void> nudgeRate({required bool up}) =>
      setRate(rate + (up ? PlaybackSpeed.nudge : -PlaybackSpeed.nudge));

  Future<void> resetRate() => setRate(1);

  double? _heldFrom;

  /// Long-press speed (VID-060): [rate] while held, not remembered.
  Future<void> holdRate(double held) async {
    _heldFrom ??= rate;
    await engine.setRate(PlaybackSpeed.normalize(held));
  }

  Future<void> releaseRate() async {
    final r = _heldFrom;
    _heldFrom = null;
    if (r != null) await engine.setRate(r);
  }

  bool get isRateHeld => _heldFrom != null;

  // --------------------------------------------------------- A-B loop

  /// `B` key: sets A, then B (starting the loop), then starts over at A.
  Future<void> markLoopPoint() async {
    final pos = _state.position;
    if (_abA == null || _abB != null) {
      if (_abB != null) await engine.setAbLoop(null, null);
      _abA = pos;
      _abB = null;
    } else if (pos > _abA!) {
      _abB = pos;
      await engine.setAbLoop(_abA, _abB, count: _abCount);
    } else {
      _abA = pos;
    }
    notifyListeners();
  }

  Future<void> setLoop(Duration a, Duration b, {int? count}) async {
    _abA = a < b ? a : b;
    _abB = a < b ? b : a;
    _abCount = count;
    await engine.setAbLoop(_abA, _abB, count: count);
    notifyListeners();
  }

  /// Repetitions for the A-B loop; null loops until cleared.
  Future<void> setLoopCount(int? count) async {
    _abCount = count;
    if (_abA != null && _abB != null) {
      await engine.setAbLoop(_abA, _abB, count: count);
    }
    notifyListeners();
  }

  Future<void> clearLoop() async {
    _abA = _abB = null;
    await engine.setAbLoop(null, null);
    notifyListeners();
  }

  // ------------------------------------------------- chapters, bookmarks

  Future<void> seekToChapter(Chapter c) => seekTo(c.start);

  /// Index of the chapter at the play head, or -1.
  int get currentChapter {
    final cs = chapters;
    for (var i = cs.length - 1; i >= 0; i--) {
      if (_state.position >= cs[i].start) return i;
    }
    return -1;
  }

  Future<void> nextChapter() async {
    final cs = chapters;
    final i = currentChapter + 1;
    if (i < cs.length) await seekToChapter(cs[i]);
  }

  Future<void> previousChapter() async {
    final cs = chapters;
    final i = currentChapter;
    if (i < 0) return;
    // Within 3 s of a chapter start, go to the one before.
    final back = _state.position - cs[i].start < const Duration(seconds: 3);
    final target = back && i > 0 ? cs[i - 1] : cs[i];
    await seekToChapter(target);
  }

  VideoBookmark? addBookmark({String note = '', Duration? at}) {
    final key = _request?.memoryKey;
    if (key == null) return null;
    final b = VideoBookmark(position: at ?? _state.position, note: note);
    memory.updateItem(
      key,
      (m) => m.copyWith(
        bookmarks: [...m.bookmarks.where((x) => x.position != b.position), b]
          ..sort((x, y) => x.position.compareTo(y.position)),
      ),
    );
    notifyListeners();
    return b;
  }

  void editBookmark(VideoBookmark b, String note) {
    final key = _request?.memoryKey;
    if (key == null) return;
    memory.updateItem(
      key,
      (m) => m.copyWith(
        bookmarks: [
          for (final x in m.bookmarks)
            if (x == b) VideoBookmark(position: x.position, note: note) else x,
        ],
      ),
    );
    notifyListeners();
  }

  void removeBookmark(VideoBookmark b) {
    final key = _request?.memoryKey;
    if (key == null) return;
    memory.updateItem(
      key,
      (m) => m.copyWith(bookmarks: [...m.bookmarks.where((x) => x != b)]),
    );
    notifyListeners();
  }

  // ------------------------------------------------------ post-playback

  Future<void> playNextNow() async {
    final n = _nextUp?.request ?? _nextRequest;
    if (n == null) return;
    await open(n);
  }

  void cancelNextUp() {
    _cancelNextUp();
    notifyListeners();
  }

  void _cancelNextUp() {
    _countdown?.cancel();
    _countdown = null;
    _nextUp = null;
  }

  PlayRequest? get _nextRequest {
    final r = _request;
    return r == null || r.next.isEmpty ? null : r.advance();
  }

  /// Confirms "delete with confirmation" (VID-064), then continues.
  Future<void> confirmDelete() async {
    final r = _request;
    _deletePending = false;
    notifyListeners();
    if (r?.onDelete == null) return;
    await engine.stop();
    await r!.onDelete!();
    memory.updateItem(r.memoryKey, (_) => const ItemMemory());
    final n = _nextRequest;
    if (n != null) {
      await open(n);
    } else {
      onClose?.call();
    }
  }

  void cancelDelete() {
    _deletePending = false;
    notifyListeners();
  }

  /// Set by the sleep timer (VID-069): stop when this item, or the last
  /// queued item, ends, whatever the post-playback setting says.
  StopAfter? stopAfter;

  Future<void> _onEnded() async {
    if (_endHandled) return;
    _endHandled = true;
    await _saveNow(finished: true);
    final stop = switch (stopAfter) {
      StopAfter.item => true,
      StopAfter.queue => _nextRequest == null,
      null => false,
    };
    if (stop) {
      stopAfter = null;
      onSleep?.call();
      if (!_disposed) notifyListeners();
      return;
    }
    switch (settings.get(VideoSettings.afterPlayback)) {
      case PostPlayback.stop:
        break;
      case PostPlayback.next:
        final n = _nextRequest;
        if (n == null) break;
        final seconds = settings.get(VideoSettings.nextCountdown);
        if (seconds == 0) {
          await open(n);
          return;
        }
        _nextUp = NextUp(n, seconds);
        _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
          final left = (_nextUp?.remaining ?? 1) - 1;
          if (left <= 0) {
            unawaited(open(n));
          } else {
            _nextUp = NextUp(n, left);
            notifyListeners();
          }
        });
      case PostPlayback.repeat:
        _endHandled = false;
        await engine.seek(Duration.zero, mode: SeekMode.exact);
        await engine.play();
      case PostPlayback.close:
        onClose?.call();
      case PostPlayback.delete:
        if (_request?.onDelete != null) _deletePending = true;
    }
    if (!_disposed) notifyListeners();
  }

  // ----------------------------------------------------------- persistence

  void _onState(PlaybackState s) {
    final prev = _state;
    _state = s;
    if (s.audio.device != prev.audio.device && _request != null) {
      unawaited(_applyDeviceVolume(s));
    }
    if (s.status == PlaybackStatus.ended && prev.status != s.status) {
      unawaited(_onEnded());
    } else if (s.status == PlaybackStatus.playing) {
      final last = _lastSave;
      if (last == null || _clock().difference(last) >= saveInterval) {
        unawaited(_saveNow());
      }
    } else if (prev.status == PlaybackStatus.playing &&
        s.status == PlaybackStatus.paused) {
      unawaited(_saveNow());
    }
    if (_resumedFrom != null &&
        s.status == PlaybackStatus.playing &&
        s.position - _resumedFrom! > const Duration(seconds: 10)) {
      _resumedFrom = null;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _saveNow({bool finished = false}) async {
    final r = _request;
    if (r == null) return;
    _lastSave = _clock();
    final pos = _state.position;
    final dur = _state.duration;
    final done =
        finished ||
        (dur != null &&
            dur > Duration.zero &&
            pos.inMilliseconds >= dur.inMilliseconds * watchedFraction);
    final keep = !done && pos >= minResume;
    memory.updateItem(
      r.memoryKey,
      (m) => m.copyWith(position: () => keep ? pos : null, duration: () => dur),
    );
    final id = r.itemId;
    final p = progress;
    if (id != null && p != null) {
      if (done) {
        await p.markWatched([id], watched: true);
      } else {
        await p.savePosition(id, pos, duration: dur);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelNextUp();
    unawaited(_saveNow());
    unawaited(_sub.cancel());
    super.dispose();
  }
}
