import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/subtitles/editor/subtitle_editor_model.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sheets.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// Where the editor saves (the source's folder when it can be written, else
/// the app's subtitle folder) and what it tells the player.
typedef SubtitleSaver = Future<String?> Function(String name, Uint8List bytes);

/// The subtitle editor (SUB-030): timing shift, two-point resync, frame
/// rate, encoding fix, split, merge, add, delete, undo, and saving as SRT,
/// ASS or WebVTT. With a playing video, "now" fills times and tapping a
/// time jumps there. Text fields use the system spell checker where the
/// platform has one.
class SubtitleEditorScreen extends StatefulWidget {
  const SubtitleEditorScreen({
    required this.model,
    required this.save,
    this.position,
    this.seek,
    super.key,
  });

  final SubtitleEditorModel model;
  final SubtitleSaver save;

  /// The player's position, for "now".
  final Duration Function()? position;
  final void Function(Duration at)? seek;

  @override
  State<SubtitleEditorScreen> createState() => _SubtitleEditorScreenState();
}

class _SubtitleEditorScreenState extends State<SubtitleEditorScreen> {
  SubtitleEditorModel get m => widget.model;

  String _t(Duration d) => formatClock(d);

  Future<void> _save(SaveFormat f) async {
    final l = AppLocalizations.of(context);
    final where = await widget.save(m.nameFor(f), m.export(f));
    if (!mounted) return;
    if (where != null) m.markSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          where == null ? l.videoEditorSaveFailed : l.videoEditorSaved(where),
        ),
      ),
    );
  }

  Future<Duration?> _askOffset() {
    final l = AppLocalizations.of(context);
    final text = TextEditingController(text: '0');
    return showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoEditorShiftTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: text,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: l.videoEditorShiftMs),
            ),
            const SizedBox(height: KSpacing.s8),
            Wrap(
              spacing: KSpacing.s8,
              children: [
                for (final ms in const [-1000, -500, -100, 100, 500, 1000])
                  ActionChip(
                    label: Text(l.videoDelayValue(ms)),
                    onPressed: () =>
                        Navigator.of(context).pop(Duration(milliseconds: ms)),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.videoCancel),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(text.text.trim());
              Navigator.of(context)
                  .pop(v == null ? null : Duration(milliseconds: v));
            },
            child: Text(l.videoEditorApply),
          ),
        ],
      ),
    );
  }

  Future<void> _resync() async {
    final l = AppLocalizations.of(context);
    final sel = m.selected.toList()..sort();
    if (sel.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.videoEditorResyncHint)));
      return;
    }
    final a = sel.first;
    final b = sel.last;
    final first = TextEditingController(text: _t(m.cues[a].start));
    final second = TextEditingController(text: _t(m.cues[b].start));
    Widget field(TextEditingController c, String label) => Row(
      children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        if (widget.position != null)
          TextButton(
            onPressed: () => c.text = _t(widget.position!()),
            child: Text(l.videoEditorNow),
          ),
      ],
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoEditorResyncTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.videoEditorResyncBody),
            field(first, l.videoEditorResyncFirst(m.cues[a].plainText)),
            field(second, l.videoEditorResyncSecond(m.cues[b].plainText)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.videoCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.videoEditorApply),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final at1 = parseClock(first.text);
    final at2 = parseClock(second.text);
    if (at1 == null || at2 == null) return;
    m.resync(a, at1, b, at2);
  }

  Future<void> _frameRate() async {
    final l = AppLocalizations.of(context);
    final factor = await showDialog<double>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.videoSubSpeedTitle),
        children: [
          for (final c in subtitleFpsConversions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(fpsFactor(c)),
              child: Text(subtitleSpeedLabel(l, fpsFactor(c))),
            ),
        ],
      ),
    );
    if (factor != null) m.stretch(factor);
  }

  Future<void> _encoding() async {
    final l = AppLocalizations.of(context);
    final decodable = decodableCharsets;
    final choice = await showDialog<(String?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.videoCharsetTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop((null,)),
            child: Text(l.videoCharsetAuto),
          ),
          for (final (iconv, _) in subtitleCharsets)
            if (decodable.contains(iconv))
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop((iconv,)),
                child: Text(charsetLabel(l, iconv)),
              ),
        ],
      ),
    );
    if (choice != null) await m.reEncode(choice.$1);
  }

  Future<void> _edit(int index) async {
    final l = AppLocalizations.of(context);
    final cue = m.cues[index];
    final text = TextEditingController(text: cue.text);
    final start = TextEditingController(text: _t(cue.start));
    final end = TextEditingController(text: _t(cue.end));
    Widget time(TextEditingController c, String label) => Row(
      children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        if (widget.position != null)
          TextButton(
            onPressed: () => c.text = _t(widget.position!()),
            child: Text(l.videoEditorNow),
          ),
      ],
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoEditorEditCue(index + 1)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                // The system spell checker where the platform offers one
                // (Android, iOS); none elsewhere.
                spellCheckConfiguration:
                    WidgetsBinding
                        .instance
                        .platformDispatcher
                        .nativeSpellCheckServiceDefined
                    ? const SpellCheckConfiguration()
                    : null,
                decoration: InputDecoration(labelText: l.videoEditorText),
              ),
              time(start, l.videoEditorStart),
              time(end, l.videoEditorEnd),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.videoCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.videoSave),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final s = parseClock(start.text);
    final e = parseClock(end.text);
    final timesOk = s != null && e != null && e > s;
    if (text.text == cue.text &&
        (!timesOk || (s == cue.start && e == cue.end))) {
      return;
    }
    m.updateCue(
      index,
      text: text.text,
      start: timesOk ? s : null,
      end: timesOk ? e : null,
    );
  }

  Future<bool> _confirmLeave() async {
    if (!m.dirty) return true;
    final l = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoEditorDiscardTitle),
        content: Text(l.videoEditorDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.videoEditorKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.videoEditorDiscard),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final now = widget.position?.call();
        final at = now == null ? -1 : m.document.cueAt(now);
        final sel = m.selected;
        return PopScope(
          canPop: !m.dirty,
          onPopInvokedWithResult: (popped, _) async {
            if (popped) return;
            final nav = Navigator.of(context);
            if (await _confirmLeave()) nav.pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(m.name),
              actions: [
                IconButton(
                  tooltip: l.videoEditorUndo,
                  onPressed: m.canUndo ? m.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: l.videoEditorRedo,
                  onPressed: m.canRedo ? m.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                PopupMenuButton<SaveFormat>(
                  tooltip: l.videoEditorSaveAs,
                  icon: const Icon(Icons.save_outlined),
                  onSelected: (f) => unawaited(_save(f)),
                  itemBuilder: (context) => [
                    for (final f in SaveFormat.values)
                      PopupMenuItem(
                        value: f,
                        child: Text(l.videoEditorSaveFormat(f.name)),
                      ),
                  ],
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(KSpacing.s8),
                  child: Wrap(
                    spacing: KSpacing.s8,
                    runSpacing: KSpacing.s4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.swap_horiz_rounded),
                        label: Text(
                          sel.isEmpty
                              ? l.videoEditorShiftAll
                              : l.videoEditorShiftSelected(sel.length),
                        ),
                        onPressed: () async {
                          final d = await _askOffset();
                          if (d != null && d != Duration.zero) m.shift(d);
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.timeline_rounded),
                        label: Text(l.videoEditorResyncTitle),
                        onPressed: () => unawaited(_resync()),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.speed_rounded),
                        label: Text(l.videoSubSpeedTitle),
                        onPressed: () => unawaited(_frameRate()),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.translate_rounded),
                        label: Text(l.videoEditorFixEncoding),
                        onPressed: () => unawaited(_encoding()),
                      ),
                      if (now != null)
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded),
                          label: Text(l.videoEditorAddHere),
                          onPressed: () {
                            final i = m.addAt(now);
                            if (i >= 0) unawaited(_edit(i));
                          },
                        ),
                      if (now != null && at >= 0)
                        ActionChip(
                          avatar: const Icon(Icons.content_cut_rounded),
                          label: Text(l.videoEditorSplitHere),
                          onPressed: () => m.split(at, now),
                        ),
                      if (sel.length >= 2)
                        ActionChip(
                          avatar: const Icon(Icons.merge_rounded),
                          label: Text(l.videoEditorMerge),
                          onPressed: m.mergeSelected,
                        ),
                      if (sel.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.delete_outline_rounded),
                          label: Text(l.videoEditorDelete(sel.length)),
                          onPressed: m.deleteSelected,
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_fix_high_rounded),
                        label: Text(l.videoEditorFixOverlaps),
                        onPressed: m.fixOverlaps,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: m.cues.length,
                    itemBuilder: (context, i) {
                      final c = m.cues[i];
                      return ListTile(
                        selected: sel.contains(i) || i == at,
                        leading: Checkbox(
                          value: sel.contains(i),
                          semanticLabel: l.videoEditorSelectCue(i + 1),
                          onChanged: (_) => m.toggle(i),
                        ),
                        title: Text(
                          c.plainText.isEmpty
                              ? l.videoEditorEmptyCue
                              : c.plainText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          l.videoEditorTimeRange(_t(c.start), _t(c.end)),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        trailing: widget.seek == null
                            ? null
                            : IconButton(
                                tooltip: l.videoEditorPlayFrom,
                                icon: const Icon(Icons.play_arrow_rounded),
                                onPressed: () => widget.seek!(c.start),
                              ),
                        onTap: () => unawaited(_edit(i)),
                        onLongPress: () => m.toggle(i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
