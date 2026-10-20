import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/probe_queue.dart';
import 'package:mediahro/features/photos/photo_open.dart';
import 'package:mediahro/features/video/video_open.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Opens an indexed item with the lane that owns its kind: images in the
/// photo viewer (C3), everything else through the video handler (C1).
void openItemByKind(BuildContext context, ItemRow item) {
  if (item.kind == ItemKind.image) {
    openImageItem(context, item);
    return;
  }
  unawaited(openVideoItem(context, item));
}

/// Routes the probe queue's prober by item kind: images to the image
/// pipeline's prober (C3), audio and video to the engine's [fallback].
final class KindRoutingProber implements MediaProber {
  const KindRoutingProber({required this.images, this.fallback});

  final MediaProber images;
  final MediaProber? fallback;

  @override
  Future<ProbeResult> probe(VirtualFile file, ItemRow item) {
    if (item.kind == ItemKind.image) return images.probe(file, item);
    final other = fallback;
    if (other == null) return Future.value(const ProbeResult());
    return other.probe(file, item);
  }
}
