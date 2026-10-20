import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/features/photos/info/metadata_edit_service.dart';
import 'package:mediahro/features/photos/organise/photo_organiser.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';

/// Copies ratings, colour labels and tags from the library into the photo
/// files (XMP: `xmp:Rating`, `xmp:Label`, `dc:subject`) so other programs
/// see them (IMG-005). Off unless the user turned it on in Settings; videos
/// are left alone. A format that cannot hold XMP gets a sidecar.
final class OrganisationWriteBack {
  OrganisationWriteBack({
    required this.editor,
    required this.organiser,
    required this.enabled,
  });

  final MetadataEditor editor;
  final PhotoOrganiser organiser;
  final bool Function() enabled;

  /// Photos whose file could not be updated by the last call.
  int lastFailures = 0;

  Future<int> rating(List<PhotoEntry> photos, int stars) =>
      _each(photos, (_) async => ImageMetadataEdit(rating: stars));

  Future<int> label(List<PhotoEntry> photos, LabelColor? color) => _each(
    photos,
    (_) async => ImageMetadataEdit(label: color == null ? '' : xmpLabel(color)),
  );

  /// Writes each photo's complete tag list, so removed tags go too.
  Future<int> tags(List<PhotoEntry> photos) => _each(
    photos,
    (p) async => ImageMetadataEdit(keywords: await organiser.tagsOf(p.id)),
  );

  /// Returns how many files could not be updated; 0 when off or all went
  /// well. One bad file does not stop the others.
  Future<int> _each(
    List<PhotoEntry> photos,
    Future<ImageMetadataEdit> Function(PhotoEntry) edit,
  ) async {
    if (!enabled()) return 0;
    var failed = 0;
    for (final p in photos) {
      if (p.isVideo) continue;
      try {
        await editor.save(p, await edit(p));
      } on Object {
        failed++;
      }
    }
    return lastFailures = failed;
  }
}

/// The spelling photo programs use in `xmp:Label` (Lightroom: Red, Yellow,
/// Green, Blue, Purple; Bridge adds Orange).
String xmpLabel(LabelColor c) => switch (c) {
  LabelColor.red => 'Red',
  LabelColor.orange => 'Orange',
  LabelColor.yellow => 'Yellow',
  LabelColor.green => 'Green',
  LabelColor.blue => 'Blue',
  LabelColor.purple => 'Purple',
  LabelColor.grey => 'Grey',
};
