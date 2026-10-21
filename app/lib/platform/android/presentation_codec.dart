import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/painting.dart' show BoxFit;
import 'package:mediahro/platform/display.dart';

/// The wire form of a [PresentationFrame] (ADR-044 amendment 1): a map of
/// plain values that the standard message codec carries from the app to the
/// native presentation module and on to the engine that draws on the external
/// display. Both ends use this class, so what is sent is what is read.
abstract final class PresentationFrameCodec {
  static Map<String, Object?> toMap(PresentationFrame f) => {
    'image': f.image,
    'fit': f.fit.name,
    'transition': f.transition.name,
    'transitionMs': f.transitionDuration.inMilliseconds,
    'motion': f.motion == null ? null : _motion(f.motion!),
    'caption': f.caption,
  };

  static PresentationFrame fromMap(Map<Object?, Object?> m) {
    final motion = m['motion'];
    return PresentationFrame(
      image: _bytes(m['image']),
      fit: BoxFit.values.asNameMap()[m['fit']] ?? BoxFit.contain,
      transition:
          PresentationTransition.values.asNameMap()[m['transition']] ??
          PresentationTransition.none,
      transitionDuration: Duration(
        milliseconds: (m['transitionMs'] as num?)?.toInt() ?? 0,
      ),
      motion: motion is Map<Object?, Object?> ? _readMotion(motion) : null,
      caption: m['caption'] as String?,
    );
  }

  static Uint8List? _bytes(Object? v) => switch (v) {
    final Uint8List b => b,
    final List<int> l => Uint8List.fromList(l),
    _ => null,
  };

  static Map<String, Object?> _motion(PresentationMotion m) => {
    'from': _rect(m.from),
    'to': _rect(m.to),
    'durationMs': m.duration.inMilliseconds,
  };

  static List<double> _rect(Rect r) => [r.left, r.top, r.right, r.bottom];

  static Rect _readRect(Object? v) {
    final l = (v! as List<Object?>).map((e) => (e! as num).toDouble()).toList();
    return Rect.fromLTRB(l[0], l[1], l[2], l[3]);
  }

  static PresentationMotion _readMotion(Map<Object?, Object?> m) =>
      PresentationMotion(
        from: _readRect(m['from']),
        to: _readRect(m['to']),
        duration: Duration(milliseconds: (m['durationMs']! as num).toInt()),
      );
}
