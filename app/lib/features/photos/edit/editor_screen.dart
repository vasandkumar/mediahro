import 'dart:async';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/edit/crop_overlay.dart';
import 'package:mediahro/features/photos/edit/curve_editor.dart';
import 'package:mediahro/features/photos/edit/draw_layer.dart';
import 'package:mediahro/features/photos/edit/edit_geometry.dart';
import 'package:mediahro/features/photos/edit/editor_controller.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/edit/edit_recipe.dart';
import 'package:mediahro/images/image_pipeline.dart';

/// The look copied from the editor, waiting to be applied to other photos.
final copiedLookProvider = NotifierProvider<CopiedLook, EditRecipe?>(
  CopiedLook.new,
);

class CopiedLook extends Notifier<EditRecipe?> {
  @override
  EditRecipe? build() => null;

  // A setter would hide the notifier's own `state`.
  // ignore: use_setters_to_change_properties
  void copy(EditRecipe? look) => state = look;
}

/// Opens the editor on [entry] (IMG-009).
Future<void> openEditor(BuildContext context, PhotoEntry entry) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EditorScreen(entry: entry),
      ),
    );

/// Non-destructive photo editor: crop, rotate and straighten, light, colour,
/// detail, curves, drawing and blurring. The original is untouched until
/// "Save a copy" or "Replace the original"; what is not saved is kept for
/// next time.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({required this.entry, super.key});

  final PhotoEntry entry;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  EditorController? _c;
  Object? _error;
  double? _ratio;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final editor = ref.read(photoEditorProvider);
    try {
      final proxy = await editor.loadProxy(widget.entry);
      final saved = await editor.savedRecipe(widget.entry);
      if (!mounted) return;
      final c = EditorController(
        entry: widget.entry,
        editor: editor,
        proxy: proxy,
        initial: saved,
      );
      setState(() => _c = c);
      await c.start();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Leaves the editor, keeping an unsaved edit for next time.
  Future<void> _close() async {
    final c = _c;
    if (c != null) {
      await ref.read(photoEditorProvider).storeRecipe(widget.entry, c.recipe);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<T?> _busy<T>(String text, Future<T> Function() task) async {
    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      nav.pop();
    }
  }

  Future<void> _saveCopy() async {
    final c = _c;
    if (c == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final name = await _busy(
        l10n.photosEditorSaving,
        () => ref.read(photoEditorProvider).saveCopy(widget.entry, c.recipe),
      );
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosEditorSavedCopy(name ?? ''))),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosEditorSaveFailed)),
      );
    }
  }

  Future<void> _replace() async {
    final c = _c;
    if (c == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photosEditorReplaceTitle),
        content: Text(l10n.photosEditorReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosEditorReplaceConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _busy(
        l10n.photosEditorSaving,
        () => ref
            .read(photoEditorProvider)
            .replaceOriginal(widget.entry, c.recipe),
      );
      c.markSaved();
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosEditorReplaced)),
      );
      nav.pop();
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosEditorSaveFailed)),
      );
    }
  }

  void _copyLook() {
    final c = _c;
    if (c == null) return;
    ref.read(copiedLookProvider.notifier).copy(c.recipe.look());
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).photosEditorLookCopied),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _c;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.photosEditorClose,
            icon: const Icon(Icons.close),
            onPressed: () => unawaited(_close()),
          ),
          title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
          actions: c == null
              ? null
              : [
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Row(
                      children: [
                        IconButton(
                          tooltip: l10n.photosEditUndo,
                          icon: const Icon(Icons.undo),
                          onPressed: c.canUndo ? c.undo : null,
                        ),
                        IconButton(
                          tooltip: l10n.photosEditRedo,
                          icon: const Icon(Icons.redo),
                          onPressed: c.canRedo ? c.redo : null,
                        ),
                        PopupMenuButton<String>(
                          tooltip: l10n.photosMore,
                          onSelected: (v) {
                            switch (v) {
                              case 'copy':
                                unawaited(_saveCopy());
                              case 'replace':
                                unawaited(_replace());
                              case 'look':
                                _copyLook();
                              case 'reset':
                                c.reset();
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'copy',
                              child: Text(l10n.photosEditorSaveCopy),
                            ),
                            PopupMenuItem(
                              value: 'replace',
                              enabled: ref
                                  .read(photoEditorProvider)
                                  .canReplace(widget.entry),
                              child: Text(l10n.photosEditorReplace),
                            ),
                            PopupMenuItem(
                              value: 'look',
                              enabled: c.recipe.hasLook,
                              child: Text(l10n.photosEditorCopyLook),
                            ),
                            PopupMenuItem(
                              value: 'reset',
                              enabled: !c.recipe.isIdentity,
                              child: Text(l10n.photosEditorResetAll),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
        ),
        body: _error != null
            ? Center(
                child: Text(
                  l10n.photosEditorLoadFailed,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : c == null
            ? Center(
                child: Semantics(
                  label: l10n.photosEditorLoading,
                  child: const CircularProgressIndicator(),
                ),
              )
            : ListenableBuilder(
                listenable: c,
                builder: (context, _) => _body(context, c),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, EditorController c) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(child: _canvas(c)),
        // The curve box is dragged in both directions, so it must not sit in
        // something that scrolls (the scroll would take the vertical drags).
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                (c.tool == EditTool.curves ? 0.5 : 0.34),
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: c.tool == EditTool.curves
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _panel(context, c),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _panel(context, c),
                  ),
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: LayoutBuilder(
                builder: (context, box) {
                  final buttons = [
                    for (final t in EditTool.values)
                      _ToolButton(
                        icon: switch (t) {
                          EditTool.crop => Icons.crop_rotate,
                          EditTool.light => Icons.wb_sunny_outlined,
                          EditTool.colour => Icons.palette_outlined,
                          EditTool.detail => Icons.deblur,
                          EditTool.curves => Icons.show_chart,
                          EditTool.draw => Icons.brush_outlined,
                        },
                        label: switch (t) {
                          EditTool.crop => l10n.photosToolCrop,
                          EditTool.light => l10n.photosToolLight,
                          EditTool.colour => l10n.photosToolColour,
                          EditTool.detail => l10n.photosToolDetail,
                          EditTool.curves => l10n.photosToolCurves,
                          EditTool.draw => l10n.photosToolDraw,
                        },
                        selected: c.tool == t,
                        onTap: () => c.selectTool(t),
                      ),
                  ];
                  // All six side by side when they fit, a scrolling row
                  // when the screen or the text size is too big for that.
                  return box.maxWidth >= 6 * 64
                      ? Row(
                          children: [
                            for (final b in buttons) Expanded(child: b),
                          ],
                        )
                      : ListView(
                          scrollDirection: Axis.horizontal,
                          children: buttons,
                        );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _canvas(EditorController c) {
    final img = c.preview;
    if (img == null) {
      return Center(
        child: Semantics(
          label: AppLocalizations.of(context).photosEditorLoading,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(img.width.toDouble(), img.height.toDouble()),
          box.biggest,
        ).destination;
        final rect = Alignment.center.inscribe(
          fitted,
          Offset.zero & box.biggest,
        );
        final aspect = img.width / img.height;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: RawImage(image: img, fit: BoxFit.fill),
            ),
            if (c.tool == EditTool.crop)
              Positioned.fill(
                child: CropOverlay(
                  imageRect: rect,
                  crop: c.recipe.crop,
                  imageAspect: aspect,
                  ratio: _ratio,
                  onStart: c.begin,
                  onChanged: (r) => c.update(c.recipe.copyWith(crop: r)),
                  onEnd: c.commit,
                ),
              ),
            if (c.tool == EditTool.draw)
              Positioned.fill(
                child: DrawLayer(
                  imageRect: rect,
                  imageAspect: aspect,
                  shape: c.shape,
                  colorArgb: c.penColor,
                  width: c.penWidth,
                  onStroke: (s) => c.apply(
                    c.recipe.copyWith(strokes: [...c.recipe.strokes, s]),
                  ),
                  onBlur: (b) =>
                      c.apply(c.recipe.copyWith(blurs: [...c.recipe.blurs, b])),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _panel(BuildContext context, EditorController c) => switch (c.tool) {
    EditTool.crop => _cropPanel(context, c),
    EditTool.light => _sliders(context, c, const [
      AdjustKind.exposure,
      AdjustKind.contrast,
      AdjustKind.highlights,
      AdjustKind.shadows,
      AdjustKind.whites,
      AdjustKind.blacks,
    ]),
    EditTool.colour => _sliders(context, c, const [
      AdjustKind.temperature,
      AdjustKind.tint,
      AdjustKind.saturation,
      AdjustKind.vibrance,
    ]),
    EditTool.detail => _sliders(context, c, const [
      AdjustKind.sharpen,
      AdjustKind.vignette,
    ]),
    EditTool.curves => _CurvesPanel(controller: c),
    EditTool.draw => _drawPanel(context, c),
  };

  Widget _sliders(
    BuildContext context,
    EditorController c,
    List<AdjustKind> kinds,
  ) => Column(
    children: [
      for (final k in kinds)
        AdjustSlider(
          kind: k,
          value: c.recipe.amount(k),
          onStart: c.begin,
          onChanged: (v) => c.update(c.recipe.withAdjust(k, v)),
          onEnd: c.commit,
        ),
    ],
  );

  static const _ratios = <(int, int)>[
    (1, 1),
    (4, 3),
    (3, 2),
    (16, 9),
    (3, 4),
    (2, 3),
    (9, 16),
  ];

  Widget _cropPanel(BuildContext context, EditorController c) {
    final l10n = AppLocalizations.of(context);
    final aspect = c.previewWidth == 0 ? 1.0 : c.previewWidth / c.previewHeight;

    void choose(double? ratio) {
      setState(() => _ratio = ratio);
      if (ratio != null) {
        c.apply(
          c.recipe.copyWith(crop: fitCropRatio(c.recipe.crop, ratio, aspect)),
        );
      }
    }

    Widget chip(String label, double? ratio, {bool? selected}) => ChoiceChip(
      label: Text(label),
      selected:
          selected ??
          (_ratio != null && ratio != null
              ? (_ratio! - ratio).abs() < 1e-6
              : _ratio == ratio),
      onSelected: (_) => choose(ratio),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            chip(l10n.photosCropFree, null),
            chip(l10n.photosCropOriginal, aspect),
            for (final (w, h) in _ratios)
              chip(l10n.photosCropRatio(w, h), w / h),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: l10n.photosCropRotateLeft,
              icon: const Icon(Icons.rotate_left),
              onPressed: () => c.apply(
                c.recipe.copyWith(
                  turns: c.recipe.turns + 3,
                  crop: NormRect.full,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.photosCropRotateRight,
              icon: const Icon(Icons.rotate_right),
              onPressed: () => c.apply(
                c.recipe.copyWith(
                  turns: c.recipe.turns + 1,
                  crop: NormRect.full,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.photosCropFlipHorizontal,
              isSelected: c.recipe.flipHorizontal,
              icon: const Icon(Icons.flip),
              onPressed: () => c.apply(
                c.recipe.copyWith(flipHorizontal: !c.recipe.flipHorizontal),
              ),
            ),
            IconButton(
              tooltip: l10n.photosCropFlipVertical,
              isSelected: c.recipe.flipVertical,
              icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
              onPressed: () => c.apply(
                c.recipe.copyWith(flipVertical: !c.recipe.flipVertical),
              ),
            ),
            TextButton(
              onPressed: c.recipe.crop.isFull
                  ? null
                  : () => c.apply(c.recipe.copyWith(crop: NormRect.full)),
              child: Text(l10n.photosCropReset),
            ),
          ],
        ),
        _StraightenSlider(controller: c),
      ],
    );
  }

  static const _colours = <(int, String)>[
    (0xFFE53935, 'red'),
    (0xFFFB8C00, 'orange'),
    (0xFFFDD835, 'yellow'),
    (0xFF43A047, 'green'),
    (0xFF1E88E5, 'blue'),
    (0xFF8E24AA, 'purple'),
    (0xFFFFFFFF, 'white'),
    (0xFF000000, 'black'),
  ];

  Widget _drawPanel(BuildContext context, EditorController c) {
    final l10n = AppLocalizations.of(context);
    String shapeLabel(DrawShape s) => switch (s) {
      DrawShape.pen => l10n.photosDrawPen,
      DrawShape.line => l10n.photosDrawLine,
      DrawShape.arrow => l10n.photosDrawArrow,
      DrawShape.box => l10n.photosDrawBox,
      DrawShape.blur => l10n.photosDrawBlur,
    };
    String colourName(String id) => switch (id) {
      'red' => l10n.photosColourRed,
      'orange' => l10n.photosColourOrange,
      'yellow' => l10n.photosColourYellow,
      'green' => l10n.photosColourGreen,
      'blue' => l10n.photosColourBlue,
      'purple' => l10n.photosColourPurple,
      'white' => l10n.photosColourWhite,
      _ => l10n.photosColourBlack,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final s in DrawShape.values)
              ChoiceChip(
                label: Text(shapeLabel(s)),
                selected: c.shape == s,
                onSelected: (_) => c.setShape(s),
              ),
          ],
        ),
        if (c.shape != DrawShape.blur) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (final (argb, id) in _colours)
                Semantics(
                  button: true,
                  selected: c.penColor == argb,
                  label: colourName(id),
                  child: InkResponse(
                    radius: 24,
                    onTap: () => c.setPen(color: argb),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(argb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.penColor == argb
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white54,
                            width: c.penColor == argb ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (w, label) in [
                (0.004, l10n.photosDrawThin),
                (0.008, l10n.photosDrawMedium),
                (0.016, l10n.photosDrawThick),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: (c.penWidth - w).abs() < 1e-9,
                  onSelected: (_) => c.setPen(width: w),
                ),
            ],
          ),
        ],
        if (c.recipe.hasAnnotations)
          TextButton(
            onPressed: () => c.apply(c.recipe.copyWith(strokes: [], blurs: [])),
            child: Text(l10n.photosDrawClear),
          ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One adjustment: its name, its value as −100…100 (sharpen 0…100) and a
/// slider; double tap on the name resets it.
class AdjustSlider extends StatelessWidget {
  const AdjustSlider({
    required this.kind,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    super.key,
  });

  final AdjustKind kind;
  final double value;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  bool get _oneSided => kind == AdjustKind.sharpen;

  static String name(AppLocalizations l10n, AdjustKind k) => switch (k) {
    AdjustKind.exposure => l10n.photosAdjExposure,
    AdjustKind.contrast => l10n.photosAdjContrast,
    AdjustKind.highlights => l10n.photosAdjHighlights,
    AdjustKind.shadows => l10n.photosAdjShadows,
    AdjustKind.whites => l10n.photosAdjWhites,
    AdjustKind.blacks => l10n.photosAdjBlacks,
    AdjustKind.saturation => l10n.photosAdjSaturation,
    AdjustKind.vibrance => l10n.photosAdjVibrance,
    AdjustKind.temperature => l10n.photosAdjTemperature,
    AdjustKind.tint => l10n.photosAdjTint,
    AdjustKind.sharpen => l10n.photosAdjSharpen,
    AdjustKind.vignette => l10n.photosAdjVignette,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = name(l10n, kind);
    final shown = (value * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: GestureDetector(
            onDoubleTap: () {
              onStart();
              onChanged(0);
              onEnd();
            },
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        Expanded(
          child: Semantics(
            label: label,
            child: Slider(
              value: value.clamp(_oneSided ? 0.0 : -1.0, 1.0),
              min: _oneSided ? 0 : -1,
              divisions: _oneSided ? 100 : 200,
              semanticFormatterCallback: (v) =>
                  NumberFormat.decimalPattern().format((v * 100).round()),
              onChangeStart: (_) => onStart(),
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            NumberFormat.decimalPattern().format(shown),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _StraightenSlider extends StatelessWidget {
  const _StraightenSlider({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = controller;
    final deg = c.recipe.straighten;
    return Row(
      children: [
        SizedBox(width: 104, child: Text(l10n.photosCropStraighten)),
        Expanded(
          child: Semantics(
            label: l10n.photosCropStraighten,
            child: Slider(
              value: deg.clamp(-45.0, 45.0),
              min: -45,
              max: 45,
              divisions: 900,
              semanticFormatterCallback: (v) =>
                  l10n.photosDegrees(NumberFormat('0.0').format(v)),
              onChangeStart: (_) => c.begin(),
              onChanged: (v) => c.update(
                c.recipe.copyWith(
                  straighten: (v * 10).round() / 10,
                  crop: NormRect.full,
                ),
              ),
              onChangeEnd: (_) => c.commit(),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            l10n.photosDegrees(NumberFormat('0.0').format(deg)),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

/// Channel choice and the curve box.
class _CurvesPanel extends StatefulWidget {
  const _CurvesPanel({required this.controller});

  final EditorController controller;

  @override
  State<_CurvesPanel> createState() => _CurvesPanelState();
}

enum _Channel { master, red, green, blue }

class _CurvesPanelState extends State<_CurvesPanel> {
  _Channel _channel = _Channel.master;

  List<(double, double)> _points(CurveSet s) => switch (_channel) {
    _Channel.master => s.master,
    _Channel.red => s.red,
    _Channel.green => s.green,
    _Channel.blue => s.blue,
  };

  CurveSet _with(CurveSet s, List<(double, double)> p) => switch (_channel) {
    _Channel.master => s.copyWith(master: p),
    _Channel.red => s.copyWith(red: p),
    _Channel.green => s.copyWith(green: p),
    _Channel.blue => s.copyWith(blue: p),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    String name(_Channel ch) => switch (ch) {
      _Channel.master => l10n.photosCurveRgb,
      _Channel.red => l10n.photosCurveRed,
      _Channel.green => l10n.photosCurveGreen,
      _Channel.blue => l10n.photosCurveBlue,
    };
    final color = switch (_channel) {
      _Channel.master => Colors.white,
      _Channel.red => Colors.redAccent,
      _Channel.green => Colors.greenAccent,
      _Channel.blue => Colors.lightBlueAccent,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final ch in _Channel.values)
              ChoiceChip(
                label: Text(name(ch)),
                selected: _channel == ch,
                onSelected: (_) => setState(() => _channel = ch),
              ),
            TextButton(
              onPressed: _points(c.recipe.curves).isEmpty
                  ? null
                  : () => c.apply(
                      c.recipe.copyWith(
                        curves: _with(c.recipe.curves, const []),
                      ),
                    ),
              child: Text(l10n.photosCurveReset),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: CurveEditor(
              points: _points(c.recipe.curves),
              color: color,
              onStart: c.begin,
              onChanged: (p) => c.update(
                c.recipe.copyWith(curves: _with(c.recipe.curves, p)),
              ),
              onEnd: c.commit,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.photosCurveHint,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
