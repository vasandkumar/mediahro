import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// Placeholder until lane B3 lands this destination (M2).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => PendingScreen(
    title: AppLocalizations.of(context).appNavSettings,
    milestone: 'M2',
  );
}
