import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/photos/vault/screen_awake.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
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

class _VaultPlayerScreenState extends ConsumerState<VaultPlayerScreen>
    with WidgetsBindingObserver {
  late final PlaybackEngine _engine = ref.read(
    playbackEngineProvider(EngineRole.video),
  );
  late final PlaybackEngine _music = ref.read(
    playbackEngineProvider(EngineRole.music),
  );
  late final ScreenAwake _awake;
  ScreenHold? _hold;
  VaultFile? _file;
  StreamSubscription<PlaybackState>? _sub;
  ProviderSubscription<VaultState>? _lock;
  PlaybackState _state = const PlaybackState();
  bool _started = false;
  bool _failed = false;
  bool _disposed = false;

  /// Playback was ended on purpose (the app left the screen, the vault
  /// locked, the screen was left); nothing may start it again.
  bool _ended = false;
  Future<void>? _closing;

  bool get _isVideo => widget.item.kind == 'video';

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    WidgetsBinding.instance.addObserver(this);
    // Locking the vault ends playback at once, whether or not this screen
    // is taken off the stack yet.
    _lock = ref.listenManual<VaultState>(vaultSessionProvider, (_, next) {
      if (!next.isOpen) unawaited(_end());
    });
    unawaited(_start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A paused app keeps the engine (and up to 32 MiB it has already
    // decrypted) running: stop and let go of the file now, before the
    // framework gets round to anything else.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_end());
    }
  }

  /// Stops the engine, then closes the file, once; later calls wait for the
  /// first.
  Future<void> _end() => _closing ??= _endNow();

  Future<void> _endNow() async {
    _ended = true;
    // The screen may sleep again at once; the rest takes the time it takes.
    _hold?.release();
    final hadFile = _file;
    _file = null;
    try {
      // The stop is asked for before anything is awaited.
      final stop = _started || hadFile != null ? _engine.stop() : null;
      await stop;
    } on Object {
      // Already stopped.
    }
    try {
      await hadFile?.close();
    } on Object {
      // Closed with the engine.
    }
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _start() async {
    try {
      final file = await widget.container.openFile(widget.item.id);
      if (_disposed || _ended) {
        await file.close();
        return;
      }
      _file = file;
      _hold = _awake.hold();
      // Music does not play under a private video.
      if (_music.current.status == PlaybackStatus.playing) {
        await _music.pause();
      }
      // Left or locked while that was going on: the file is closed already,
      // and the hold was taken after the end gave its own back.
      if (_disposed || _ended) {
        _hold?.release();
        return;
      }
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
      if (_disposed || _ended) {
        // Left or locked while it was opening: stop what has just started.
        await _engine.stop();
        return;
      }
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
    WidgetsBinding.instance.removeObserver(this);
    _lock?.close();
    unawaited(_sub?.cancel());
    // Stop first, then close the file: the engine reads from it.
    unawaited(_end());
    super.dispose();
  }

  bool get _playing => _state.status == PlaybackStatus.playing;

  Future<void> _toggle() async {
    if (!_started || _ended) return;
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
    if (!_started || _ended) return;
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
