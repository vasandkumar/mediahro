import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/edit/editor_screen.dart';
import 'package:mediahro/features/photos/edit/photo_editor_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';

/// Puts the copied look (light, colour, detail, curves) on the selected
/// photos (IMG-009 batch apply): as new copies, or over the originals after a
/// warning. Returns true when something was saved.
Future<bool> applyCopiedLookFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> chosen,
) async {
  final look = ref.read(copiedLookProvider);
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final photos = chosen.where((e) => !e.isVideo).toList();
  if (look == null || photos.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosLocationNoPhotos)),
    );
    return false;
  }
  final editor = ref.read(photoEditorProvider);
  final canReplace = photos.any(editor.canReplace);
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.photosApplyLookTitle),
      content: Text(l10n.photosApplyLookBody(photos.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.photosCancel),
        ),
        if (canReplace)
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosApplyLookReplace),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.photosApplyLookCopies),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  final done = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
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
                  Text(l10n.photosBatchProgress(n, photos.length)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: n / photos.length),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final BatchOutcome result;
  try {
    result = await applyLookToPhotos(
      editor,
      photos,
      look,
      replace: choice,
      onProgress: (n) => done.value = n,
    );
  } finally {
    navigator.pop();
    done.dispose();
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        [
          if (result.saved > 0) l10n.photosApplyLookDone(result.saved),
          if (result.failed > 0) l10n.photosLocationFailed(result.failed),
        ].join(' '),
      ),
    ),
  );
  return result.saved > 0;
}
