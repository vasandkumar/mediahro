import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The picture of one timeline tile: the cached thumbnail, a neutral
/// placeholder while it is generated, a broken-image mark if it cannot be.
/// Asks its [controller] when built and releases the request when it is
/// scrolled away (IMG-003).
class PhotoThumbnail extends StatefulWidget {
  const PhotoThumbnail({
    required this.entry,
    required this.index,
    required this.controller,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    super.key,
  });

  final PhotoEntry entry;

  /// Position in the timeline, for scheduling priority.
  final int index;
  final ThumbnailController controller;

  /// Decode width in physical pixels.
  final int? cacheWidth;
  final BoxFit fit;

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  File? _file;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PhotoThumbnail old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id ||
        old.controller != widget.controller) {
      old.controller.release(old.entry.id);
      _file = null;
      _failed = false;
      _start();
    }
  }

  void _start() {
    final c = widget.controller;
    final id = widget.entry.id;
    final known = c.resolved(id);
    if (known != null) {
      _file = known;
      return;
    }
    unawaited(
      c.request(widget.entry, widget.index).then((f) {
        if (!mounted || widget.entry.id != id) return;
        setState(() {
          _file = f;
          _failed = f == null && c.failed(id);
        });
      }),
    );
  }

  @override
  void dispose() {
    widget.controller.release(widget.entry.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = _file;
    if (file == null) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: _failed || widget.entry.isVideo
            ? Center(
                child: Icon(
                  widget.entry.isVideo
                      ? Icons.movie_outlined
                      : Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : null,
      );
    }
    final reduceMotion = KAccessibility.reduceMotion(context);
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) {
        if (sync || reduceMotion) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: KMotion.fast,
          child: child,
        );
      },
      errorBuilder: (context, error, stack) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
