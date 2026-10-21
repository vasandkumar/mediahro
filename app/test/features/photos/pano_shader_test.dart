import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/pano/pano_controller.dart';
import 'package:mediahro/features/photos/pano/pano_painter.dart';
import 'package:mediahro/images/metadata/pano_meta.dart';

/// A picture whose colour tells where on the sphere a pixel is: red grows to
/// the right, green downward.
Future<ui.Image> _map() async {
  const w = 256;
  const h = 128;
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      px[i] = (x * 255 / (w - 1)).round();
      px[i + 1] = (y * 255 / (h - 1)).round();
      px[i + 2] = 128;
      px[i + 3] = 255;
    }
  }
  final c = ui.ImmutableBuffer.fromUint8List(px);
  final buffer = await c;
  final d = await ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  return (await d.getNextFrame()).image;
}

Future<Uint8List> _draw(
  ui.Image image,
  PanoController c,
  ui.FragmentProgram? program,
) async {
  const size = Size(160, 120);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  PanoPainter(
    image: image,
    controller: c,
    program: program,
  ).paint(canvas, size);
  final out = await rec.endRecording().toImage(160, 120);
  final data = await out.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  // The shader is declared in pubspec.yaml; the check is made where it is.
  final declared = File('pubspec.yaml')
      .readAsStringSync()
      .contains('shaders/pano_equirect.frag');

  group(
    'IMG-001 the shader and the mesh draw the same picture',
    () {
      for (final (name, meta, yaw, pitch) in [
        ('whole sphere ahead', null, 0.0, 0.0),
        ('whole sphere across the seam', null, 3.1, 0.2),
        ('whole sphere looking up', null, 1.0, 0.9),
        (
          'cropped window',
          const PanoramaMeta(
            projection: 'equirectangular',
            fullWidth: 8000,
            fullHeight: 4000,
            croppedWidth: 4000,
            croppedHeight: 2000,
            croppedLeft: 2000,
            croppedTop: 1000,
          ),
          0.3,
          0.1,
        ),
      ]) {
        test('IMG-001 $name', () async {
          final program = await loadPanoProgram();
          expect(program, isNotNull);
          final image = await _map();
          final c = PanoController(meta: meta);
          c
            ..setAspect(160 / 120)
            ..turn(yaw: yaw - c.view.yaw, pitch: pitch - c.view.pitch);
          final shader = await _draw(image, c, program);
          final mesh = await _draw(image, c, null);
          var sum = 0;
          var far = 0;
          for (var i = 0; i < shader.length; i += 4) {
            var worst = 0;
            for (var k = 0; k < 4; k++) {
              final d = (shader[i + k] - mesh[i + k]).abs();
              sum += d;
              if (d > worst) worst = d;
            }
            if (worst > 40) far++;
          }
          final mean = sum / shader.length;
          // The mesh is exact at its vertices and a few pixels off between
          // them; the picture is a smooth gradient, so the mean stays small.
          expect(mean, lessThan(3), reason: 'mean difference $mean');
          // Only the seam of a whole sphere may differ (the mesh blends the two
          // edges, the shader holds each): a thin line of pixels.
          expect(far / (shader.length / 4), lessThan(0.02), reason: '$far');
        });
      }
    },
    skip: declared ? false : 'blocked: pubspec.yaml does not yet declare shaders/pano_equirect.frag (orchestrator change)',
  );
}
