import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/features/photos/batch/photo_batch_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';

/// Opens the batch screen for [photos] (IMG-010).
Future<void> openBatch(BuildContext context, List<PhotoEntry> photos) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BatchScreen(photos: photos)),
    );

enum BatchAction { rename, convert, upright, strip }

/// Rename with tokens, convert and resize, turn upright by EXIF, strip
/// metadata: one operation on all selected photos, with a preview where one
/// is possible and a report at the end.
class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({required this.photos, super.key});

  final List<PhotoEntry> photos;

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  BatchAction _action = BatchAction.rename;
  final TextEditingController _pattern = TextEditingController(
    text: '{date:yyyy-MM-dd}_{n:3}',
  );
  Set<EncodeFormat> _formats = {
    EncodeFormat.jpeg,
    EncodeFormat.png,
    EncodeFormat.webp,
  };
  EncodeFormat? _format;
  double _quality = 90;
  int? _maxEdge;
  bool _stripOnConvert = false;
  StripScope _scope = StripScope.location;
  bool _cancel = false;

  static const _tokens = [
    '{name}',
    '{n:3}',
    '{date:yyyy-MM-dd}',
    '{date:HHmmss}',
    '{width}',
    '{height}',
  ];
  static const _edges = <int?>[null, 4096, 2048, 1600, 1024];

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(photoBatchProvider).formats().then((f) {
        if (mounted) setState(() => _formats = f);
      }),
    );
  }

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  String _formatName(EncodeFormat f) => switch (f) {
    EncodeFormat.jpeg => 'JPEG',
    EncodeFormat.png => 'PNG',
    EncodeFormat.webp => 'WebP',
    EncodeFormat.jxl => 'JPEG XL',
    EncodeFormat.avif => 'AVIF',
    EncodeFormat.heic => 'HEIC',
  };

  int get _needUpright =>
      widget.photos.where((p) => !p.isVideo && (p.orientation ?? 1) > 1).length;

  Future<bool> _confirm(String body, String yes) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photosBatchChangesOriginals),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final batch = ref.read(photoBatchProvider);
    final photos = widget.photos;
    final Future<BatchReport> Function(
      void Function(int) progress,
      bool Function() cancelled,
    )
    job;
    switch (_action) {
      case BatchAction.rename:
        if (!_renameOk()) return;
        job = (p, c) =>
            batch.rename(photos, _pattern.text, onProgress: p, cancelled: c);
      case BatchAction.convert:
        job = (p, c) => batch.convert(
          photos,
          ConvertOptions(
            format: _format,
            quality: _quality.round(),
            maxEdge: _maxEdge,
            stripMetadata: _stripOnConvert,
          ),
          onProgress: p,
          cancelled: c,
        );
      case BatchAction.upright:
        if (!await _confirm(
          l10n.photosBatchUprightConfirm(_needUpright),
          l10n.photosBatchStartUpright,
        )) {
          return;
        }
        job = (p, c) =>
            batch.uprightByExif(photos, onProgress: p, cancelled: c);
      case BatchAction.strip:
        if (!await _confirm(
          l10n.photosBatchStripConfirm(photos.length),
          l10n.photosBatchStartStrip,
        )) {
          return;
        }
        job = (p, c) =>
            batch.strip(photos, _scope, onProgress: p, cancelled: c);
    }
    if (!mounted) return;
    await _run(job);
  }

  Future<void> _run(
    Future<BatchReport> Function(
      void Function(int) progress,
      bool Function() cancelled,
    )
    job,
  ) async {
    final l10n = AppLocalizations.of(context);
    final done = ValueNotifier<int>(0);
    _cancel = false;
    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<int>(
              valueListenable: done,
              builder: (ctx, n, _) => Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.photosBatchWorking(n, widget.photos.length)),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: n / widget.photos.length),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _cancel = true,
                child: Text(l10n.photosBatchStop),
              ),
            ],
          ),
        ),
      ),
    );
    BatchReport report;
    try {
      report = await job((n) => done.value = n, () => _cancel);
    } on Object {
      report = BatchReport(failed: [for (final p in widget.photos) p.name]);
    } finally {
      nav.pop();
      done.dispose();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photosBatchReportTitle),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.photosBatchReport(
                report.done,
                report.skipped,
                report.failed.length,
              ),
            ),
            if (report.stopped) Text(l10n.photosBatchStopped),
            if (report.failed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.photosBatchFailedList,
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              for (final n in report.failed.take(12)) Text(n),
              if (report.failed.length > 12)
                Text(l10n.photosBatchMore(report.failed.length - 12)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.photosBatchClose),
          ),
        ],
      ),
    );
    if (mounted && report.failed.isEmpty && report.done > 0) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canStart = switch (_action) {
      BatchAction.rename => _renameOk(),
      BatchAction.upright => _needUpright > 0,
      _ => true,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.photosBatchTitle(widget.photos.length))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<BatchAction>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: BatchAction.rename,
                label: Text(l10n.photosBatchRename),
              ),
              ButtonSegment(
                value: BatchAction.convert,
                label: Text(l10n.photosBatchConvert),
              ),
              ButtonSegment(
                value: BatchAction.upright,
                label: Text(l10n.photosBatchUpright),
              ),
              ButtonSegment(
                value: BatchAction.strip,
                label: Text(l10n.photosBatchStrip),
              ),
            ],
            selected: {_action},
            onSelectionChanged: (s) => setState(() => _action = s.first),
          ),
          const SizedBox(height: 16),
          switch (_action) {
            BatchAction.rename => _renamePanel(context),
            BatchAction.convert => _convertPanel(context),
            BatchAction.upright => _uprightPanel(context),
            BatchAction.strip => _stripPanel(context),
          },
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canStart ? () => unawaited(_start()) : null,
            child: Text(switch (_action) {
              BatchAction.rename => l10n.photosBatchStartRename,
              BatchAction.convert => l10n.photosBatchStartConvert,
              BatchAction.upright => l10n.photosBatchStartUpright,
              BatchAction.strip => l10n.photosBatchStartStrip,
            }),
          ),
        ],
      ),
    );
  }

  /// A pattern that expands for every photo to a distinct, valid name.
  bool _renameOk() {
    try {
      return !ref
          .read(photoBatchProvider)
          .previewRename(widget.photos, _pattern.text)
          .any((p) => p.conflict);
    } on PatternError {
      return false;
    }
  }

  Widget _renamePanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final batch = ref.read(photoBatchProvider);
    List<RenamePlan>? plan;
    var invalid = false;
    try {
      plan = batch.previewRename(widget.photos, _pattern.text);
    } on PatternError {
      invalid = true;
    }
    final conflicts = plan?.where((p) => p.conflict).length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _pattern,
          decoration: InputDecoration(
            labelText: l10n.photosBatchPattern,
            helperText: l10n.photosBatchPatternHelp,
            helperMaxLines: 3,
            errorText: invalid ? l10n.photosBatchPatternError : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final t in _tokens)
              ActionChip(
                label: Text(t),
                onPressed: () {
                  final sel = _pattern.selection;
                  final at = sel.isValid ? sel.end : _pattern.text.length;
                  _pattern.value = TextEditingValue(
                    text: _pattern.text.replaceRange(at, at, t),
                    selection: TextSelection.collapsed(offset: at + t.length),
                  );
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.photosBatchPreview,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (plan != null)
          for (final p in plan.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(p.to),
              subtitle: Text(p.from),
              textColor: p.conflict
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
        if (plan != null && plan.length > 8)
          Text(l10n.photosBatchMore(plan.length - 8)),
        if (conflicts > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.photosBatchConflicts,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _convertPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lossy =
        _format == null ||
        _format == EncodeFormat.jpeg ||
        _format == EncodeFormat.webp ||
        _format == EncodeFormat.avif ||
        _format == EncodeFormat.heic ||
        _format == EncodeFormat.jxl;
    final order = [
      EncodeFormat.jpeg,
      EncodeFormat.png,
      EncodeFormat.webp,
      EncodeFormat.jxl,
      EncodeFormat.avif,
      EncodeFormat.heic,
    ].where(_formats.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.photosBatchFormat,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.photosBatchSameFormat),
              selected: _format == null,
              onSelected: (_) => setState(() => _format = null),
            ),
            for (final f in order)
              ChoiceChip(
                label: Text(_formatName(f)),
                selected: _format == f,
                onSelected: (_) => setState(() => _format = f),
              ),
          ],
        ),
        if (lossy) ...[
          const SizedBox(height: 16),
          Text(l10n.photosBatchQuality(_quality.round())),
          Slider(
            value: _quality,
            min: 40,
            max: 100,
            divisions: 60,
            label: NumberFormat.decimalPattern().format(_quality.round()),
            onChanged: (v) => setState(() => _quality = v),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.photosBatchSize,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final e in _edges)
              ChoiceChip(
                label: Text(
                  e == null
                      ? l10n.photosBatchSizeOriginal
                      : l10n.photosBatchSizeEdge(e),
                ),
                selected: _maxEdge == e,
                onSelected: (_) => setState(() => _maxEdge = e),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _stripOnConvert,
          title: Text(l10n.photosBatchRemoveMetadata),
          onChanged: (v) => setState(() => _stripOnConvert = v),
        ),
        Text(
          l10n.photosBatchConvertNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _uprightPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      _needUpright == 0
          ? l10n.photosBatchUprightNone
          : l10n.photosBatchUprightInfo(_needUpright),
    );
  }

  Widget _stripPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RadioGroup<StripScope>(
      groupValue: _scope,
      onChanged: (v) => setState(() => _scope = v ?? _scope),
      child: Column(
        children: [
          RadioListTile<StripScope>(
            value: StripScope.location,
            title: Text(l10n.photosBatchStripLocation),
            subtitle: Text(l10n.photosBatchStripLocationHint),
          ),
          RadioListTile<StripScope>(
            value: StripScope.everything,
            title: Text(l10n.photosBatchStripEverything),
            subtitle: Text(l10n.photosBatchStripEverythingHint),
          ),
        ],
      ),
    );
  }
}
