import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// Placeholder until lane B2 lands this destination (M2).
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => PendingScreen(
    title: AppLocalizations.of(context).appNavSources,
    milestone: 'M2',
  );
}
