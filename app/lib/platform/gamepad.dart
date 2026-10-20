import 'package:meta/meta.dart';

/// Game controller sticks, triggers and hat (SYS-009, ADR-038). Flutter key
/// events cover controller buttons (`LogicalKeyboardKey.gameButton*`) but
/// ignore analog axes, so seek, volume and scroll by stick need this facade:
/// `MotionEvent` from SOURCE_JOYSTICK / SOURCE_GAMEPAD via `InputDevice` (A),
/// the GameController framework (I M), GameInput / XInput (W). Buttons stay
/// on Flutter key events.
abstract interface class GamepadFacade {
  /// The controllers connected now.
  Future<List<GamepadInfo>> connected();

  /// Emits when a controller is added or removed.
  Stream<GamepadChange> get connections;

  /// Analog and hat input from every connected controller. The native side
  /// applies the dead zone, so values near rest arrive as 0.
  Stream<GamepadAxisEvent> get axes;
}

/// An analog control. Sticks and the hat are -1..1; triggers are 0..1.
/// Positive Y is down, as on the screen.
enum GamepadAxis {
  leftX,
  leftY,
  rightX,
  rightY,
  leftTrigger,
  rightTrigger,
  hatX,
  hatY,
}

@immutable
final class GamepadInfo {
  const GamepadInfo({
    required this.id,
    required this.name,
    this.vendorId,
    this.productId,
  });

  /// Stable for as long as the controller stays connected.
  final int id;

  /// The controller's own name, used to choose on-screen glyph sets.
  final String name;
  final int? vendorId;
  final int? productId;
}

enum GamepadConnectionKind { added, removed }

@immutable
final class GamepadChange {
  const GamepadChange({required this.kind, required this.gamepad});

  final GamepadConnectionKind kind;
  final GamepadInfo gamepad;
}

@immutable
final class GamepadAxisEvent {
  const GamepadAxisEvent({
    required this.deviceId,
    required this.axis,
    required this.value,
  });

  /// The [GamepadInfo.id] of the controller that produced this.
  final int deviceId;
  final GamepadAxis axis;

  /// -1..1 for sticks and the hat, 0..1 for triggers.
  final double value;
}

/// Default for platforms and tests with no native implementation (ADR-038):
/// no controllers and no axis events; buttons still work through key events.
final class UnsupportedGamepad implements GamepadFacade {
  const UnsupportedGamepad();

  @override
  Future<List<GamepadInfo>> connected() async => const <GamepadInfo>[];

  @override
  Stream<GamepadChange> get connections => const Stream<GamepadChange>.empty();

  @override
  Stream<GamepadAxisEvent> get axes => const Stream<GamepadAxisEvent>.empty();
}
