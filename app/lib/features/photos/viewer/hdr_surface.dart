import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/photos/output/photo_output_service.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// A native HDR picture of one photo: the view type to embed and what to
/// pass it (IMG-002; ADR-022 for images).
class HdrHandle {
  HdrHandle({required this.viewType, required this.uri, this.onClose});

  final String viewType;
  final Uri uri;
  final Future<void> Function()? onClose;

  Future<void> close() async {
    await onClose?.call();
  }
}

/// Opens the platform HDR view for a photo; null where the display is SDR or
/// the platform has none. Faked in widget tests.
abstract interface class HdrOpener {
  /// Whether this display can show HDR stills at all.
  Future<bool> available();

  Future<HdrHandle?> open(PhotoEntry entry);
}

final class PlatformHdrOpener implements HdrOpener {
  PlatformHdrOpener({required this.imaging, required this.output});

  final ImagingFacade imaging;
  final PhotoOutput output;

  @override
  Future<bool> available() async => (await imaging.support()).hdrDisplay;

  @override
  Future<HdrHandle?> open(PhotoEntry entry) async {
    final uri = await output.readableUri(entry);
    final view = await imaging.openHdrView(uri);
    final type = view?.viewType;
    if (view == null || type == null) return null;
    return HdrHandle(viewType: type, uri: uri, onClose: view.close);
  }
}

final hdrOpenerProvider = Provider<HdrOpener>(
  (ref) => PlatformHdrOpener(
    imaging: ref.watch(imagingProvider),
    output: ref.watch(photoOutputProvider),
  ),
);

/// Whether the HDR toggle can be offered on this device.
final hdrDisplayProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(hdrOpenerProvider).available();
  } on Object {
    return false;
  }
});

/// The widget that embeds the platform view for [handle]; replaced in tests.
typedef HdrPlatformViewBuilder = Widget Function(
  BuildContext context,
  HdrHandle handle,
);

final hdrPlatformViewProvider = Provider<HdrPlatformViewBuilder>(
  (ref) =>
      (context, handle) => switch (defaultTargetPlatform) {
        TargetPlatform.android => AndroidView(
          viewType: handle.viewType,
          creationParams: {'uri': handle.uri.toString()},
          creationParamsCodec: const StandardMessageCodec(),
          // Touches stay with the viewer: swipe, pinch, tap.
          gestureRecognizers: const {},
        ),
        TargetPlatform.iOS => UiKitView(
          viewType: handle.viewType,
          creationParams: {'uri': handle.uri.toString()},
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: const {},
        ),
        _ => const SizedBox.shrink(),
      },
);

/// The HDR picture of [entry], drawn by the system over the viewer while the
/// photo is at fit size (IMG-002). Shows nothing if the view cannot be
/// opened; the tone-mapped picture underneath stays visible then.
class HdrImageSurface extends ConsumerStatefulWidget {
  const HdrImageSurface({required this.entry, super.key});

  final PhotoEntry entry;

  @override
  ConsumerState<HdrImageSurface> createState() => _HdrImageSurfaceState();
}

class _HdrImageSurfaceState extends ConsumerState<HdrImageSurface> {
  HdrHandle? _handle;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final h = await ref.read(hdrOpenerProvider).open(widget.entry);
      if (_disposed) {
        await h?.close();
        return;
      }
      if (mounted) setState(() => _handle = h);
    } on Object {
      // No HDR view: the SDR picture is shown.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_handle?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _handle;
    if (h == null) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black,
      child: ExcludeSemantics(
        child: ref.watch(hdrPlatformViewProvider)(context, h),
      ),
    );
  }
}
