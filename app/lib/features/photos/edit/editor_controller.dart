import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/pixel_codec.dart';

enum EditTool { crop, light, colour, detail, curves, draw }

/// What the pen of the draw tool makes.
enum DrawShape { pen, line, arrow, box, blur }

/// State of one editing session (IMG-009): the recipe being built, its undo
/// history, and the preview picture computed from it. Sliders and drags
/// change the recipe live ([update]); the change is one undo step once the
/// gesture ends ([commit]).
class EditorController extends ChangeNotifier {
  EditorController({
    required this.entry,
    required this.editor,
    required this.proxy,
    EditRecipe initial = EditRecipe.none,
    this.renderDelay = const Duration(milliseconds: 30),
  }) : recipe = initial,
       _savedJson = _json(initial);

  final PhotoEntry entry;
  final PhotoEditor editor;

  /// The reduced picture previews are computed on.
  final PixelFrame proxy;
  final Duration renderDelay;

  EditRecipe recipe;
  EditTool tool = EditTool.light;
  DrawShape shape = DrawShape.pen;
  int penColor = 0xFFE53935;
  double penWidth = 0.008;

  /// The picture of the recipe at preview size; null until the first render.
  ui.Image? preview;
  int previewWidth = 0;
  int previewHeight = 0;
  bool rendering = false;

  final List<EditRecipe> _undo = [];
  final List<EditRecipe> _redo = [];
  EditRecipe? _gestureStart;
  String _savedJson;
  Timer? _timer;
  int _version = 0;
  bool _disposed = false;

  static String _json(EditRecipe r) => jsonEncode(r.toJson());

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Changed since it was opened or last stored.
  bool get dirty => _json(recipe) != _savedJson;

  /// While cropping the whole straightened picture is shown, with the crop
  /// drawn over it.
  EditRecipe get previewRecipe =>
      tool == EditTool.crop ? recipe.copyWith(crop: NormRect.full) : recipe;

  void selectTool(EditTool t) {
    if (t == tool) return;
    tool = t;
    notifyListeners();
    _schedule();
  }

  void setShape(DrawShape s) {
    shape = s;
    notifyListeners();
  }

  void setPen({int? color, double? width}) {
    penColor = color ?? penColor;
    penWidth = width ?? penWidth;
    notifyListeners();
  }

  /// Starts a gesture: the recipe now is the undo step if it changes.
  void begin() => _gestureStart ??= recipe;

  /// Changes the recipe without adding an undo step (a slider being dragged).
  void update(EditRecipe next) {
    begin();
    recipe = next;
    notifyListeners();
    _schedule();
  }

  /// Ends a gesture, making what changed one undo step.
  void commit() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start == null || _json(start) == _json(recipe)) return;
    _undo.add(start);
    _redo.clear();
    notifyListeners();
  }

  /// A change that is one step by itself (a button).
  void apply(EditRecipe next) {
    begin();
    update(next);
    commit();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(recipe);
    recipe = _undo.removeLast();
    _gestureStart = null;
    notifyListeners();
    _schedule();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(recipe);
    recipe = _redo.removeLast();
    _gestureStart = null;
    notifyListeners();
    _schedule();
  }

  /// Back to the untouched photo (one undo step).
  void reset() => apply(EditRecipe.none);

  /// Marks the current recipe as stored, so closing asks nothing.
  void markSaved() {
    _savedJson = _json(recipe);
    notifyListeners();
  }

  /// Computes the first preview.
  Future<void> start() => _render();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(renderDelay, () => unawaited(_render()));
  }

  Future<void> _render() async {
    final mine = ++_version;
    rendering = true;
    notifyListeners();
    ui.Image? image;
    PixelFrame? frame;
    try {
      frame = await editor.render(proxy, previewRecipe);
      image = await uiImageFrom(
        DecodedImage(
          width: frame.width,
          height: frame.height,
          pixels: frame.rgba,
        ),
      );
    } on Object {
      image = null;
    }
    // A newer render started meanwhile: this picture is stale.
    if (_disposed || mine != _version || image == null || frame == null) {
      image?.dispose();
      if (!_disposed && mine == _version) {
        rendering = false;
        notifyListeners();
      }
      return;
    }
    final old = preview;
    preview = image;
    previewWidth = frame.width;
    previewHeight = frame.height;
    rendering = false;
    notifyListeners();
    // The painter may still draw [old] this frame.
    if (old != null) {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => old.dispose())
        ..scheduleFrame();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    preview?.dispose();
    preview = null;
    super.dispose();
  }
}
