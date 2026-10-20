import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/output/photo_output_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/photos_settings.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/settings/settings_providers.dart'
    show settingsStoreProvider;
import 'package:mediahro/platform/imaging.dart';

/// What the output menu can do to the photos in front of the user.
enum OutputAction { share, wallpaper, print, copy }

/// The items of the output menu for [support]: share and copy always, the
/// rest where the OS offers them.
List<OutputAction> outputActionsFor(
  ImagingSupport support, {
  bool single = true,
}) => [
  OutputAction.share,
  if (single && support.wallpaperTargets.isNotEmpty) OutputAction.wallpaper,
  if (support.print) OutputAction.print,
  if (single) OutputAction.copy,
];

String outputActionLabel(AppLocalizations l10n, OutputAction a) => switch (a) {
  OutputAction.share => l10n.photosShare,
  OutputAction.wallpaper => l10n.photosWallpaper,
  OutputAction.print => l10n.photosPrint,
  OutputAction.copy => l10n.photosCopyImage,
};

/// Runs [action] on [photos] (one photo for wallpaper and copy).
Future<void> runOutputAction(
  BuildContext context,
  WidgetRef ref,
  OutputAction action,
  List<PhotoEntry> photos,
) async {
  switch (action) {
    case OutputAction.share:
      await showShareSheet(context, ref, photos);
    case OutputAction.wallpaper:
      await setWallpaperFlow(context, ref, photos.first);
    case OutputAction.print:
      await printFlow(context, ref, photos);
    case OutputAction.copy:
      await copyFlow(context, ref, photos.first);
  }
}

Future<T?> _busy<T>(
  BuildContext context,
  String text,
  Future<T> Function() task,
) async {
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

/// The share sheet: size and metadata options, then the system share sheet
/// (IMG-015; Nearby Share / Quick Share / AirDrop come with it).
Future<void> showShareSheet(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
) async {
  final startStrip = ref
      .read(settingsStoreProvider)
      .get(PhotoSettings.stripOnShare);
  final options = await showModalBottomSheet<ShareOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        ShareSheet(count: photos.length, stripByDefault: startStrip),
  );
  if (options == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await _busy(
      context,
      l10n.photosSharePreparing,
      () => ref.read(photoOutputProvider).share(photos, options),
    );
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosShareFailed)));
  }
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({
    required this.count,
    required this.stripByDefault,
    super.key,
  });

  final int count;
  final bool stripByDefault;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  static const _edges = <int?>[null, 2048, 1280, 640];
  int? _edge;
  late bool _strip = widget.stripByDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.photosShareTitle(widget.count),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.photosShareSize,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _edges)
                  ChoiceChip(
                    label: Text(
                      e == null
                          ? l10n.photosShareSizeOriginal
                          : l10n.photosBatchSizeEdge(e),
                    ),
                    selected: _edge == e,
                    onSelected: (_) => setState(() => _edge = e),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _strip,
              title: Text(l10n.photosShareStrip),
              subtitle: Text(l10n.photosShareStripHint),
              onChanged: (v) => setState(() => _strip = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: Text(l10n.photosShare),
                onPressed: () => Navigator.pop(
                  context,
                  ShareOptions(maxEdge: _edge, stripMetadata: _strip),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home, lock or both, whichever the OS allows, then sets it.
Future<void> setWallpaperFlow(
  BuildContext context,
  WidgetRef ref,
  PhotoEntry photo,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final support = await ref.read(photoOutputSupportProvider.future);
  final targets = [
    for (final t in const [
      WallpaperTarget.home,
      WallpaperTarget.lock,
      WallpaperTarget.both,
      WallpaperTarget.desktop,
    ])
      if (support.wallpaperTargets.contains(t)) t,
  ];
  if (targets.isEmpty || !context.mounted) return;
  String label(WallpaperTarget t) => switch (t) {
    WallpaperTarget.home => l10n.photosWallpaperHome,
    WallpaperTarget.lock => l10n.photosWallpaperLock,
    WallpaperTarget.both => l10n.photosWallpaperBoth,
    WallpaperTarget.desktop => l10n.photosWallpaper,
  };
  final target = targets.length == 1
      ? targets.single
      : await showModalBottomSheet<WallpaperTarget>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in targets)
                  ListTile(
                    title: Text(label(t)),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
              ],
            ),
          ),
        );
  if (target == null || !context.mounted) return;
  try {
    await _busy(
      context,
      l10n.photosSharePreparing,
      () => ref.read(photoOutputProvider).setWallpaper(photo, target),
    );
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosWallpaperSet)));
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosWallpaperFailed)),
    );
  }
}

/// Asks for the layout and opens the system print dialog.
Future<void> printFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
) async {
  final layout = await showDialog<PrintLayout>(
    context: context,
    builder: (_) => const _PrintDialog(),
  );
  if (layout == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await _busy(
      context,
      l10n.photosSharePreparing,
      () => ref.read(photoOutputProvider).print(photos, layout),
    );
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosPrintFailed)));
  }
}

class _PrintDialog extends StatefulWidget {
  const _PrintDialog();

  @override
  State<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends State<_PrintDialog> {
  int _per = 1;
  bool _fill = false;
  bool _captions = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosPrintTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [1, 2, 4, 6])
                ChoiceChip(
                  label: Text(l10n.photosPrintPerPage(n)),
                  selected: _per == n,
                  onSelected: (_) => setState(() => _per = n),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _fill,
            title: Text(l10n.photosPrintFill),
            onChanged: (v) => setState(() => _fill = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _captions,
            title: Text(l10n.photosPrintCaptions),
            onChanged: (v) => setState(() => _captions = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PrintLayout(perPage: _per, fill: _fill, captions: _captions),
          ),
          child: Text(l10n.photosPrint),
        ),
      ],
    );
  }
}

Future<void> copyFlow(
  BuildContext context,
  WidgetRef ref,
  PhotoEntry photo,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(photoOutputProvider).copy(photo);
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosImageCopied)));
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosCopyFailed)));
  }
}
