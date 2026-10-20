import 'dart:math' as math;
import 'dart:ui';

import 'package:mediahro/images/edit/edit_recipe.dart';

/// Which part of the crop box a finger took hold of.
enum CropHandle {
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

const double _minCrop = 0.05;

/// The handle under [p] (screen pixels) for a crop box drawn at [box], or
/// null when the finger is outside it. Corners and edges win over the inside;
/// [slop] is the reach of a handle (about 22 logical pixels).
CropHandle? hitCropHandle(Rect box, Offset p, {double slop = 22}) {
  final nearL = (p.dx - box.left).abs() <= slop;
  final nearR = (p.dx - box.right).abs() <= slop;
  final nearT = (p.dy - box.top).abs() <= slop;
  final nearB = (p.dy - box.bottom).abs() <= slop;
  final inX = p.dx >= box.left - slop && p.dx <= box.right + slop;
  final inY = p.dy >= box.top - slop && p.dy <= box.bottom + slop;
  if (nearL && nearT) return CropHandle.topLeft;
  if (nearR && nearT) return CropHandle.topRight;
  if (nearL && nearB) return CropHandle.bottomLeft;
  if (nearR && nearB) return CropHandle.bottomRight;
  if (nearT && inX) return CropHandle.top;
  if (nearB && inX) return CropHandle.bottom;
  if (nearL && inY) return CropHandle.left;
  if (nearR && inY) return CropHandle.right;
  if (box.contains(p)) return CropHandle.move;
  return null;
}

/// The crop after dragging [handle] by [delta] (0–1 units of the picture).
/// [ratio] is the pixel width ÷ height to hold, or null for free;
/// [imageAspect] is the picture's pixel width ÷ height, needed to turn a
/// pixel ratio into 0–1 units.
NormRect dragCrop(
  NormRect start,
  CropHandle handle,
  Offset delta, {
  required double imageAspect,
  double? ratio,
}) {
  if (handle == CropHandle.move) {
    return NormRect(
      (start.left + delta.dx).clamp(0.0, 1 - start.width),
      (start.top + delta.dy).clamp(0.0, 1 - start.height),
      start.width,
      start.height,
    );
  }
  var l = start.left;
  var t = start.top;
  var r = start.right;
  var b = start.bottom;
  final movesLeft = const {
    CropHandle.topLeft,
    CropHandle.left,
    CropHandle.bottomLeft,
  }.contains(handle);
  final movesRight = const {
    CropHandle.topRight,
    CropHandle.right,
    CropHandle.bottomRight,
  }.contains(handle);
  final movesTop = const {
    CropHandle.topLeft,
    CropHandle.top,
    CropHandle.topRight,
  }.contains(handle);
  final movesBottom = const {
    CropHandle.bottomLeft,
    CropHandle.bottom,
    CropHandle.bottomRight,
  }.contains(handle);
  if (movesLeft) l = (l + delta.dx).clamp(0.0, r - _minCrop);
  if (movesRight) r = (r + delta.dx).clamp(l + _minCrop, 1.0);
  if (movesTop) t = (t + delta.dy).clamp(0.0, b - _minCrop);
  if (movesBottom) b = (b + delta.dy).clamp(t + _minCrop, 1.0);
  if (ratio == null) return NormRect(l, t, r - l, b - t);

  // Hold the ratio: the dragged side leads, the other follows.
  // heightFor(w) = w * imageAspect / ratio, in 0–1 units.
  final k = imageAspect / ratio;
  final corner = (movesLeft || movesRight) && (movesTop || movesBottom);
  final horizontalEdge = (movesLeft || movesRight) && !corner;
  var w = r - l;
  var h = b - t;
  if (corner) {
    // Width leads; the anchor is the corner that did not move.
    final anchorX = movesLeft ? start.right : start.left;
    final anchorY = movesTop ? start.bottom : start.top;
    final maxW = movesLeft ? anchorX : 1 - anchorX;
    final maxH = movesTop ? anchorY : 1 - anchorY;
    w = math.min(w, math.min(maxW, maxH / k)).clamp(_minCrop, 1.0);
    h = w * k;
    l = movesLeft ? anchorX - w : anchorX;
    t = movesTop ? anchorY - h : anchorY;
    return NormRect(l, t, w, h).clamped(min: _minCrop);
  }
  if (horizontalEdge) {
    // Width leads; the height follows around the vertical middle.
    final cy = (start.top + start.bottom) / 2;
    final maxH = 2 * math.min(cy, 1 - cy);
    w = math.min(w, maxH / k).clamp(_minCrop, 1.0);
    h = w * k;
    t = cy - h / 2;
    l = movesLeft ? r - w : l;
    return NormRect(l, t, w, h).clamped(min: _minCrop);
  }
  // A top or bottom edge: height leads; the width follows around the middle.
  final cx = (start.left + start.right) / 2;
  final maxW = 2 * math.min(cx, 1 - cx);
  h = math.min(h, maxW / k).clamp(_minCrop, 1.0);
  w = h / k;
  l = cx - w / 2;
  t = movesTop ? b - h : t;
  return NormRect(l, t, w, h).clamped(min: _minCrop);
}

/// The largest box of pixel ratio [ratio] that fits the picture, centred on
/// [around]'s middle as far as it can be.
NormRect fitCropRatio(NormRect around, double ratio, double imageAspect) {
  final k = imageAspect / ratio;
  // Largest w with w <= 1 and w * k <= 1.
  final w = (1 / k).clamp(0.0, 1.0);
  final h = w * k;
  final cx = (around.left + around.right) / 2;
  final cy = (around.top + around.bottom) / 2;
  // Keep about the same area as the box it replaces, never smaller than 30 %.
  final scale = math
      .sqrt((around.width * around.height) / (w * h))
      .clamp(0.3, 1.0);
  final fw = w * scale;
  final fh = h * scale;
  return NormRect(
    (cx - fw / 2).clamp(0.0, 1 - fw),
    (cy - fh / 2).clamp(0.0, 1 - fh),
    fw,
    fh,
  );
}

/// The drawing helpers' output: a polyline for an arrow from [from] to [to]
/// (0–1 coordinates) with an arrow head of [head] (fraction of the shorter
/// side) at the end. [aspect] is the picture's pixel width ÷ height.
List<(double, double)> arrowPoints(
  (double, double) from,
  (double, double) to, {
  required double aspect,
  double head = 0.04,
}) {
  // Work in a square space so the head is not squashed on a wide picture.
  (double, double) sq((double, double) p) => (p.$1 * aspect, p.$2);
  (double, double) back((double, double) p) => (p.$1 / aspect, p.$2);
  final a = sq(from);
  final b = sq(to);
  final dx = b.$1 - a.$1;
  final dy = b.$2 - a.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-6) return [from];
  final ux = dx / len;
  final uy = dy / len;
  final size = math.min(head, len * 0.5);
  (double, double) wing(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return (b.$1 - size * (ux * c - uy * s), b.$2 - size * (ux * s + uy * c));
  }

  final w1 = wing(math.pi / 6);
  final w2 = wing(-math.pi / 6);
  return [from, to, back(w1), to, back(w2)];
}

/// A closed rectangle outline through [a] and [b].
List<(double, double)> boxPoints((double, double) a, (double, double) b) => [
  a,
  (b.$1, a.$2),
  b,
  (a.$1, b.$2),
  a,
];

/// A rectangle through two corners as a normalised crop-style box.
NormRect rectBetween((double, double) a, (double, double) b) => NormRect(
  math.min(a.$1, b.$1),
  math.min(a.$2, b.$2),
  (a.$1 - b.$1).abs(),
  (a.$2 - b.$2).abs(),
).clamped(min: 0.005);
