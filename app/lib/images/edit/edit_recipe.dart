import 'package:mediahro/images/image_pipeline.dart';
import 'package:meta/meta.dart';

/// A rectangle in 0–1 coordinates of the picture it is drawn on, so a recipe
/// means the same thing on a 1 400 px preview and on the full-size photo.
@immutable
final class NormRect {
  const NormRect(this.left, this.top, this.width, this.height);

  static const NormRect full = NormRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  bool get isFull => left <= 0 && top <= 0 && width >= 1 && height >= 1;

  /// Kept inside the picture and at least [min] wide and high.
  NormRect clamped({double min = 0.02}) {
    final w = width.clamp(min, 1.0);
    final h = height.clamp(min, 1.0);
    return NormRect(left.clamp(0.0, 1 - w), top.clamp(0.0, 1 - h), w, h);
  }

  Map<String, Object?> toJson() => {
    'l': left,
    't': top,
    'w': width,
    'h': height,
  };

  static NormRect? fromJson(Object? j) {
    if (j is! Map) return null;
    final l = j['l'];
    final t = j['t'];
    final w = j['w'];
    final h = j['h'];
    if (l is num && t is num && w is num && h is num) {
      return NormRect(
        l.toDouble(),
        t.toDouble(),
        w.toDouble(),
        h.toDouble(),
      ).clamped();
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// A drawn line: points in 0–1 coordinates of the finished picture, a colour
/// and a width as a fraction of the picture's shorter side.
@immutable
final class StrokeSpec {
  const StrokeSpec(this.points, {required this.colorArgb, this.width = 0.01});

  final List<(double, double)> points;
  final int colorArgb;
  final double width;

  Map<String, Object?> toJson() => {
    'p': [
      for (final (x, y) in points) [x, y],
    ],
    'c': colorArgb,
    'w': width,
  };

  static StrokeSpec? fromJson(Object? j) {
    if (j is! Map || j['p'] is! List) return null;
    final points = <(double, double)>[];
    for (final p in j['p'] as List<Object?>) {
      if (p is List && p.length == 2 && p[0] is num && p[1] is num) {
        points.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    final c = j['c'];
    final w = j['w'];
    if (points.isEmpty || c is! int || w is! num) return null;
    return StrokeSpec(points, colorArgb: c, width: w.toDouble());
  }
}

/// A blurred area (to hide a face or a number plate).
@immutable
final class BlurSpec {
  const BlurSpec(this.rect, {this.radius = 0.03});

  final NormRect rect;

  /// Fraction of the picture's shorter side.
  final double radius;

  Map<String, Object?> toJson() => {'r': rect.toJson(), 'x': radius};

  static BlurSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final r = NormRect.fromJson(j['r']);
    final x = j['x'];
    if (r == null || x is! num) return null;
    return BlurSpec(r, radius: x.toDouble());
  }
}

/// Curves as control points in 0–1 space, x ascending; fewer than two points
/// is a straight line.
@immutable
final class CurveSet {
  const CurveSet({
    this.master = const [],
    this.red = const [],
    this.green = const [],
    this.blue = const [],
  });

  factory CurveSet.fromJson(Object? j) => j is Map
      ? CurveSet(
          master: _read(j['m']),
          red: _read(j['r']),
          green: _read(j['g']),
          blue: _read(j['b']),
        )
      : const CurveSet();

  final List<(double, double)> master;
  final List<(double, double)> red;
  final List<(double, double)> green;
  final List<(double, double)> blue;

  bool get isIdentity =>
      _flat(master) && _flat(red) && _flat(green) && _flat(blue);

  static bool _flat(List<(double, double)> c) =>
      c.length < 2 || c.every((p) => (p.$1 - p.$2).abs() < 1e-6);

  CurveSet copyWith({
    List<(double, double)>? master,
    List<(double, double)>? red,
    List<(double, double)>? green,
    List<(double, double)>? blue,
  }) => CurveSet(
    master: master ?? this.master,
    red: red ?? this.red,
    green: green ?? this.green,
    blue: blue ?? this.blue,
  );

  Map<String, Object?> toJson() => {
    if (master.isNotEmpty) 'm': _points(master),
    if (red.isNotEmpty) 'r': _points(red),
    if (green.isNotEmpty) 'g': _points(green),
    if (blue.isNotEmpty) 'b': _points(blue),
  };

  static List<List<double>> _points(List<(double, double)> c) => [
    for (final (x, y) in c) [x, y],
  ];

  static List<(double, double)> _read(Object? j) {
    if (j is! List) return const [];
    return [
      for (final p in j)
        if (p is List && p.length == 2 && p[0] is num && p[1] is num)
          ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
  }
}

/// Everything the editor does to a photo (IMG-009), as data: it is what the
/// editor shows, what is saved with the photo so editing can continue, and
/// what batch apply copies. The original file is never touched until the
/// user saves.
///
/// Geometry order: flip, quarter turns, straighten, crop. Then light and
/// colour, detail, vignette, blurred areas and drawing.
@immutable
final class EditRecipe {
  const EditRecipe({
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.turns = 0,
    this.straighten = 0,
    this.crop = NormRect.full,
    this.adjust = const {},
    this.curves = const CurveSet(),
    this.blurs = const [],
    this.strokes = const [],
  });

  /// Reads a saved recipe; anything unreadable is dropped, never fatal.
  factory EditRecipe.fromJson(Object? j) {
    if (j is! Map) return none;
    final adjust = <AdjustKind, double>{};
    final a = j['adjust'];
    if (a is Map) {
      for (final k in AdjustKind.values) {
        final v = a[k.name];
        if (v is num) adjust[k] = v.toDouble().clamp(-1.0, 1.0);
      }
    }
    final turns = j['turns'];
    final straighten = j['straighten'];
    return EditRecipe(
      flipHorizontal: j['fh'] == true,
      flipVertical: j['fv'] == true,
      turns: turns is int ? turns % 4 : 0,
      straighten: straighten is num
          ? straighten.toDouble().clamp(-45.0, 45.0)
          : 0,
      crop: NormRect.fromJson(j['crop']) ?? NormRect.full,
      adjust: adjust,
      curves: CurveSet.fromJson(j['curves']),
      blurs: [
        if (j['blurs'] is List)
          for (final b in j['blurs'] as List<Object?>)
            if (BlurSpec.fromJson(b) case final BlurSpec s) s,
      ],
      strokes: [
        if (j['strokes'] is List)
          for (final s in j['strokes'] as List<Object?>)
            if (StrokeSpec.fromJson(s) case final StrokeSpec t) t,
      ],
    );
  }

  /// The recipe of a list of [EditOp]s on a picture of [width] × [height]
  /// source pixels (the contract of `ImagePipeline.export`). Crop and blur
  /// regions are in source pixels; stroke points and widths are 0–1.
  factory EditRecipe.fromOps(List<EditOp> ops, int width, int height) {
    var r = none;
    for (final op in ops) {
      switch (op) {
        case CropOp(:final region):
          r = r.copyWith(
            crop: NormRect(
              region.left / width,
              region.top / height,
              region.width / width,
              region.height / height,
            ).clamped(),
          );
        case RotateOp(:final degrees):
          final quarter = (degrees / 90).round();
          final rest = degrees - quarter * 90;
          r = r.copyWith(
            turns: r.turns + quarter,
            straighten: (r.straighten + rest).clamp(-45.0, 45.0),
          );
        case FlipOp(:final horizontal, :final vertical):
          r = r.copyWith(
            flipHorizontal: horizontal ? !r.flipHorizontal : null,
            flipVertical: vertical ? !r.flipVertical : null,
          );
        case AdjustOp(:final kind, :final amount):
          r = r.withAdjust(kind, amount);
        case CurvesOp(:final points):
          r = r.copyWith(curves: r.curves.copyWith(master: points));
        case BlurRegionOp(:final region, :final radius):
          final shorter = width < height ? width : height;
          r = r.copyWith(
            blurs: [
              ...r.blurs,
              BlurSpec(
                NormRect(
                  region.left / width,
                  region.top / height,
                  region.width / width,
                  region.height / height,
                ).clamped(),
                radius: radius / shorter,
              ),
            ],
          );
        case StrokeOp(
          :final points,
          :final colorArgb,
          width: final strokeWidth,
        ):
          r = r.copyWith(
            strokes: [
              ...r.strokes,
              StrokeSpec(points, colorArgb: colorArgb, width: strokeWidth),
            ],
          );
      }
    }
    return r;
  }

  static const EditRecipe none = EditRecipe();

  final bool flipHorizontal;
  final bool flipVertical;

  /// Clockwise quarter turns, 0–3.
  final int turns;

  /// Degrees, −45…45; the picture is cropped to the largest upright
  /// rectangle that fits, so no blank corners appear.
  final double straighten;

  /// Of the straightened picture.
  final NormRect crop;

  /// −1…1 per kind (sharpen 0…1); missing means 0.
  final Map<AdjustKind, double> adjust;
  final CurveSet curves;
  final List<BlurSpec> blurs;
  final List<StrokeSpec> strokes;

  double amount(AdjustKind k) => adjust[k] ?? 0;

  bool get hasGeometry =>
      flipHorizontal ||
      flipVertical ||
      turns % 4 != 0 ||
      straighten.abs() > 0.005 ||
      !crop.isFull;

  bool get hasLook =>
      adjust.values.any((v) => v.abs() > 0.0005) || !curves.isIdentity;

  bool get hasAnnotations => blurs.isNotEmpty || strokes.isNotEmpty;

  bool get isIdentity => !hasGeometry && !hasLook && !hasAnnotations;

  EditRecipe copyWith({
    bool? flipHorizontal,
    bool? flipVertical,
    int? turns,
    double? straighten,
    NormRect? crop,
    Map<AdjustKind, double>? adjust,
    CurveSet? curves,
    List<BlurSpec>? blurs,
    List<StrokeSpec>? strokes,
  }) => EditRecipe(
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    turns: (turns ?? this.turns) % 4,
    straighten: straighten ?? this.straighten,
    crop: crop ?? this.crop,
    adjust: adjust ?? this.adjust,
    curves: curves ?? this.curves,
    blurs: blurs ?? this.blurs,
    strokes: strokes ?? this.strokes,
  );

  /// One adjustment changed; zero removes it.
  EditRecipe withAdjust(AdjustKind kind, double value) {
    final next = {...adjust};
    if (value.abs() < 0.0005) {
      next.remove(kind);
    } else {
      next[kind] = value.clamp(-1.0, 1.0);
    }
    return copyWith(adjust: next);
  }

  /// Only light, colour, detail and curves: what makes sense on other photos
  /// (batch apply). Crop, straightening and drawings belong to one picture.
  EditRecipe look() => EditRecipe(adjust: adjust, curves: curves);

  Map<String, Object?> toJson() => {
    'v': 1,
    if (flipHorizontal) 'fh': true,
    if (flipVertical) 'fv': true,
    if (turns % 4 != 0) 'turns': turns % 4,
    if (straighten.abs() > 0.005) 'straighten': straighten,
    if (!crop.isFull) 'crop': crop.toJson(),
    if (adjust.isNotEmpty)
      'adjust': {for (final e in adjust.entries) e.key.name: e.value},
    if (!curves.isIdentity) 'curves': curves.toJson(),
    if (blurs.isNotEmpty) 'blurs': [for (final b in blurs) b.toJson()],
    if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) s.toJson()],
  };
}
