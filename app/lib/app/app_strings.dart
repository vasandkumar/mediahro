import 'package:flutter/foundation.dart' show immutable;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The design system's strings from the app's ARB files.
@immutable
final class AppKStrings extends KStrings {
  const AppKStrings(this.l10n);

  final AppLocalizations l10n;

  @override
  String get close => l10n.appClose;
  @override
  String get back => l10n.appBack;
  @override
  String get loading => l10n.appLoading;
  @override
  String get managedByOrganisation => l10n.appManagedByOrganisation;
  @override
  String get seekBar => l10n.appSeek;
  @override
  String seekValue(String position, String duration) =>
      l10n.appSeekValue(position, duration);
  @override
  String get seekForwardLarge => l10n.appSeekForwardLarge;
  @override
  String get seekBackLarge => l10n.appSeekBackLarge;
  @override
  String get compareDivider => l10n.appCompareDivider;
  @override
  String compareItem(int index, int count) => l10n.appCompareItem(index, count);
  @override
  String percent(int value) => l10n.appPercent(value);
  @override
  String get showAdvanced => l10n.appShowAdvanced;
  @override
  String get hideAdvanced => l10n.appHideAdvanced;
  @override
  String get collapseSidebar => l10n.appCollapseSidebar;
  @override
  String get expandSidebar => l10n.appExpandSidebar;

  @override
  bool operator ==(Object other) => other is AppKStrings && other.l10n == l10n;

  @override
  int get hashCode => l10n.hashCode;
}
