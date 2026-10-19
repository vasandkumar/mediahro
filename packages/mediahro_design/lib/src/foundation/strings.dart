import 'package:flutter/widgets.dart';

/// Strings the component library needs for labels and state announcements
/// (docs/06 §7). The design package has no ARB files of its own: the app
/// implements this from its localisations and installs it with
/// [KStringsScope] above every screen.
abstract class KStrings {
  const KStrings();

  /// Closes a sheet or dialog.
  String get close;

  /// Navigates back.
  String get back;

  /// Announced for skeleton placeholders.
  String get loading;

  /// Secondary text on rows locked by managed configuration.
  String get managedByOrganisation;

  /// Name of a seek bar ("Seek").
  String get seekBar;

  /// Spoken value of a seek bar: "1:23 of 45:00".
  String seekValue(String position, String duration);

  /// Custom accessibility actions on the seek bar.
  String get seekForwardLarge;
  String get seekBackLarge;

  /// Name of the comparison divider in `KCompareView`'s swipe mode.
  String get compareDivider;

  /// "Image 1 of 4" for compare panels.
  String compareItem(int index, int count);

  /// Spoken percentage: "40 %".
  String percent(int value);

  /// Expands the collapsed advanced group in a settings section.
  String get showAdvanced;
  String get hideAdvanced;

  /// Collapses or expands the sidebar.
  String get collapseSidebar;
  String get expandSidebar;

  static KStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<KStringsScope>();
    assert(
      scope != null,
      'No KStringsScope found. The app installs one in MediahroApp; tests use '
      'package:mediahro_design/testing.dart.',
    );
    return scope!.strings;
  }
}

/// Provides [KStrings] to the component library.
class KStringsScope extends InheritedWidget {
  const KStringsScope({required this.strings, required super.child, super.key});

  final KStrings strings;

  @override
  bool updateShouldNotify(KStringsScope oldWidget) =>
      strings != oldWidget.strings;
}
