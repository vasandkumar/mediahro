import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Development-build stand-in for a destination whose lane has not landed.
/// Every use is replaced by the owning lane before its milestone gate.
class PendingScreen extends StatelessWidget {
  const PendingScreen({
    required this.title,
    required this.milestone,
    super.key,
  });

  final String title;
  final String milestone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(KSpacing.s24),
          child: Text(
            l10n.appComingInMilestone(title, milestone),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
