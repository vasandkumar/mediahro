import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/painting.dart' show BoxFit;
import 'package:mediahro/platform/display.dart';

/// What a presentation frame may contain (ADR-044 amendment 1). The engine on
/// the external display draws what it is sent, so both ends check every frame
/// against these limits and reject a bad one with a [FormatException].
abstract final class PresentationLimits {
  /// Encoded image bytes.
  static const int maxImageBytes = 32 * 1024 * 1024;

  /// Pixels on either side of the image, read from its header before it is
  /// decoded; larger images are refused (and on screen they are decoded at the
  /// size of the display, not their own).
  static const int maxImageEdge = 8192;

  /// A transition or a pan and zoom.
  static const Duration maxDuration = Duration(seconds: 60);

  static const int maxCaptionChars = 1000;
}

/// The wire form of a [PresentationFrame] (ADR-044 amendment 1): a map of
/// plain values that the standard message codec carries from the app to the
/// native presentation module and on to the engine that draws on the external
/// display. Both ends use this class, so what is sent is what is read, and
/// both [validate] it.
abstract final class PresentationFrameCodec {
  /// The map for [f]. Throws [FormatException] if the frame breaks
  /// [PresentationLimits].
  static Map<String, Object?> toMap(PresentationFrame f) {
    validate(f);
    return {
      'image': f.image,
      'fit': f.fit.name,
      'transition': f.transition.name,
      'transitionMs': f.transitionDuration.inMilliseconds,
      'motion': f.motion == null ? null : _motion(f.motion!),
      'caption': f.caption,
    };
  }

  /// The frame in [m], or a [FormatException] for anything that is not a
  /// well-formed, in-limits frame (wrong types, unknown names, a rectangle
  /// outside the image, a huge image, a long duration).
  static PresentationFrame fromMap(Map<Object?, Object?> m) {
    final frame = PresentationFrame(
      image: _bytes(m['image']),
      fit: _named(BoxFit.values, m['fit'], 'fit', BoxFit.contain),
      transition: _named(
        PresentationTransition.values,
        m['transition'],
        'transition',
        PresentationTransition.none,
      ),
      transitionDuration: _duration(m['transitionMs'], 'transitionMs'),
      motion: switch (m['motion']) {
        null => null,
        final Map<Object?, Object?> motion => _readMotion(motion),
        _ => throw const FormatException('motion is not a map'),
      },
      caption: switch (m['caption']) {
        null => null,
        final String c => c,
        _ => throw const FormatException('caption is not text'),
      },
    );
    validate(frame);
    return frame;
  }

  /// Throws [FormatException] unless [f] is within [PresentationLimits].
  static void validate(PresentationFrame f) {
    final image = f.image;
    if (image != null) {
      if (image.length > PresentationLimits.maxImageBytes) {
        throw FormatException(
          'image is ${image.length} bytes (limit ${PresentationLimits.maxImageBytes})',
        );
      }
      final size = imageSize(image);
      if (size == null) {
        throw const FormatException('image is not a PNG or JPEG');
      }
      if (size.$1 < 1 ||
          size.$2 < 1 ||
          size.$1 > PresentationLimits.maxImageEdge ||
          size.$2 > PresentationLimits.maxImageEdge) {
        throw FormatException(
          'image is ${size.$1}x${size.$2} (limit ${PresentationLimits.maxImageEdge} per side)',
        );
      }
    }
    _checkDuration(f.transitionDuration, 'transitionDuration');
    final motion = f.motion;
    if (motion != null) {
      _checkRect(motion.from, 'motion.from');
      _checkRect(motion.to, 'motion.to');
      _checkDuration(motion.duration, 'motion.duration');
    }
    final caption = f.caption;
    if (caption != null &&
        caption.length > PresentationLimits.maxCaptionChars) {
      throw const FormatException('caption is too long');
    }
  }

  /// (width, height) from the header of a PNG or JPEG, or null if `bytes` is
  /// neither (or the header is cut short). Reads only the header: a huge
  /// image is refused before anything decodes it.
  static (int, int)? imageSize(Uint8List b) {
    // PNG: 8-byte signature, then the IHDR chunk with 32-bit width and height.
    if (b.length >= 24 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[12] == 0x49 && // I
        b[13] == 0x48 && // H
        b[14] == 0x44 && // D
        b[15] == 0x52) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return (w, h);
    }
    // JPEG: SOI, then segments until a start-of-frame marker.
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        if (marker == 0xD8 ||
            marker == 0x01 ||
            (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        final length = (b[i + 2] << 8) | b[i + 3];
        final isFrame =
            marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isFrame) {
          final h = (b[i + 5] << 8) | b[i + 6];
          final w = (b[i + 7] << 8) | b[i + 8];
          return (w, h);
        }
        if (length < 2) return null;
        i += 2 + length;
      }
    }
    return null;
  }

  /// The value called [name]; [fallback] if there is no name, an error if the name is unknown.
  static T _named<T extends Enum>(
    List<T> values,
    Object? name,
    String field,
    T fallback,
  ) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw FormatException('unknown $field: $name');
  }

  static Duration _duration(Object? ms, String field) {
    if (ms == null) return Duration.zero;
    if (ms is! num || !ms.isFinite || ms.abs() > 1e12) {
      throw FormatException('$field is not a sane number');
    }
    return Duration(milliseconds: ms.round());
  }

  static void _checkDuration(Duration d, String field) {
    if (d.isNegative || d > PresentationLimits.maxDuration) {
      throw FormatException('$field is out of range: $d');
    }
  }

  static void _checkRect(Rect r, String field) {
    final values = [r.left, r.top, r.right, r.bottom];
    if (values.any((v) => !v.isFinite || v < 0 || v > 1) ||
        r.right <= r.left ||
        r.bottom <= r.top) {
      throw FormatException('$field is not a rectangle inside the image: $r');
    }
  }

  static Uint8List? _bytes(Object? v) => switch (v) {
    null => null,
    final Uint8List b => b,
    final List<int> l => Uint8List.fromList(l),
    _ => throw const FormatException('image is not bytes'),
  };

  static Map<String, Object?> _motion(PresentationMotion m) => {
    'from': _rect(m.from),
    'to': _rect(m.to),
    'durationMs': m.duration.inMilliseconds,
  };

  static List<double> _rect(Rect r) => [r.left, r.top, r.right, r.bottom];

  static Rect _readRect(Object? v, String field) {
    if (v is! List<Object?> || v.length != 4) {
      throw FormatException('$field needs exactly four numbers');
    }
    final n = <double>[];
    for (final e in v) {
      if (e is! num || !e.isFinite) {
        throw FormatException('$field has a value that is not a finite number');
      }
      n.add(e.toDouble());
    }
    return Rect.fromLTRB(n[0], n[1], n[2], n[3]);
  }

  static PresentationMotion _readMotion(Map<Object?, Object?> m) =>
      PresentationMotion(
        from: _readRect(m['from'], 'motion.from'),
        to: _readRect(m['to'], 'motion.to'),
        duration: m['durationMs'] == null
            ? throw const FormatException('motion has no duration')
            : _duration(m['durationMs'], 'motion.durationMs'),
      );
}
