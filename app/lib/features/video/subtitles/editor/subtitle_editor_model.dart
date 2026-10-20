import 'package:flutter/foundation.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// Formats the editor saves (SUB-030).
enum SaveFormat {
  srt('srt', SubtitleFormat.srt),
  ass('ass', SubtitleFormat.ass),
  vtt('vtt', SubtitleFormat.webvtt);

  const SaveFormat(this.extension, this.format);

  final String extension;
  final SubtitleFormat format;

  SubtitleParser get writer => parserFor(format)!;
}

/// The subtitle editor's state (SUB-030): the document, the bytes it came
/// from (for "fix encoding"), undo/redo, selection and unsaved changes.
/// Parsing runs in an isolate with limits (PRIV-005).
final class SubtitleEditorModel extends ChangeNotifier {
  SubtitleEditorModel._(this.name, this._bytes, this._doc, this._charset);

  /// Parses [bytes] (a file called [name]) off the UI isolate.
  static Future<SubtitleEditorModel> open(
    String name,
    Uint8List bytes, {
    String? charset,
  }) async {
    final format = subtitleFormatForExtension(_ext(name));
    final doc = await parseSubtitlesIsolated(
      bytes,
      format: format == SubtitleFormat.txt ? null : format,
      charset: charset,
    );
    return SubtitleEditorModel._(name, bytes, doc, charset);
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1);
  }

  final String name;
  final Uint8List _bytes;
  SubtitleDocument _doc;
  String? _charset;
  final List<SubtitleDocument> _undo = [];
  final List<SubtitleDocument> _redo = [];
  final Set<int> _selected = {};
  bool _dirty = false;

  SubtitleDocument get document => _doc;
  List<SubtitleCue> get cues => _doc.cues;
  String? get charset => _charset;
  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Set<int> get selected => Set.unmodifiable(_selected);

  /// The selected range, or everything when nothing is selected.
  (int?, int?) get _range {
    if (_selected.isEmpty) return (null, null);
    final s = _selected.toList()..sort();
    return (s.first, s.last);
  }

  void _apply(SubtitleDocument next) {
    _undo.add(_doc);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _doc = next;
    _dirty = true;
    _selected.removeWhere((i) => i >= next.cues.length);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_doc);
    _doc = _undo.removeLast();
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_doc);
    _doc = _redo.removeLast();
    _dirty = true;
    notifyListeners();
  }

  void toggle(int index) {
    if (!_selected.remove(index)) _selected.add(index);
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------ edits

  /// Shifts the selection (or everything) by [offset].
  void shift(Duration offset) {
    final (from, to) = _range;
    _apply(_doc.shift(offset, from: from, to: to));
  }

  void stretch(double factor) => _apply(_doc.stretch(factor));

  /// Resync by two points: cue [a] should start at [aAt], cue [b] at [bAt].
  void resync(int a, Duration aAt, int b, Duration bAt) => _apply(
    _doc.resync(from1: cues[a].start, to1: aAt, from2: cues[b].start, to2: bAt),
  );

  /// Edits one cue's text and times in a single undo step.
  void updateCue(int index, {String? text, Duration? start, Duration? end}) =>
      _apply(
        _doc.replaceCue(
          index,
          cues[index].copyWith(text: text, start: start, end: end),
        ),
      );

  void setText(int index, String text) =>
      _apply(_doc.replaceCue(index, cues[index].copyWith(text: text)));

  void setTimes(int index, Duration start, Duration end) => _apply(
    _doc.replaceCue(index, cues[index].copyWith(start: start, end: end)),
  );

  void split(int index, Duration at) => _apply(_doc.split(index, at));

  /// Merges the selected cues into one.
  void mergeSelected() {
    final (from, to) = _range;
    if (from == null || to == null || from == to) return;
    _apply(_doc.merge(from, to));
    _selected
      ..clear()
      ..add(from);
  }

  void deleteSelected() {
    if (_selected.isEmpty) return;
    _apply(_doc.removeCues({..._selected}));
    _selected.clear();
  }

  /// Adds an empty cue at [at] lasting two seconds.
  int addAt(Duration at) {
    _apply(
      _doc.insertCue(
        SubtitleCue(start: at, end: at + const Duration(seconds: 2), text: ''),
      ),
    );
    return _doc.cueAt(at);
  }

  void fixOverlaps() => _apply(_doc.fixOverlaps());

  /// Re-reads the original bytes as [charset] ("fix encoding"); times and
  /// structure come from the file again, so earlier edits are undone into
  /// history.
  Future<void> reEncode(String? charset) async {
    final format = _doc.format;
    final next = await parseSubtitlesIsolated(
      _bytes,
      format: format,
      charset: charset,
    );
    _charset = charset;
    _apply(next);
  }

  /// The document as [format], UTF-8 with a BOM.
  Uint8List export(SaveFormat format) =>
      encodeSubtitleText(format.writer.write(_doc));

  /// "Film.en.srt" → "Film.en.ass".
  String nameFor(SaveFormat format) {
    final i = name.lastIndexOf('.');
    final stem = i < 0 ? name : name.substring(0, i);
    return '$stem.${format.extension}';
  }

  void markSaved() {
    _dirty = false;
    notifyListeners();
  }
}
