import 'dart:typed_data';

/// One bitmap subtitle (PGS, VobSub or DVB) cut out of an embedded track
/// (ADR-031 part 2, SUB-051 OCR).
///
/// The bitmap covers only the part of the video frame that holds
/// subtitle pixels: [x], [y], [width] and [height] place it in a frame of
/// [frameWidth] × [frameHeight]. [rgba] is straight (non-premultiplied)
/// RGBA, [width] × [height] × 4 bytes, row by row.
final class SubtitleImage {
  const SubtitleImage({
    required this.start,
    required this.end,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.frameWidth,
    required this.frameHeight,
    required this.rgba,
  });

  /// When the subtitle appears and disappears, on the media timeline.
  final Duration start;
  final Duration end;

  final int x;
  final int y;
  final int width;
  final int height;
  final int frameWidth;
  final int frameHeight;
  final Uint8List rgba;

  SubtitleImage withEnd(Duration end) => SubtitleImage(
    start: start,
    end: end,
    x: x,
    y: y,
    width: width,
    height: height,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    rgba: rgba,
  );

  SubtitleImage shifted(Duration by) => SubtitleImage(
    start: start + by,
    end: end + by,
    x: x,
    y: y,
    width: width,
    height: height,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    rgba: rgba,
  );

  @override
  String toString() =>
      'SubtitleImage($start–$end ${width}x$height at $x,$y '
      'in ${frameWidth}x$frameHeight)';
}
