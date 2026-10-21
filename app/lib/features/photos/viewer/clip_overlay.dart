import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_clips.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Plays the clip of a Live Photo or Motion Photo over the picture
/// (IMG-001), once, with sound at the player's volume, and calls [onDone]
/// when it ends, fails or cannot be found. Touches go through to the photo.
class ClipOverlay extends ConsumerStatefulWidget {
  const ClipOverlay({required this.entry, required this.onDone, super.key});

  final PhotoEntry entry;
  final VoidCallback onDone;

  @override
  ConsumerState<ClipOverlay> createState() => _ClipOverlayState();
}

class _ClipOverlayState extends ConsumerState<ClipOverlay> {
  late final PlaybackEngine _engine = ref.read(
    playbackEngineProvider(EngineRole.video),
  );
  PhotoClip? _clip;
  StreamSubscription<PlaybackState>? _sub;
  bool _started = false;
  bool _done = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (!_disposed) widget.onDone();
  }

  Future<void> _start() async {
    final clip = await ref.read(photoClipsProvider).open(widget.entry);
    if (_disposed) {
      await clip?.file.close();
      return;
    }
    if (clip == null) {
      _finish();
      return;
    }
    _clip = clip;
    _sub = _engine.state.listen((s) {
      if (!_started) return;
      if (!_disposed && mounted) setState(() {});
      if (s.status == PlaybackStatus.ended ||
          s.status == PlaybackStatus.error) {
        _finish();
      }
    });
    try {
      await _engine.open(
        VirtualFileSource(clip.file, title: widget.entry.name),
        opts: const OpenOptions(),
      );
      _started = true;
      if (!_disposed) setState(() {});
      // A clip that was over before the first state arrived.
      final s = _engine.current;
      if (s.status == PlaybackStatus.ended ||
          s.status == PlaybackStatus.error) {
        _finish();
      }
    } on Object {
      _finish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    final clip = _clip;
    if (_started || clip != null) {
      unawaited(_engine.stop());
    }
    if (clip != null) unawaited(clip.file.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _engine.textureId;
    if (!_started || id == null) return const SizedBox.shrink();
    final video = _engine.current.video;
    final w = (video.width ?? 16).toDouble();
    final h = (video.height ?? 9).toDouble();
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black,
        child: FittedBox(
          child: SizedBox(
            width: w,
            height: h,
            child: Texture(textureId: id, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }
}
