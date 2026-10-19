import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Renders one [SettingEntry] with the design system's settings row.
class SettingEntryTile extends ConsumerWidget {
  const SettingEntryTile({required this.entry, this.highlight, super.key});

  final SettingEntry entry;
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final store = ref.watch(settingsStoreProvider);
    final managed = entry.keys.any(settings.isManaged);
    final title = entry.title(l10n);
    final description = entry.description(l10n);

    return switch (entry) {
      ToggleSetting(:final key) => KSettingsRow.toggle(
        key: ValueKey(entry.id),
        title: title,
        description: description,
        value: settings.get(key),
        managed: managed,
        highlight: highlight,
        onChanged: (v) => store.set(key, v),
      ),
      final ChoiceSetting<Object> c => KSettingsRow.value(
        key: ValueKey(entry.id),
        title: title,
        description: description,
        valueLabel: c.currentLabel(settings, l10n),
        managed: managed,
        highlight: highlight,
        onTap: () => KSheet.show<void>(
          context,
          title: title,
          builder: (sheetContext) => Consumer(
            builder: (context, ref, _) {
              final s = ref.watch(settingsProvider);
              return Column(
                children: [
                  for (final (label, selected, select) in c.choices(s, l10n))
                    KRow(
                      title: label,
                      selected: selected,
                      onTap: () {
                        select(store);
                        Navigator.of(sheetContext).maybePop();
                      },
                    ),
                  const SizedBox(height: KSpacing.s16),
                ],
              );
            },
          ),
        ),
      ),
      SliderSetting(
        :final key,
        :final min,
        :final max,
        :final divisions,
        :final valueLabel,
      ) =>
        KSettingsRow.custom(
          key: ValueKey(entry.id),
          title: title,
          description: description,
          managed: managed,
          highlight: highlight,
          trailing: Slider(
            value: settings.get(key).clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel(l10n, settings.get(key)),
            semanticFormatterCallback: (v) => valueLabel(l10n, v),
            onChanged: (v) => store.set(key, v),
          ),
        ),
      LinkSetting(:final location) => KSettingsRow.navigation(
        key: ValueKey(entry.id),
        title: title,
        description: description,
        managed: managed,
        highlight: highlight,
        onTap: () => context.push(location),
      ),
      CustomSetting(:final builder) => KeyedSubtree(
        key: ValueKey(entry.id),
        child: builder(context, highlight),
      ),
    };
  }
}
