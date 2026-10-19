import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/shortcut_bindings.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Shows the keyboard cheat sheet (CORE-009, `?`).
Future<void> showShortcutCheatSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l10n.appShortcutSheetTitle,
    builder: (_) => const ShortcutCheatSheet(),
  );
}

/// Every action with its current keys, grouped by category. "Copy" puts a
/// printable plain-text version on the clipboard.
class ShortcutCheatSheet extends ConsumerWidget {
  const ShortcutCheatSheet({super.key});

  static String asText(ShortcutBindings bindings, AppLocalizations l10n) {
    final b = StringBuffer()..writeln(l10n.appShortcutSheetTitle);
    for (final c in ShortcutCategory.values) {
      final actions = bindings.actions.where((a) => a.category == c).toList();
      if (actions.isEmpty) continue;
      b
        ..writeln()
        ..writeln(c.title(l10n));
      for (final a in actions) {
        final keys = bindings
            .keysFor(a.id)
            .map((k) => keyLabel(k, bindings.platform, l10n))
            .join(' / ');
        b.writeln('  ${keys.padRight(16)} ${a.label(l10n)}');
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: KButton(
              label: l10n.appShortcutSheetCopy,
              icon: KIcon.copy,
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: asText(bindings, l10n)),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(l10n.appShortcutSheetCopied)),
                );
              },
            ),
          ),
        ),
        for (final c in ShortcutCategory.values)
          if (bindings.actions.any((a) => a.category == c)) ...[
            KSettingsHeader(title: c.title(l10n)),
            for (final a in bindings.actions.where((a) => a.category == c))
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.s16,
                    vertical: KSpacing.s4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.label(l10n),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      const SizedBox(width: KSpacing.s12),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: KSpacing.s4,
                          runSpacing: KSpacing.s4,
                          children: [
                            for (final k in bindings.keysFor(a.id))
                              KeyCap(keyLabel(k, bindings.platform, l10n)),
                            if (bindings.keysFor(a.id).isEmpty)
                              Text(
                                l10n.appShortcutUnbound,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        const SizedBox(height: KSpacing.s24),
      ],
    );
  }
}

/// A key drawn as a keycap.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(KRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpacing.s8,
          vertical: 2,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
