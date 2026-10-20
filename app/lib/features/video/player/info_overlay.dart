import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// Playback statistics over the video (VID-072): codec, hardware decode
/// path, resolution, frame rate, dropped frames, bitrate, dynamic range,
/// audio format and output, subtitle renderer. Technical values are shown
/// as the engine reports them; labels are localised.
class VideoInfoOverlay extends StatelessWidget {
  const VideoInfoOverlay({required this.state, super.key});

  final PlaybackState state;

  static String hdrLabel(AppLocalizations l, VideoStats v) => switch (v.hdr) {
    HdrType.sdr => l.videoInfoHdrSdr,
    HdrType.hdr10 => l.videoInfoHdrHdr10,
    HdrType.hdr10Plus => l.videoInfoHdrHdr10Plus,
    HdrType.hlg => l.videoInfoHdrHlg,
    // Never the trademark (docs/09 §4): "HDR (dynamic metadata, profile 8)".
    HdrType.dolbyVision => l.videoInfoHdrDynamicProfile(
      v.dolbyVisionProfile ?? 0,
    ),
  };

  static String hwdecLabel(AppLocalizations l, HwdecPath p) => switch (p) {
    HwdecPath.none => l.videoInfoSoftware,
    HwdecPath.other => l.videoInfoHardware,
    _ => p.name,
  };

  static List<(String, String)> rows(AppLocalizations l, PlaybackState s) {
    final v = s.video;
    final a = s.audio;
    final video = s.tracks
        .where((t) => t.type == TrackType.video && t.id == s.videoTrackId)
        .firstOrNull;
    final audio = s.tracks
        .where((t) => t.type == TrackType.audio && t.id == s.audioTrackId)
        .firstOrNull;
    final width = v.width ?? video?.width;
    final height = v.height ?? video?.height;
    final fps = v.fps ?? video?.fps;
    return [
      if (v.container != null) (l.videoInfoContainer, v.container!),
      if (v.videoCodec ?? video?.codec case final c?) (l.videoInfoCodec, c),
      (l.videoInfoDecoder, hwdecLabel(l, v.hwdec)),
      if (width != null && height != null)
        (l.videoInfoResolution, l.videoInfoResolutionValue(width, height)),
      if (fps != null) (l.videoInfoFrameRate, l.videoInfoFps(fps)),
      (l.videoInfoDropped, l.videoInfoDroppedValue(v.droppedFrames)),
      if (v.bitrate != null)
        (l.videoInfoBitrate, l.videoInfoKbps((v.bitrate! / 1000).round())),
      (l.videoInfoDynamicRange, hdrLabel(l, v)),
      if (v.renderBackend != null) (l.videoInfoRenderer, v.renderBackend!),
      if (a.format ?? audio?.codec case final f?)
        (
          l.videoInfoAudio,
          [
            f,
            if (a.channels ?? audio?.channels case final ch?)
              l.videoInfoChannels(ch),
            if (a.sampleRate ?? audio?.sampleRate case final r?)
              l.videoInfoHz(r),
          ].join(' · '),
        ),
      if (a.output != null || a.device != null)
        (
          l.videoInfoAudioOutput,
          [?a.output, ?a.device, ?a.bluetoothCodec].join(' · '),
        ),
      if (v.subtitleRenderer != null)
        (l.videoInfoSubtitles, v.subtitleRenderer!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final label = theme.labelMedium!.copyWith(color: Colors.white70);
    final value = theme.labelMedium!.copyWith(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      label: l.videoInfoTitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(KRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KSpacing.s12),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (final (k, v) in rows(l, state))
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: KSpacing.s12,
                        bottom: KSpacing.s4,
                      ),
                      child: Text(k, style: label),
                    ),
                    Text(v, style: value),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
