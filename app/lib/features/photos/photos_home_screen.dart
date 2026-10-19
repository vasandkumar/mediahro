import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/ui/pending_screen.dart';

/// Placeholder until lane C3 lands this destination (M5).
class PhotosHomeScreen extends StatelessWidget {
  const PhotosHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => PendingScreen(
    title: AppLocalizations.of(context).appNavPhotos,
    milestone: 'M5',
  );
}
