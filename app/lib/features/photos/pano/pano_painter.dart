import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:mediahro/features/photos/pano/pano_controller.dart';

/// The path of the fragment shader (declared in pubspec.yaml under `shaders:`).
const String panoShaderAsset = 'shaders/pano_equirect.frag';

/// Loads the shader; null when the build has none (the picture is then drawn
/// with a mesh, which looks the same to the eye).
Future<ui.FragmentProgram?> loadPanoProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(panoShaderAsset);
  } on Object {
    return null;
  }
}

/// Draws the part of an equirectangular picture the camera sees (IMG-001):
/// with the fragment shader per pixel, or, when [program] is null, with a
/// grid of vertices whose texture coordinates come from the same arithmetic
/// (a rectilinear view is exact at the vertices and a few pixels off between
/// them, which is not visible at the grid size used).
final class PanoPainter extends CustomPainter {
  PanoPainter({
    required this.image,
    required this.controller,
    required this.program,
    this.background = const Color(0xFF000000),
  }) : super(repaint: controller);

  final ui.Image image;
  final PanoController controller;
  final ui.FragmentProgram? program;
  final Color background;

  /// True once a frame was drawn with the shader (for tests).
  static bool lastUsedShader = false;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    controller.setAspect(size.width / size.height);
    final view = controller.view;
    final camera = controller.camera;
    final g = controller.geometry;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final prog = program;
    if (prog != null) {
      final shader = prog.fragmentShader()
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, image.width.toDouble())
        ..setFloat(3, image.height.toDouble())
        ..setFloat(4, view.yaw)
        ..setFloat(5, view.pitch)
        ..setFloat(6, math.tan(view.fov / 2))
        ..setFloat(7, camera.aspect)
        ..setFloat(8, g.lonMin)
        ..setFloat(9, g.lonSpan)
        ..setFloat(10, g.latMax)
        ..setFloat(11, g.latSpan)
        ..setFloat(12, g.wrapsAround ? 1 : 0)
        ..setImageSampler(0, image);
      lastUsedShader = true;
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      shader.dispose();
      return;
    }
    lastUsedShader = false;
    _paintMesh(canvas, size);
  }

  void _paintMesh(Canvas canvas, Size size) {
    final view = controller.view;
    final camera = controller.camera;
    final g = controller.geometry;
    const cols = 40;
    final rows = (cols * size.height / size.width).ceil().clamp(12, 64);
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final positions = Float32List((cols + 1) * (rows + 1) * 2);
    final coords = Float32List(positions.length);
    var k = 0;
    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        final x = size.width * c / cols;
        final y = size.height * r / rows;
        final (lon, lat) = camera.direction(Offset(x, y), size, view);
        // Not wrapped: the shader repeats the picture sideways, so a view
        // across the seam stays continuous.
        final u = (lon - g.lonMin) / g.lonSpan;
        final v = (g.latMax - lat) / g.latSpan;
        positions[k] = x;
        positions[k + 1] = y;
        coords[k] = u * w;
        coords[k + 1] = v.clamp(0, 1) * h;
        k += 2;
      }
    }
    final indices = Uint16List(cols * rows * 6);
    var i = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final a = r * (cols + 1) + c;
        final b = a + 1;
        final d = a + cols + 1;
        final e = d + 1;
        indices
          ..[i] = a
          ..[i + 1] = b
          ..[i + 2] = d
          ..[i + 3] = b
          ..[i + 4] = e
          ..[i + 5] = d;
        i += 6;
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: coords,
      indices: indices,
    );
    final shader = ui.ImageShader(
      image,
      g.wrapsAround ? ui.TileMode.repeated : ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint()..shader = shader);
    vertices.dispose();
    shader.dispose();
  }

  @override
  bool shouldRepaint(PanoPainter old) =>
      old.image != image ||
      old.program != program ||
      old.controller != controller ||
      old.background != background;
}
