import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show VirtualFileException;

/// One page of the viewer: the cached thumbnail at once, then the real
/// picture as soon as it is decoded, with zoom and pan.
class PhotoPage extends ConsumerStatefulWidget {
  const PhotoPage({
    required this.entry,
    required this.index,
    required this.thumbs,
    required this.active,
    required this.mode,
    required this.quarterTurns,
    required this.onAtFitChanged,
    required this.onTap,
    this.controller,
    this.onZoomChanged,
    this.onLoaded,
    this.onPlayVideo,
    super.key,
  });

  final PhotoEntry entry;
  final int index;
  final ThumbnailController thumbs;

  /// The page the user is looking at: only it reports zoom and holds the
  /// controller.
  final bool active;
  final FitMode mode;
  final int quarterTurns;
  final ValueChanged<bool> onAtFitChanged;
  final VoidCallback onTap;
  final ViewerController? controller;
  final void Function(ZoomState zoom, int percent)? onZoomChanged;

  /// The image finished loading (the chrome shows what it learned).
  final ValueChanged<ViewerImage>? onLoaded;
  final VoidCallback? onPlayVideo;

  @override
  ConsumerState<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends ConsumerState<PhotoPage> {
  ViewerImage? _image;
  Object? _error;
  ImageSource? _source;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.entry.isVideo) unawaited(_load());
  }

  @override
  void didUpdateWidget(PhotoPage old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id && !widget.entry.isVideo) {
      _release();
      unawaited(_load());
    }
  }

  void _release() {
    _generation++;
    _image?.dispose();
    _image = null;
    _error = null;
    final s = _source;
    _source = null;
    if (s != null) unawaited(s.file.close());
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _error = null;
    });
    try {
      final src = await ref.read(photoFilesProvider).open(widget.entry);
      if (!mounted || gen != _generation) {
        unawaited(src.file.close());
        return;
      }
      _source = src;
      final image = await loadViewerImage(ref.read(imagePipelineProvider), src);
      if (!mounted || gen != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
      widget.onLoaded?.call(image);
    } on Object catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final image = _image;
    if (image != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ViewerSurface(
            key: ValueKey(widget.entry.id),
            base: image.base,
            fullSize: image.fullSize,
            tileLoader: image.tileLoader,
            mode: widget.mode,
            quarterTurns: widget.quarterTurns,
            controller: widget.active ? widget.controller : null,
            onZoomChanged: widget.active ? widget.onZoomChanged : null,
            onAtFitChanged: widget.active ? widget.onAtFitChanged : (_) {},
            onTap: widget.onTap,
          ),
          if (image.previewOnly)
            PositionedDirectional(
              top: 72,
              start: KSpacing.s16,
              child: _Pill(l10n.photosPreviewOnly),
            ),
        ],
      );
    }
    if (_error != null) {
      return KErrorState(
        message: _error is VirtualFileException
            ? l10n.photosLoadFailedSource
            : l10n.photosLoadFailedMessage,
        action: KButton(label: l10n.photosRetry, onPressed: _load),
      );
    }
    // Loading, or a video: the thumbnail fills in while the picture decodes.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.entry.isVideo ? widget.onPlayVideo : widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoThumbnail(
            entry: widget.entry,
            index: widget.index,
            controller: widget.thumbs,
            fit: BoxFit.contain,
          ),
          if (widget.entry.isVideo)
            const Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 72,
                color: Colors.white,
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 96),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(KRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.s12,
        vertical: KSpacing.s4,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: Colors.white),
      ),
    ),
  );
}
