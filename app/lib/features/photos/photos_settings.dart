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

  /// The share sheet starts with "remove location and camera info" ticked
  /// (IMG-006, IMG-015; opt-in).
  static final SettingKey<bool> stripOnShare = SettingKey.boolean(
    'photos.stripOnShare',
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
      ToggleSetting(
        key: PhotoSettings.stripOnShare,
        title: (l) => l.photosSettingsStripOnShare,
        description: (l) => l.photosSettingsStripOnShareHint,
      ),
    ],
  ),
];
