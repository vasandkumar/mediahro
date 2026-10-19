import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/onboarding/first_run_actions.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// First run without walls (CORE-002, docs/06 §3.7): one sentence, three
/// actions, the privacy line, and the note that crash reports, usage
/// statistics and update checks are off (PRIV-001). No permission is
/// requested until an action is taken. Also the empty-library state
/// (docs/06 §9).
///
/// Callbacks default to [firstRunActionsProvider].
class FirstRunPanel extends ConsumerWidget {
  const FirstRunPanel({
    this.onOpenFile,
    this.onAddFolder,
    this.onAddServer,
    this.onPrivacy,
    super.key,
  });

  final VoidCallback? onOpenFile;
  final VoidCallback? onAddFolder;
  final VoidCallback? onAddServer;
  final VoidCallback? onPrivacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actions = ref.watch(firstRunActionsProvider);
    VoidCallback run(Future<void> Function(BuildContext) f) =>
        () => unawaited(f(context));

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KSpacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.appTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: KSpacing.s8),
              Text(
                l10n.onboardingTagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: KSpacing.s32),
              KButton(
                icon: KIcon.openFile,
                label: l10n.onboardingOpenFile,
                variant: KButtonVariant.primary,
                expand: true,
                onPressed: onOpenFile ?? run(actions.openFile),
              ),
              const SizedBox(height: KSpacing.s12),
              KButton(
                icon: KIcon.folder,
                label: l10n.onboardingAddFolder,
                expand: true,
                onPressed: onAddFolder ?? run(actions.addFolder),
              ),
              const SizedBox(height: KSpacing.s12),
              KButton(
                icon: KIcon.server,
                label: l10n.onboardingAddServer,
                expand: true,
                onPressed: onAddServer ?? run(actions.addServer),
              ),
              const SizedBox(height: KSpacing.s24),
              KButton(
                icon: KIcon.lock,
                label: l10n.onboardingPrivacyNote,
                variant: KButtonVariant.tertiary,
                onPressed: onPrivacy ?? run(actions.openPrivacy),
              ),
              const SizedBox(height: KSpacing.s4),
              Text(
                l10n.onboardingTelemetryOff,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
