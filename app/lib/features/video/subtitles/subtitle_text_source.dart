import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// The text of the primary subtitles at the play head, for reading aloud
/// (SUB-040) and translation (SUB-053).
///
/// Works for subtitle tracks the player added from files (sidecars, added
/// or saved files): they are parsed here, and the cue is found with the
/// subtitle delay and speed applied. Built-in tracks need the engine's
/// subtitle text (ADR request); [available] is false for them.
final class SubtitleTextSource extends ChangeNotifier {
  SubtitleTextSource(this.controller) {
    controller.addListener(_onChange);
  }

  final VideoPlayerController controller;

  int? _trackId;
  SubtitleDocument? _doc;
  SubtitleCue? _cue;
  Future<void>? _loading;

  /// The cue showing now; null between cues or without a source.
  SubtitleCue? get cue => _cue;

  /// The parsed document of the selected track, once loaded.
  SubtitleDocument? get document => _doc;

  /// Whether the selected subtitles can be read here (a file track).
  bool get available =>
      controller.subtitleFiles.containsKey(controller.state.subtitleTrackId);

  /// Language of the selected track (BCP 47 or ISO 639), when known.
  String? get language => controller
      .tracksOf(TrackType.subtitle)
      .where((t) => t.id == controller.state.subtitleTrackId)
      .firstOrNull
      ?.language;

  void _onChange() {
    final id = controller.state.subtitleTrackId;
    if (id != _trackId) {
      _trackId = id;
      _doc = null;
      _setCue(null);
      final file = controller.subtitleFiles[id];
      if (file != null) _loading = _load(id!, file.$1);
      return;
    }
    _update();
  }

  /// Loads the selected track now and returns its document (null for a
  /// built-in track).
  Future<SubtitleDocument?> load() async {
    _onChange();
    await _loading;
    return _doc;
  }

  Future<void> _load(int id, Uri file) async {
    try {
      final doc = await parseSubtitlesIsolated(
        await File.fromUri(file).readAsBytes(),
        format: subtitleFormatForExtension(_ext(file.path)),
        charset: controller.subtitleCodepage,
      );
      if (_trackId != id) return;
      _doc = doc;
      _update();
    } on SubtitleParseException {
      // Not a text format (image subtitles): nothing to read.
    } on FileSystemException {
      // The cached copy went away.
    }
  }

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1);
  }

  void _update() {
    final doc = _doc;
    if (doc == null) return;
    final s = controller.state;
    final speed = controller.subtitleSpeed;
    // mpv shows a cue at (t * speed) + delay.
    final t = Duration(
      microseconds:
          ((s.position - controller.subtitleDelay).inMicroseconds / speed)
              .round(),
    );
    final i = doc.cueAt(t);
    _setCue(i < 0 ? null : doc.cues[i]);
  }

  void _setCue(SubtitleCue? c) {
    if (c == _cue) return;
    _cue = c;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    super.dispose();
  }
}
