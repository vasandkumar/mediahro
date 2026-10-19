import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// Placeholder until lane B2 lands this destination (M2).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => PendingScreen(
    title: AppLocalizations.of(context).appNavSearch,
    milestone: 'M2',
  );
}
