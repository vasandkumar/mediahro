import 'package:flutter_riverpod/misc.dart' show Override;

/// Facade implementations for iOS and macOS (Swift) through Pigeon files in app/pigeons/apple/
/// (lane C4b, ADR-025). Each entry overrides one provider from
/// `platform_facades.dart`; a facade not yet implemented stays unavailable
/// and its callers show "Not available on this device".
List<Override> overrides() => const [];
