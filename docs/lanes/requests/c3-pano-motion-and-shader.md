# C3 requests for the 360° look-around (IMG-001), 2026-10-21

Lane C3 (Photos). Two things only the orchestrator or C4a can do. Neither blocks the PR: without them the look-around works by touch, keys and buttons, drawn with a mesh instead of the shader.

## 1. pubspec: declare the fragment shader (orchestrator)

`app/pubspec.yaml` is not mine to edit. Under `flutter:` add

```yaml
  shaders:
    - shaders/pano_equirect.frag
```

The shader is `app/shaders/pano_equirect.frag` (original work, no third-party code). `test/features/photos/pano_shader_test.dart` is skipped until the line exists; once it does, that test renders four views with the shader and with the mesh and checks they agree. I ran it with the line added locally and it passes (four cases); the line is not in my PR.

## 2. ADR request: `MotionFacade` (C4a), so the phone can steer the view

Frozen platform paths (ADR-025). The look-around reads a `PanoMotionSource` (`app/lib/features/photos/pano/pano_providers.dart`, `panoMotionProvider`, default null). Proposed member for `app/lib/platform/`:

```dart
abstract interface class MotionFacade {
  /// Aim of the back of the phone, a few dozen readings a second while
  /// listened to; the stream ends the sensor when cancelled.
  Stream<MotionAttitude> get attitude;  // yaw: radians right of the start, pitch: radians above the horizon
  Future<bool> get available;
}
```

| | Android | iOS | macOS | Windows |
|---|---|---|---|---|
| Source | `SensorManager`, `TYPE_GAME_ROTATION_VECTOR` (no magnetometer, no permission) | `CMMotionManager.deviceMotion`, `xArbitraryZVertical` | none (`available` false) | `Inclinometer` / `OrientationSensor` where present |

Notes: no permission is needed on Android for these sensors; the rate should be `SENSOR_DELAY_GAME` or lower, only while the screen is listening (the screen cancels on pause and dispose); yaw and pitch of the camera axis (out of the back of the phone) come from the rotation matrix, with the screen's rotation applied. The consumer only needs deltas, so an arbitrary start heading is fine. Once it exists I wire `panoMotionProvider` to it (one provider override line in my lane's files); the follower, smoothing, rebase-after-drag and reduced-motion rules are already in and tested.
