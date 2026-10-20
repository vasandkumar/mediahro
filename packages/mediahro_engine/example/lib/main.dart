import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Engine test bed: plays one file through the platform render bridge.
///
/// `flutter run --dart-define=MEDIAHRO_FILE=<path>` on a desktop; the
/// integration tests drive [EnginePlayer] directly.
void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: EnginePlayer(file: String.fromEnvironment('MEDIAHRO_FILE')),
      ),
    ),
  );
}

/// Shows [engine]'s video texture, or creates an engine and opens [file].
class EnginePlayer extends StatefulWidget {
  const EnginePlayer({required this.file, super.key, this.engine});

  final String file;
  final MpvEngine? engine;

  @override
  State<EnginePlayer> createState() => _EnginePlayerState();
}

class _EnginePlayerState extends State<EnginePlayer> {
  late final MpvEngine _engine =
      widget.engine ??
      MpvEngine(
        EngineRole.video,
        config: MpvEngineConfig(renderBridge: RenderBridge()),
      );
  StreamSubscription<PlaybackState>? _sub;
  int? _texture;

  @override
  void initState() {
    super.initState();
    _sub = _engine.state.listen((_) {
      if (_engine.textureId != _texture && mounted) {
        setState(() => _texture = _engine.textureId);
      }
    });
    if (widget.file.isNotEmpty && File(widget.file).existsSync()) {
      unawaited(_engine.open(UriSource(Uri.file(widget.file))));
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    if (widget.engine == null) unawaited(_engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _texture;
    final v = _engine.current.video;
    final aspect = (v.width ?? 16) / (v.height ?? 9);
    return Center(
      child: id == null
          ? const SizedBox.shrink()
          : AspectRatio(
              aspectRatio: aspect,
              child: Texture(textureId: id),
            ),
    );
  }
}
