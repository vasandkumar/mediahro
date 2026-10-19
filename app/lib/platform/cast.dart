import 'package:meta/meta.dart';

/// Casting senders (CAST-001…003): Google Cast SDK (A I, store flavour),
/// Open Screen (M W, FOSS), AirPlay route picker (I M), DLNA AVTransport.
abstract interface class CastFacade {
  Stream<List<CastDevice>> discover();
  Future<CastSession> connect(CastDevice device);

  /// System route picker (AirPlay) where one exists.
  Future<void> showSystemRoutePicker();
}

enum CastProtocol { googleCast, airPlay, dlna }

@immutable
final class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.protocol,
    this.supportsVideo = true,
  });

  final String id;
  final String name;
  final CastProtocol protocol;
  final bool supportsVideo;
}

@immutable
final class CastMedia {
  const CastMedia({
    required this.uri,
    required this.contentType,
    this.title,
    this.subtitles = const [],
    this.start,
  });

  /// URL on the embedded cast server (docs/05 §4.5).
  final Uri uri;
  final String contentType;
  final String? title;

  /// WebVTT tracks.
  final List<Uri> subtitles;
  final Duration? start;
}

abstract interface class CastSession {
  CastDevice get device;
  Future<void> load(CastMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Stream<CastStatus> get status;
  Future<void> disconnect();
}

@immutable
final class CastStatus {
  const CastStatus({
    required this.playing,
    required this.position,
    this.duration,
    this.volume = 1,
  });

  final bool playing;
  final Duration position;
  final Duration? duration;
  final double volume;
}
