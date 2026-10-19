import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/setting_entry_tile.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_transfer.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Settings (CORE-006, docs/06 §3.5): searchable, grouped by section, list
/// and detail side by side on wide windows.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.section, super.key});

  /// Open section (from `/settings/<section>`); null shows the list.
  final SettingsSectionId? section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _build(context, wide: KListDetail.sideBySide(constraints.maxWidth)),
  );

  Widget _build(BuildContext context, {required bool wide}) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(settingsRegistryProvider);
    final sections = registry.sections;
    final selected =
        widget.section ??
        (wide && sections.isNotEmpty ? sections.first.id : null);

    if (!wide && widget.section != null) {
      return SettingsSectionPage(section: widget.section!);
    }

    final list = _SettingsList(
      query: _query,
      selected: wide ? selected : null,
      onChanged: () => setState(() {}),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appNavSettings),
        actions: const [SettingsTransferMenu()],
      ),
      body: KListDetail(
        list: list,
        detail: selected == null
            ? null
            : SettingsSectionBody(key: ValueKey(selected), section: selected),
      ),
    );
  }
}

class _SettingsList extends ConsumerWidget {
  const _SettingsList({
    required this.query,
    required this.selected,
    required this.onChanged,
  });

  final TextEditingController query;
  final SettingsSectionId? selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registry = ref.watch(settingsRegistryProvider);
    final theme = Theme.of(context);
    final q = query.text.trim();
    final hits = q.isEmpty ? null : registry.search(q, l10n);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.s16,
            KSpacing.s8,
            KSpacing.s16,
            KSpacing.s8,
          ),
          child: TextField(
            controller: query,
            onChanged: (_) => onChanged(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: Icon(KIcon.search.resolve(theme.family)),
              hintText: l10n.settingsSearchHint,
              border: const OutlineInputBorder(),
              suffixIcon: q.isEmpty
                  ? null
                  : KIconButton(
                      icon: KIcon.close,
                      label: l10n.settingsSearchClear,
                      onPressed: () {
                        query.clear();
                        onChanged();
                      },
                    ),
            ),
          ),
        ),
        if (hits == null)
          for (final s in registry.sections)
            KRow(
              key: ValueKey('section.${s.id.name}'),
              title: s.id.title(l10n),
              subtitle: s.id.description(l10n),
              leading: Icon(s.id.icon.resolve(theme.family)),
              selected: s.id == selected,
              onTap: () => context.go('/settings/${s.id.name}'),
            )
        else if (hits.isEmpty)
          Padding(
            padding: const EdgeInsets.all(KSpacing.s24),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.settingsSearchNoResults(q),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
              child: Text(
                l10n.settingsSearchResults(hits.length),
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
          for (final (i, h) in hits.indexed) ...[
            if (i == 0 || hits[i - 1].section != h.section)
              KSettingsHeader(title: h.section.title(l10n)),
            SettingEntryTile(entry: h.entry, highlight: q),
          ],
        ],
      ],
    );
  }
}

/// A section on its own page (compact windows).
class SettingsSectionPage extends ConsumerWidget {
  const SettingsSectionPage({required this.section, super.key});

  final SettingsSectionId section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(section.title(l10n))),
      body: SettingsSectionBody(section: section, showHeader: false),
    );
  }
}

/// Rows of one section, Advanced rows collapsed, and "Reset section".
class SettingsSectionBody extends ConsumerWidget {
  const SettingsSectionBody({
    required this.section,
    this.showHeader = true,
    super.key,
  });

  final SettingsSectionId section;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(settingsRegistryProvider).section(section);
    final theme = Theme.of(context);
    if (view == null) {
      return KEmptyState(message: l10n.settingsSectionEmpty);
    }
    return ListView(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              KSpacing.s16,
              KSpacing.s16,
              KSpacing.s8,
              0,
            ),
            child: Semantics(
              header: true,
              child: Text(
                section.title(l10n),
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ),
        for (final e in view.basic) SettingEntryTile(entry: e),
        if (view.advanced.isNotEmpty)
          KAdvancedGroup(
            children: [
              for (final e in view.advanced) SettingEntryTile(entry: e),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(KSpacing.s16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ResetSectionButton(section: section),
          ),
        ),
      ],
    );
  }
}

class _ResetSectionButton extends ConsumerWidget {
  const _ResetSectionButton({required this.section});

  final SettingsSectionId section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final name = section.title(l10n);
    return KButton(
      label: l10n.settingsResetSection,
      variant: KButtonVariant.tertiary,
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l10n.settingsResetSectionTitle(name)),
            content: Text(l10n.settingsResetSectionBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l10n.settingsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l10n.settingsReset),
              ),
            ],
          ),
        );
        if (ok ?? false) {
          ref.read(settingsStoreProvider).resetSection(section.name);
        }
      },
    );
  }
}
