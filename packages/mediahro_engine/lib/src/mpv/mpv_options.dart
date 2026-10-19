import 'dart:io';

import 'package:mediahro_engine/src/api/models.dart';

/// Platforms the engine configures itself for (docs/05 §4.1). `linux` exists
/// only for desktop test runners and Linux 1.2 (ADR-010).
enum EnginePlatform {
  android,
  ios,
  macos,
  windows,
  linux;

  static EnginePlatform get current => switch (Platform.operatingSystem) {
    'android' => android,
    'ios' => ios,
    'macos' => macos,
    'windows' => windows,
    _ => linux,
  };

  bool get isMobile => this == android || this == ios;
}

/// How video frames leave the core.
enum VideoOutputMode {
  /// Render API into a platform texture (Apple: OpenGL into an IOSurface
  /// `CVPixelBuffer`; Windows: D3D11 render API into a shared texture).
  renderApi,

  /// `vo=gpu-next` drawing straight into an Android `Surface` from Flutter's
  /// `SurfaceProducer` (`wid`), so MediaCodec frames stay on the GPU.
  androidSurface,

  /// `vo=libmpv` driven by the software render API (corpus harness, tests,
  /// thumbnails); never used for on-screen playback.
  software,

  /// No video output (music role, audio-only mode VID-068, headless probes).
  none,
}

/// Audio outputs per platform, most capable first (docs/05 §4.1; AUD-040…042).
String audioOutputsFor(EnginePlatform p) => switch (p) {
  EnginePlatform.android => 'aaudio,opensles,audiotrack',
  EnginePlatform.ios => 'avfoundation,audiounit',
  EnginePlatform.macos => 'coreaudio,avfoundation',
  EnginePlatform.windows => 'wasapi',
  EnginePlatform.linux => 'pipewire,pulse,alsa',
};

/// libmpv options set before `mpv_initialize` (docs/05 §4.1).
///
/// Every row of the §4.1 table is here; anything not listed keeps mpv's
/// default. Scripting, config files, terminal, input bindings, OSC and
/// youtube-dl are off: the engine is embedded, sandboxed and makes no network
/// call the user did not start (PRIV-004).
Map<String, String> defaultMpvOptions({
  required EnginePlatform platform,
  required EngineRole role,
  required VideoOutputMode video,
  bool nullAudio = false,
}) {
  final desktop = !platform.isMobile;
  return {
    // Embedding and sandbox.
    'config': 'no',
    'terminal': 'no',
    'input-default-bindings': 'no',
    'input-vo-keyboard': 'no',
    'osc': 'no',
    'load-scripts': 'no',
    'ytdl': 'no',
    'idle': 'yes',
    'keep-open': 'yes',
    'force-window': 'no',
    'osd-level': '0',
    // Video (VID-030, VID-031).
    ...switch (video) {
      VideoOutputMode.renderApi => {'vo': 'libmpv'},
      // The bridge attaches the Surface and switches to gpu-next (native,
      // synchronous); until then the core runs without a video output.
      VideoOutputMode.androidSurface => {
        'vo': 'null',
        'gpu-context': 'androidvk,android',
        'gpu-api': 'vulkan,opengl',
      },
      VideoOutputMode.software => {'vo': 'libmpv'},
      VideoOutputMode.none => {'vo': 'null', 'vid': 'no'},
    },
    'hwdec': video == VideoOutputMode.software ? 'no' : 'auto-safe',
    'vd-lavc-dr': 'yes',
    'target-colorspace-hint': 'yes',
    'tone-mapping': 'bt.2390',
    'hdr-compute-peak': 'yes',
    'video-sync': desktop ? 'display-resample' : 'audio',
    // Audio (AUD-002, AUD-005, AUD-040…042).
    'ao': nullAudio ? 'null' : audioOutputsFor(platform),
    'audio-exclusive': 'no',
    'gapless-audio': 'yes',
    'prefetch-playlist': 'yes',
    'af': 'scaletempo2',
    'audio-pitch-correction': 'yes',
    'volume-max': '300',
    'audio-display': role == EngineRole.music ? 'no' : 'embedded-first',
    // Subtitles (SUB-010…013).
    'sub-ass': 'yes',
    'embeddedfonts': 'yes',
    'sub-font-provider': 'auto',
    'sub-auto': 'fuzzy',
    // Path lists use ';' on Windows and ':' elsewhere.
    'sub-file-paths': [
      'Subs',
      'subs',
      'Subtitles',
      'subtitles',
      'Sub',
      'sub',
    ].join(platform == EnginePlatform.windows ? ';' : ':'),
    'sub-codepage': 'auto',
    'demuxer-mkv-subtitle-preroll': 'yes',
    // Cache and network (VID-006).
    'cache': 'yes',
    'demuxer-max-bytes': '${cacheBytes(platform: platform, isNetwork: false)}',
    'demuxer-max-back-bytes':
        '${cacheBytes(platform: platform, isNetwork: false) ~/ 4}',
    'network-timeout': '30',
    'stream-lavf-o':
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
        'reconnect_delay_max=30',
    'cache-pause-wait': '2',
    // Edge cases (VID-005).
    'hr-seek': 'default',
    'hr-seek-framedrop': 'yes',
    'vd-lavc-software-fallback': '3',
    'screenshot-format': 'png',
  };
}

/// Demuxer cache budget in bytes (VID-006): sized by bitrate and source type,
/// bounded by platform memory budgets (docs/11 §5: 4K playback RAM ≤ 350 MB
/// mobile, ≤ 500 MB desktop).
int cacheBytes({
  required EnginePlatform platform,
  required bool isNetwork,
  int? bitrate,
}) {
  const mb = 1024 * 1024;
  final mobile = platform.isMobile;
  if (!isNetwork) return (mobile ? 32 : 64) * mb;
  final minimum = (mobile ? 32 : 64) * mb;
  final maximum = (mobile ? 150 : 400) * mb;
  if (bitrate == null || bitrate <= 0) return mobile ? 96 * mb : 192 * mb;
  // 90 s of read-ahead rides out a 30 s Wi-Fi drop with margin.
  final wanted = bitrate ~/ 8 * 90;
  return wanted.clamp(minimum, maximum);
}

/// Whether [uri] is read over a network, for cache sizing.
bool isNetworkUri(Uri uri) => switch (uri.scheme) {
  '' || 'file' || 'fd' || 'fdclose' || 'memory' || 'edl' || 'av' => false,
  _ => true,
};
