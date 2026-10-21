// 360° look-around (IMG-001): shows an equirectangular picture as a camera
// looking in one direction. The same arithmetic is in lib/features/photos/
// pano/pano_math.dart (PanoCamera.direction, PanoGeometry.uv), which is what
// the tests check. Original work for Mediahro; no third-party code.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // viewport, logical pixels
uniform vec2 uImageSize;   // picture, pixels
uniform float uYaw;        // radians, right of the sphere's middle
uniform float uPitch;      // radians, above the horizon
uniform float uTanHalfFov; // tan(vertical field of view / 2)
uniform float uAspect;     // viewport width / height
uniform vec4 uCrop;        // lonMin, lonSpan, latMax, latSpan (radians)
uniform float uWrap;       // 1 when the picture goes all the way round
uniform sampler2D uImage;

out vec4 fragColor;

const float PI = 3.14159265358979;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  float nx = (p.x - 0.5) * 2.0 * uTanHalfFov * uAspect;
  float ny = (0.5 - p.y) * 2.0 * uTanHalfFov;
  float sp = sin(uPitch);
  float cp = cos(uPitch);
  float dx = nx;
  float dy = ny * cp + sp;
  float dz = cp - ny * sp;
  float lon = uYaw + atan(dx, dz);
  float lat = asin(dy / sqrt(dx * dx + dy * dy + dz * dz));

  float u;
  if (uWrap > 0.5) {
    u = mod(lon - uCrop.x, 2.0 * PI) / uCrop.y;
  } else {
    float centre = uCrop.x + uCrop.y * 0.5;
    float d = mod(lon - centre + PI, 2.0 * PI) - PI;
    u = (centre + d - uCrop.x) / uCrop.y;
  }
  float v = (uCrop.z - lat) / uCrop.w;

  // Normalised coordinates, kept half a texel inside the picture.
  vec2 edge = 0.5 / uImageSize;
  fragColor = texture(uImage, clamp(vec2(u, v), edge, vec2(1.0) - edge));
}
