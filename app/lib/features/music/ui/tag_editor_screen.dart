import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/id3.dart' show normaliseMime;
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

Future<void> openTagEditor(BuildContext context, List<MusicTrack> tracks) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => TagEditorScreen(tracks: tracks)),
    );

enum _Cover { keep, replace, remove }

/// Single and batch tag editing (MUS-003). In a batch, fields that differ
/// between songs start empty and are kept unless typed into.
class TagEditorScreen extends ConsumerStatefulWidget {
  const TagEditorScreen({required this.tracks, super.key});

  final List<MusicTrack> tracks;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  final _controllers = <String, TextEditingController>{};
  final _initial = <String, String>{};
  final _mixed = <String>{};
  List<AudioTags>? _tags;
  _Cover _cover = _Cover.keep;
  EmbeddedPicture? _newCover;
  int? _progressDone;

  bool get _batch => widget.tracks.length > 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final files = ref.read(musicFilesProvider);
    final tags = <AudioTags>[];
    for (final t in widget.tracks) {
      try {
        final f = await files.open(t.sourceId, t.relPath);
        try {
          tags.add(await readTagsOf(f));
        } finally {
          await f.close();
        }
      } on Exception {
        tags.add(AudioTags.empty);
      }
    }
    for (final k in TagField.editable) {
      final values = {for (final t in tags) t.values(k).join('; ')};
      final v = values.length == 1 ? values.single : '';
      if (values.length > 1) _mixed.add(k);
      _initial[k] = v;
      _controllers[k] = TextEditingController(text: v);
    }
    if (mounted) setState(() => _tags = tags);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TagEdit _editFor(AudioTags before) {
    final fields = <String, List<String>>{};
    for (final k in TagField.editable) {
      final text = _controllers[k]!.text;
      if (text == _initial[k]) continue;
      if (_mixed.contains(k) && text.isEmpty) continue;
      final multi =
          k == TagField.artist ||
          k == TagField.albumArtist ||
          k == TagField.genre ||
          k == TagField.composer;
      fields[k] = multi
          ? [
              for (final v in text.split(';'))
                if (v.trim().isNotEmpty) v.trim(),
            ]
          : [if (text.trim().isNotEmpty) text.trim()];
    }
    return TagEdit(
      fields: fields,
      pictures: switch (_cover) {
        _Cover.keep => null,
        _Cover.remove => const [],
        _Cover.replace => [
          _newCover!,
          for (final p in before.pictures)
            if (p.type != PictureType.frontCover) p,
        ],
      },
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() => _progressDone = 0);
    final res = await ref
        .read(tagEditorProvider)
        .apply(
          widget.tracks,
          (_, before) => _editFor(before),
          progress: (done, _) {
            if (mounted) setState(() => _progressDone = done);
          },
        );
    final reasons = res.failed.values.toSet();
    messenger?.showSnackBar(
      SnackBar(
        content: res.failed.isEmpty
            ? Text(l10n.musicTagSaved(res.changed))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.musicTagFailed(res.failed.length)),
                  Text(l10n.musicTagFailure(reasons.first.name)),
                ],
              ),
      ),
    );
    nav.pop();
  }

  Future<void> _pickCover() async {
    final storage = ref.read(storageProvider);
    final picked = await storage.pickFiles(kinds: const {PickKind.image});
    if (picked.isEmpty) return;
    final bytes = await readPickedFile(
      storage,
      picked.first.uri,
      maxBytes: 16 << 20,
    );
    setState(() {
      _cover = _Cover.replace;
      _newCover = EmbeddedPicture(
        type: PictureType.frontCover,
        mimeType: normaliseMime('', bytes),
        bytes: bytes,
      );
    });
  }

  Future<void> _fromFileName() async {
    final l10n = AppLocalizations.of(context);
    final pattern = await _askPattern(
      l10n.musicTagFromFileName,
      '%track% - %artist% - %title%',
      preview: (p) {
        final t = widget.tracks.first;
        final stem = _stem(t.relPath);
        final got = tagsFromName(p, stem);
        return got == null
            ? l10n.musicTagNoMatch(stem)
            : got.entries
                  .map((e) => '${l10n.musicTagField(e.key)}: ${e.value.join()}')
                  .join(' · ');
      },
    );
    if (pattern == null || !mounted) return;
    // Per-file values: applied directly as a batch.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() => _progressDone = 0);
    final res = await ref
        .read(tagEditorProvider)
        .apply(
          widget.tracks,
          (t, _) => TagEdit(
            fields: tagsFromName(pattern, _stem(t.relPath)) ?? const {},
          ),
          progress: (done, _) {
            if (mounted) setState(() => _progressDone = done);
          },
        );
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.musicTagSaved(res.changed))),
    );
    nav.pop();
  }

  Future<void> _renameFiles() async {
    final l10n = AppLocalizations.of(context);
    final tags = _tags!;
    final pattern = await _askPattern(
      l10n.musicTagRenameFiles,
      '%track% - %title%',
      preview: (p) {
        final t = widget.tracks.first;
        final n = nameFromTags(p, tags.first);
        return n == null
            ? l10n.musicTagNoMatch(_name(t.relPath))
            : l10n.musicTagPreview(_name(t.relPath), '$n.${_ext(t.relPath)}');
      },
    );
    if (pattern == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final ops = ref.read(fileOperationsProvider);
    final files = ref.read(musicFilesProvider);
    var renamed = 0;
    for (final (i, t) in widget.tracks.indexed) {
      final n = nameFromTags(pattern, tags[i]);
      if (n == null) continue;
      final newName = '$n.${_ext(t.relPath)}';
      if (newName == _name(t.relPath)) continue;
      try {
        await ops.rename(await files.uriOf(t.sourceId, t.relPath), newName);
        renamed++;
      } on Exception {
        // Name clash or read-only: leave this one.
      }
    }
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.musicTagRenamed(renamed))),
    );
    nav.pop();
  }

  Future<String?> _askPattern(
    String title,
    String initial, {
    required String Function(String pattern) preview,
  }) async {
    final l10n = AppLocalizations.of(context);
    final c = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                decoration: InputDecoration(labelText: l10n.musicTagPattern),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: KSpacing.s8),
              Text(l10n.musicTagPatternHelp),
              const SizedBox(height: KSpacing.s8),
              Text(
                preview(c.text),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: Text(l10n.musicCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(c.text),
              child: Text(l10n.musicTagApply),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return result == null || result.trim().isEmpty ? null : result;
  }

  static String _name(String rel) => rel.split('/').last;
  static String _ext(String rel) {
    final n = _name(rel);
    final dot = n.lastIndexOf('.');
    return dot < 0 ? '' : n.substring(dot + 1);
  }

  static String _stem(String rel) {
    final n = _name(rel);
    final dot = n.lastIndexOf('.');
    return dot < 0 ? n : n.substring(0, dot);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = _tags;
    final done = _progressDone;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _batch
              ? l10n.musicEditTagsCount(widget.tracks.length)
              : l10n.musicEditTags,
        ),
        actions: [
          TextButton(
            onPressed: tags == null || done != null
                ? null
                : () => unawaited(_save()),
            child: Text(l10n.musicSave),
          ),
        ],
      ),
      body: tags == null
          ? Center(child: Text(l10n.musicTagLoading))
          : done != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: KSpacing.s16),
                  Text(l10n.musicTagSaving(done, widget.tracks.length)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(KSpacing.s16),
              children: [
                Row(
                  children: [
                    if (!_batch && _cover != _Cover.remove && _newCover == null)
                      CoverArt(itemId: widget.tracks.first.itemId, size: 88)
                    else if (!_batch && _cover != _Cover.remove)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _newCover!.bytes,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(width: KSpacing.s16),
                    Expanded(
                      child: Wrap(
                        spacing: KSpacing.s8,
                        runSpacing: KSpacing.s8,
                        children: [
                          OutlinedButton(
                            onPressed: () => unawaited(_pickCover()),
                            child: Text(l10n.musicTagReplaceCover),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _cover = _cover == _Cover.remove
                                  ? _Cover.keep
                                  : _Cover.remove;
                              _newCover = null;
                            }),
                            child: Text(
                              _cover == _Cover.remove
                                  ? l10n.musicTagKeepCover
                                  : l10n.musicTagRemoveCover,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.s16),
                Wrap(
                  spacing: KSpacing.s8,
                  children: [
                    ActionChip(
                      label: Text(l10n.musicTagFromFileName),
                      onPressed: () => unawaited(_fromFileName()),
                    ),
                    ActionChip(
                      label: Text(l10n.musicTagRenameFiles),
                      onPressed: () => unawaited(_renameFiles()),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.s16),
                for (final k in TagField.editable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KSpacing.s12),
                    child: TextField(
                      controller: _controllers[k],
                      minLines: k == TagField.lyrics || k == TagField.comment
                          ? 2
                          : 1,
                      maxLines: k == TagField.lyrics
                          ? 8
                          : k == TagField.comment
                          ? 4
                          : 1,
                      keyboardType:
                          const {
                            TagField.trackNumber,
                            TagField.trackTotal,
                            TagField.discNumber,
                            TagField.discTotal,
                            TagField.bpm,
                          }.contains(k)
                          ? TextInputType.number
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: l10n.musicTagField(k),
                        hintText: _mixed.contains(k)
                            ? l10n.musicTagMultipleValues
                            : null,
                        helperText:
                            const {
                              TagField.artist,
                              TagField.albumArtist,
                              TagField.genre,
                              TagField.composer,
                            }.contains(k)
                            ? l10n.musicTagMultiValueHint
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
