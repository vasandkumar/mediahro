import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/app/shortcuts/cheat_sheet.dart';
import 'package:mediahro/app/shortcuts/key_spec.dart';
import 'package:mediahro/app/shortcuts/shortcut_bindings.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Remapping UI (CORE-009): every action, its keys, change / remove /
/// restore, conflict warnings, reset all, and the cheat sheet.
class ShortcutEditor extends ConsumerWidget {
  const ShortcutEditor({this.highlight, super.key});

  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final store = ref.watch(settingsStoreProvider);
    final theme = Theme.of(context);
    final conflicts = bindings.conflicts;
    final term = SettingsRegistry.fold(highlight ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(KSpacing.s16),
          child: Wrap(
            spacing: KSpacing.s8,
            runSpacing: KSpacing.s8,
            children: [
              KButton(
                label: l10n.appShortcutSheetTitle,
                icon: KIcon.keyboard,
                onPressed: () => showShortcutCheatSheet(context),
              ),
              KButton(
                label: l10n.settingsShortcutsResetAll,
                icon: KIcon.reset,
                variant: KButtonVariant.tertiary,
                onPressed: () {
                  for (final a in bindings.actions) {
                    setShortcut(store, a, null);
                  }
                },
              ),
            ],
          ),
        ),
        if (conflicts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    KIcon.warning.resolve(theme.family),
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: KSpacing.s8),
                  Expanded(
                    child: Text(
                      l10n.settingsShortcutsConflicts(conflicts.length),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final c in ShortcutCategory.values)
          if (bindings.actions.any((a) => a.category == c)) ...[
            KSettingsHeader(title: c.title(l10n)),
            for (final a in bindings.actions.where((a) => a.category == c))
              if (term.isEmpty ||
                  SettingsRegistry.fold(a.label(l10n)).contains(term) ||
                  SettingsRegistry.fold(c.title(l10n)).contains(term))
                KSettingsRow.value(
                  title: a.label(l10n),
                  description: bindings.isDefault(a)
                      ? l10n.settingsShortcutDefault
                      : l10n.settingsShortcutCustom,
                  valueLabel: bindings.keysFor(a.id).isEmpty
                      ? l10n.appShortcutUnbound
                      : bindings
                            .keysFor(a.id)
                            .map((k) => keyLabel(k, bindings.platform, l10n))
                            .join(' / '),
                  onTap: () => _edit(context, ref, a),
                ),
          ],
        const SizedBox(height: KSpacing.s24),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ShortcutAction action,
  ) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _CaptureDialog(action: action),
    );
    if (result == null) return;
    final store = ref.read(settingsStoreProvider);
    final bindings = ref.read(shortcutBindingsProvider);
    switch (result) {
      case _Restore():
        setShortcut(store, action, null);
      case _Remove():
        setShortcut(store, action, const []);
      case _Assign(:final spec):
        for (final other in bindings.clashesWith(action, spec)) {
          setShortcut(store, other, [
            for (final k in bindings.keysFor(other.id))
              if (k != spec) k,
          ]);
        }
        setShortcut(store, action, [spec]);
    }
  }
}

sealed class _EditResult {
  const _EditResult();
}

final class _Restore extends _EditResult {
  const _Restore();
}

final class _Remove extends _EditResult {
  const _Remove();
}

final class _Assign extends _EditResult {
  const _Assign(this.spec);

  final KeySpec spec;
}

/// "Press the new shortcut": captures the next non-modifier key, warns when
/// it is taken by another action and asks before replacing.
class _CaptureDialog extends ConsumerStatefulWidget {
  const _CaptureDialog({required this.action});

  final ShortcutAction action;

  @override
  ConsumerState<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends ConsumerState<_CaptureDialog> {
  KeySpec? _captured;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final platform = ref.read(capabilitiesProvider).platform;
    final spec = KeySpec.fromEvent(event, platform);
    if (spec == null) return KeyEventResult.handled;
    setState(() => _captured = spec);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final platform = bindings.platform;
    final clashes = _captured == null
        ? const <ShortcutAction>[]
        : bindings.clashesWith(widget.action, _captured!);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.action.label(l10n)),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsShortcutPress),
            const SizedBox(height: KSpacing.s16),
            Semantics(
              liveRegion: true,
              child: _captured == null
                  ? Text(
                      l10n.settingsShortcutWaiting,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : KeyCap(keyLabel(_captured!, platform, l10n)),
            ),
            if (clashes.isNotEmpty) ...[
              const SizedBox(height: KSpacing.s12),
              Text(
                l10n.settingsShortcutTaken(
                  clashes.map((a) => a.label(l10n)).join(', '),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _Restore()),
          child: Text(l10n.settingsShortcutRestore),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const _Remove()),
          child: Text(l10n.settingsShortcutRemove),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.settingsCancel),
        ),
        FilledButton(
          onPressed: _captured == null
              ? null
              : () => Navigator.pop(context, _Assign(_captured!)),
          child: Text(
            clashes.isEmpty
                ? l10n.settingsShortcutAssign
                : l10n.settingsShortcutReplace,
          ),
        ),
      ],
    );
  }
}
