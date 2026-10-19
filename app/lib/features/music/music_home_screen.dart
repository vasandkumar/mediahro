import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// Placeholder until lane C2 lands this destination (M4).
class MusicHomeScreen extends StatelessWidget {
  const MusicHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => PendingScreen(
    title: AppLocalizations.of(context).appNavMusic,
    milestone: 'M4',
  );
}
