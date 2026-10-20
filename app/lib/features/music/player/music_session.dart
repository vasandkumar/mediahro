import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro/features/music/library/artwork_store.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Connects the music player to the OS media session (SYS-001/002 through
/// C4's [MediaSessionFacade]): lock screen, notification, headset and car
/// buttons control the player, and the session shows what plays. Optional
/// [HomeWidgetsFacade] gets the same updates (MUS-012).
final class MusicSessionBridge {
  MusicSessionBridge({
    required this.player,
    required this.session,
    required this.art,
    this.widgets,
    this.otherPlayer,
  });

  final MusicPlayer player;
  final MediaSessionFacade session;
  final ArtworkStore art;
  final HomeWidgetsFacade? widgets;

  /// State of the other player sharing the OS session (the video engine).
  /// When it starts playing it takes the session over: music stops
  /// answering lock-screen commands until music plays again.
  final Stream<PlaybackState>? otherPlayer;

  StreamSubscription<MusicPlayerState>? _states;
  StreamSubscription<RemoteCommand>? _commands;
  StreamSubscription<PlaybackState>? _other;
  bool _active = false;
  String? _shownItem;
  NowPlaying? _shownNowPlaying;
  bool? _widgetPlaying;
  SessionPlaybackState? _shownState;
  bool? _shownNext;
  Duration _shownPosition = Duration.zero;

  /// Whether music owns the OS media session right now.
  bool get owns => _active;

  void start() {
    _commands ??= session.commands.listen(_onCommand);
    _other ??= otherPlayer?.listen((s) {
      if (s.status != PlaybackStatus.playing) return;
      // A film started: it takes the session (and the speakers) over.
      if (player.state.playing) unawaited(player.pause());
      if (_active) {
        _active = false;
        _shownItem = null;
        _shownState = null;
        _shownNext = null;
      }
    });
    _states ??= player.states.listen((s) => unawaited(_onState(s)));
  }

  Future<void> dispose() async {
    await _states?.cancel();
    await _commands?.cancel();
    await _other?.cancel();
    if (_active) await session.deactivate();
  }

  Future<void> _onCommand(RemoteCommand c) async {
    // One session, two players: act only while music owns it.
    if (!_active) return;
    switch (c) {
      case PlayCommand():
        await player.play();
      case PauseCommand():
        await player.pause();
      case TogglePlayPauseCommand():
        await player.togglePlayPause();
      case NextCommand():
        await player.next();
      case PreviousCommand():
        await player.previous();
      case StopCommand():
        await player.stop();
      case SeekToCommand(:final position):
        await player.seek(position);
      case SkipByCommand(:final offset):
        await player.seek(player.state.position + offset);
      case SetRateCommand():
        break; // Music plays at 1×; podcasts handle rate (POD-001).
    }
  }

  Future<void> _onState(MusicPlayerState s) async {
    final track = s.current;
    final station = s.station;
    if (track == null && station == null) return;
    if (!_active && s.playing) {
      _active = true;
      await session.activate(MediaSessionKind.music);
    }
    if (!_active) return;
    final key = station != null ? 'st:${station.id}' : 'tr:${track!.itemId}';
    if (_shownItem != key) {
      _shownItem = key;
      final item = station != null
          // A radio stream (MUS-014): live, no duration.
          ? NowPlaying(title: station.name, isLive: true)
          : NowPlaying(
              title: track!.title,
              artist: track.artist ?? track.albumArtist,
              album: track.album,
              duration: s.duration,
              artwork: await _artwork(track.itemId),
            );
      await session.setNowPlaying(item);
      _shownNowPlaying = item;
      _widgetPlaying = s.playing;
      await widgets?.update(item, playing: s.playing);
    } else if (s.playing != _widgetPlaying && _shownNowPlaying != null) {
      // Home-screen / lock-screen widgets show play or pause (MUS-012).
      _widgetPlaying = s.playing;
      await widgets?.update(_shownNowPlaying, playing: s.playing);
    }
    final state = switch (s.playback.status) {
      PlaybackStatus.playing => SessionPlaybackState.playing,
      PlaybackStatus.buffering ||
      PlaybackStatus.opening => SessionPlaybackState.buffering,
      PlaybackStatus.paused => SessionPlaybackState.paused,
      _ => SessionPlaybackState.stopped,
    };
    // Position updates only on state changes and jumps; the OS extrapolates.
    final jumped =
        (s.position - _shownPosition).abs() > const Duration(seconds: 2);
    _shownPosition = s.position;
    if (state == _shownState && s.hasNext == _shownNext && !jumped) return;
    _shownState = state;
    _shownNext = s.hasNext;
    await session.setPlaybackStatus(
      SessionPlaybackStatus(
        state: state,
        position: s.position,
        canSkipNext: s.hasNext,
        canSkipPrevious: s.hasPrevious,
      ),
    );
  }

  Future<Uint8List?> _artwork(int itemId) async {
    final path = await art.coverPath(itemId);
    if (path == null) return null;
    final f = File(path);
    // Large covers go through as-is; the platform module scales them.
    if (await f.length() > 4 * 1024 * 1024) return null;
    return await f.readAsBytes();
  }
}
