import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Names a new album; null when cancelled.
Future<String?> askAlbumName(
  BuildContext context, {
  String? initial,
  bool rename = false,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: rename ? l10n.photosRename : l10n.photosNewAlbum,
      action: rename ? l10n.photosRename : l10n.photosCreate,
      initial: initial,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, this.initial});

  final String title;
  final String action;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.photosAlbumName),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(context).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: _c.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_c.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Picks one of the manual albums, or creates one. Null when cancelled.
Future<int?> chooseAlbum(
  BuildContext context,
  WidgetRef ref, {
  Iterable<int> thenAdd = const [],
}) async {
  final org = ref.read(photoOrganiserProvider);
  final albums = [
    for (final a in await org.albums())
      if (!a.smart) a,
  ];
  if (!context.mounted) return null;
  final l10n = AppLocalizations.of(context);
  final choice = await showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.photosChooseAlbum),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop('new'),
          child: Row(
            children: [
              const Icon(Icons.add),
              const SizedBox(width: KSpacing.s12),
              Text(l10n.photosNewAlbum),
            ],
          ),
        ),
        for (final a in albums)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(a.id),
            child: Row(
              children: [
                const Icon(Icons.photo_album_outlined),
                const SizedBox(width: KSpacing.s12),
                Expanded(child: Text(a.name)),
                Text(l10n.photosAlbumCount(a.count)),
              ],
            ),
          ),
      ],
    ),
  );
  if (choice is int) return choice;
  if (choice != 'new' || !context.mounted) return null;
  final name = await askAlbumName(context);
  if (name == null) return null;
  return await org.createAlbum(name);
}

/// Adds [ids] to an album the user picks and says how many were new.
Future<bool> addToAlbumFlow(
  BuildContext context,
  WidgetRef ref,
  Set<int> ids,
) async {
  final albumId = await chooseAlbum(context, ref);
  if (albumId == null || !context.mounted) return false;
  final added = await ref.read(photoOrganiserProvider).addToAlbum(albumId, ids);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).photosAddedToAlbum(added)),
      ),
    );
  }
  return true;
}

/// Rating dialog: 1–5 stars or none. Null when cancelled.
Future<int?> askRating(BuildContext context, {int current = 0}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.photosRate),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: l10n.photosRatingStars(i),
              icon: Icon(
                i <= current ? Icons.star : Icons.star_border,
                color: i <= current ? Colors.amber : null,
              ),
              onPressed: () => Navigator.of(ctx).pop(i),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(0),
          child: Text(l10n.photosRemoveRating),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.photosCancel),
        ),
      ],
    ),
  );
}

/// Colour of a label, for the dots in the dialog.
Color labelColour(LabelColor c) => switch (c) {
  LabelColor.red => Colors.red,
  LabelColor.orange => Colors.orange,
  LabelColor.yellow => Colors.yellow.shade700,
  LabelColor.green => Colors.green,
  LabelColor.blue => Colors.blue,
  LabelColor.purple => Colors.purple,
  LabelColor.grey => Colors.grey,
};

/// Label dialog. The result is the chosen colour, [clearLabel] for "none",
/// or null when cancelled.
Future<Object?> askLabel(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.photosLabelAction),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(clearLabel),
          child: Text(l10n.photosNoLabel),
        ),
        for (final c in LabelColor.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(c),
            child: Row(
              children: [
                Icon(Icons.circle, color: labelColour(c)),
                const SizedBox(width: KSpacing.s12),
                Text(l10n.photosLabelName(c.name)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Marker result of [askLabel] meaning "remove the label".
const Object clearLabel = 'none';

/// Tag editor for the selection: tags on all of it can be removed, any tag
/// can be added.
Future<void> editTagsFlow(
  BuildContext context,
  WidgetRef ref,
  Set<int> ids,
) async {
  final org = ref.read(photoOrganiserProvider);
  final common = await org.commonTags(ids);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _TagsDialog(org: org, ids: ids, initial: common),
  );
}

class _TagsDialog extends StatefulWidget {
  const _TagsDialog({
    required this.org,
    required this.ids,
    required this.initial,
  });

  final PhotoOrganiser org;
  final Set<int> ids;
  final Set<String> initial;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late final Set<String> _tags = {...widget.initial};
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    await widget.org.addTag(widget.ids, t);
    if (!mounted) return;
    setState(() {
      _tags.add(t);
      _c.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosTagsTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tags.isEmpty)
            Text(l10n.photosTagsNone)
          else ...[
            Text(
              l10n.photosTagsApplied,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: KSpacing.s8),
            Wrap(
              spacing: KSpacing.s8,
              children: [
                for (final t in _tags.toList()..sort())
                  InputChip(
                    label: Text(t),
                    onDeleted: () async {
                      await widget.org.removeTag(widget.ids, t);
                      if (mounted) setState(() => _tags.remove(t));
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: KSpacing.s12),
          TextField(
            controller: _c,
            decoration: InputDecoration(
              labelText: l10n.photosAddTag,
              hintText: l10n.photosTagHint,
              suffixIcon: IconButton(
                tooltip: l10n.photosAddTag,
                icon: const Icon(Icons.add),
                onPressed: () => unawaited(_add()),
              ),
            ),
            onSubmitted: (_) => unawaited(_add()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.photosEditSave),
        ),
      ],
    );
  }
}
