import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Media session and lock-screen/notification integration (SYS-001, SYS-002):
/// Media3 MediaSessionService (A), MPNowPlayingInfoCenter +
/// MPRemoteCommandCenter (I M), SystemMediaTransportControls (W).
abstract interface class MediaSessionFacade {
  Future<void> activate(MediaSessionKind kind);
  Future<void> setNowPlaying(NowPlaying item);
  Future<void> setPlaybackStatus(SessionPlaybackStatus status);
  Stream<RemoteCommand> get commands;
  Future<void> deactivate();
}

enum MediaSessionKind { video, music, podcast }

enum SessionPlaybackState { playing, paused, buffering, stopped }

@immutable
final class NowPlaying {
  const NowPlaying({
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.artwork,
    this.isLive = false,
  });

  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;

  /// Encoded image (PNG/JPEG), already downscaled.
  final Uint8List? artwork;
  final bool isLive;
}

@immutable
final class SessionPlaybackStatus {
  const SessionPlaybackStatus({
    required this.state,
    required this.position,
    this.rate = 1,
    this.canSkipNext = false,
    this.canSkipPrevious = false,
  });

  final SessionPlaybackState state;
  final Duration position;
  final double rate;
  final bool canSkipNext;
  final bool canSkipPrevious;
}

/// Commands from lock screen, notification, headset, car, watch, SMTC.
@immutable
sealed class RemoteCommand {
  const RemoteCommand();
}

final class PlayCommand extends RemoteCommand {
  const PlayCommand();
}

final class PauseCommand extends RemoteCommand {
  const PauseCommand();
}

final class TogglePlayPauseCommand extends RemoteCommand {
  const TogglePlayPauseCommand();
}

final class NextCommand extends RemoteCommand {
  const NextCommand();
}

final class PreviousCommand extends RemoteCommand {
  const PreviousCommand();
}

final class StopCommand extends RemoteCommand {
  const StopCommand();
}

final class SeekToCommand extends RemoteCommand {
  const SeekToCommand(this.position);
  final Duration position;
}

final class SkipByCommand extends RemoteCommand {
  const SkipByCommand(this.offset);
  final Duration offset;
}

final class SetRateCommand extends RemoteCommand {
  const SetRateCommand(this.rate);
  final double rate;
}
