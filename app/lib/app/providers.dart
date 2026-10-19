import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/flags.dart';

/// Overridden in tests and by the B2B managed-config overlay.
final capabilitiesProvider = Provider<Capabilities>(
  (ref) => Capabilities.current(),
);

final flagsProvider = Provider<Flags>((ref) => Flags.fromEnvironment());
