import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shell's mini-player slot (docs/06 §3.2). Lane C2 overrides this
/// with a builder returning its `KMiniPlayer` while something plays, or
/// null to hide the slot. The shell shows it above the navigation bar on
/// phones and under the content on wide windows; full-screen player routes
/// live outside the shell, so it never covers video.
final miniPlayerSlotProvider = Provider<WidgetBuilder?>((ref) => null);
