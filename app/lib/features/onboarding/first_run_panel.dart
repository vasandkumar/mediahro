import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// First run without walls (CORE-002, docs/06 §3.7): one sentence, three
/// actions, the privacy line. No permission is requested until an action is
/// taken. Also used as the empty-library state (docs/06 §9).
class FirstRunPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final family = platformFamilyFor(defaultTargetPlatform);
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
              _Action(
                icon: KIcon.openFile.resolve(family),
                label: l10n.onboardingOpenFile,
                onPressed: onOpenFile,
                primary: true,
              ),
              const SizedBox(height: KSpacing.s12),
              _Action(
                icon: KIcon.folder.resolve(family),
                label: l10n.onboardingAddFolder,
                onPressed: onAddFolder,
              ),
              const SizedBox(height: KSpacing.s12),
              _Action(
                icon: KIcon.server.resolve(family),
                label: l10n.onboardingAddServer,
                onPressed: onAddServer,
              ),
              const SizedBox(height: KSpacing.s24),
              TextButton.icon(
                onPressed: onPrivacy,
                icon: Icon(KIcon.lock.resolve(family), size: 18),
                label: Text(
                  l10n.onboardingPrivacyNote,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const size = Size.fromHeight(KTarget.min + KSpacing.s4);
    return primary
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(minimumSize: size),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: OutlinedButton.styleFrom(minimumSize: size),
          );
  }
}
