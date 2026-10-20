import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// Photo settings (lane C3). The orchestrator lists
/// [photoSettingsContributions] in the app root.
abstract final class PhotoSettings {
  /// Save ratings, colour labels and tags into the photo files (XMP) as well
  /// as the library, so other apps see them (IMG-005, opt-in: it rewrites
  /// files).
  static final SettingKey<bool> writeOrganisation = SettingKey.boolean(
    'photos.writeOrganisationToFiles',
    defaultValue: false,
  );
}

final photoSettingsContributions = [
  SettingsContribution(
    section: SettingsSectionId.photos,
    entries: [
      ToggleSetting(
        key: PhotoSettings.writeOrganisation,
        title: (l) => l.photosSettingsWriteMetadata,
        description: (l) => l.photosSettingsWriteMetadataHint,
      ),
    ],
  ),
];
