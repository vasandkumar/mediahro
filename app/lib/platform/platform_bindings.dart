import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/platform/android/bindings.dart' as android;
import 'package:mediahro/platform/apple/bindings.dart' as apple;
import 'package:mediahro/platform/windows/bindings.dart' as windows;

/// The platform's facade implementations (docs/05 §8, ADR-025). Each
/// platform sub-lane of C4 owns its own `bindings.dart`; this file only
/// selects one and is the orchestrator's.
List<Override> platformOverrides() {
  if (Platform.isAndroid) return android.overrides();
  if (Platform.isIOS || Platform.isMacOS) return apple.overrides();
  if (Platform.isWindows) return windows.overrides();
  return const [];
}
