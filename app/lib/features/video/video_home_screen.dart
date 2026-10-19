import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/onboarding/first_run_panel.dart';

/// Video home (docs/06 §2). With an empty library it is the first-run
/// screen (CORE-002); lane C1 adds the rows once the library exists.
class VideoHomeScreen extends StatelessWidget {
  const VideoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).appNavVideo)),
    body: const FirstRunPanel(),
  );
}
