import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Plays a video or audio file from the vault (PRIV-007). The file is
/// decrypted chunk by chunk as the engine reads it and handed over as a
/// sensitive source (ADR-043): the engine refuses every path that would write
/// decoded content to disk, and this screen offers none of the features that
/// need one (no visualiser, no subtitle generation, no screenshots, no
/// picture-in-picture, no casting). It publishes no title to the system, so
/// no notification or lock screen names the file.
class VaultPlayerScreen extends ConsumerStatefulWidget {
  const VaultPlayerScreen({
    required this.container,
    required this.item,
    super.key,
  });

  final VaultContainer container;
  final VaultItem item;

  @override
  ConsumerState<VaultPlayerScreen> createState() => _VaultPlayerScreenState();
}

class _VaultPlayerScreenState extends ConsumerState<VaultPlayerScreen> {
  late final PlaybackEngine _engine = ref.read(
    playbackEngineProvider(EngineRole.video),
  );
  VaultFile? _file;
  StreamSubscription<PlaybackState>? _sub;
  PlaybackState _state = const PlaybackState();
  bool _started = false;
  bool _failed = false;
  bool _disposed = false;

  bool get _isVideo => widget.item.kind == 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final file = await widget.container.openFile(widget.item.id);
      if (_disposed) {
        await file.close();
        return;
      }
      _file = file;
      _sub = _engine.state.listen((s) {
        if (_disposed || !mounted) return;
        setState(() {
          _state = s;
          if (s.status == PlaybackStatus.error) _failed = true;
        });
      });
      await _engine.open(
        VirtualFileSource(file, sensitive: true),
        opts: const OpenOptions(),
      );
      if (_disposed) return;
      _started = true;
      await _engine.play();
      if (mounted) setState(() {});
    } on Object {
      if (mounted && !_disposed) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    if (_started || _file != null) unawaited(_engine.stop());
    unawaited(_file?.close());
    super.dispose();
  }

  bool get _playing => _state.status == PlaybackStatus.playing;

  Future<void> _toggle() async {
    if (!_started) return;
    if (_state.status == PlaybackStatus.ended) {
      await _engine.seek(Duration.zero);
      await _engine.play();
    } else if (_playing) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  Future<void> _skip(Duration by) async {
    if (!_started) return;
    final total = _state.duration;
    var to = _state.position + by;
    if (to < Duration.zero) to = Duration.zero;
    if (total != null && to > total) to = total;
    await _engine.seek(to, mode: SeekMode.exact);
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = _engine.textureId;
    final total = _state.duration;
    final totalMs = total?.inMilliseconds ?? 0;
    final at = _state.position.inMilliseconds.clamp(
      0,
      totalMs > 0 ? totalMs : 1,
    );
    final video = _state.video;
    Widget picture;
    if (_failed) {
      picture = Center(
        child: Text(
          l10n.photosVaultPlayerFailed,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    } else if (_isVideo && _started && id != null) {
      picture = Center(
        child: AspectRatio(
          aspectRatio: (video.width ?? 16) / (video.height ?? 9),
          child: Texture(textureId: id, filterQuality: FilterQuality.medium),
        ),
      );
    } else if (!_isVideo) {
      picture = const Center(
        child: ExcludeSemantics(
          child: Icon(Icons.audiotrack, size: 96, color: Colors.white54),
        ),
      );
    } else {
      picture = const Center(child: CircularProgressIndicator());
    }
    Widget button(String tip, IconData icon, VoidCallback onTap) => IconButton(
      tooltip: tip,
      color: Colors.white,
      iconSize: 32,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(icon),
      onPressed: _failed ? null : onTap,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.item.name, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: picture),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _clock(_state.position),
                        style: const TextStyle(color: Colors.white),
                      ),
                      Expanded(
                        child: Slider(
                          value: at.toDouble(),
                          max: totalMs > 0 ? totalMs.toDouble() : 1,
                          semanticFormatterCallback: (v) =>
                              l10n.photosVaultPlayerPosition(
                                _clock(Duration(milliseconds: v.round())),
                                _clock(total ?? Duration.zero),
                              ),
                          onChanged: totalMs > 0 && !_failed
                              ? (v) => unawaited(
                                  _engine.seek(
                                    Duration(milliseconds: v.round()),
                                    mode: SeekMode.exact,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Text(
                        _clock(total ?? Duration.zero),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      button(
                        l10n.photosVaultPlayerBack,
                        Icons.replay_10,
                        () => unawaited(_skip(const Duration(seconds: -10))),
                      ),
                      button(
                        _playing
                            ? l10n.photosVaultPlayerPause
                            : l10n.photosVaultPlayerPlay,
                        _playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        () => unawaited(_toggle()),
                      ),
                      button(
                        l10n.photosVaultPlayerForward,
                        Icons.forward_10,
                        () => unawaited(_skip(const Duration(seconds: 10))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
