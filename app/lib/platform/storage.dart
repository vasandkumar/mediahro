import 'package:meta/meta.dart';

/// Storage access (LIB-002, SYS-007, FILE-002): SAF trees + MediaStore +
/// Photo Picker (A), document picker + security-scoped bookmarks (I M),
/// pickers + known folders + Recycle Bin (W). Never MANAGE_EXTERNAL_STORAGE.
abstract interface class StorageFacade {
  Future<List<PickedFile>> pickFiles({
    Set<PickKind> kinds = const {PickKind.any},
    bool multiple = false,
  });

  /// Grants persistent access to a folder (SAF tree / bookmark / path).
  Future<FolderGrant?> pickFolder();

  /// Resolves a persisted grant to a readable URI after relaunch.
  Future<Uri?> resolveGrant(String grantId);
  Future<List<FolderGrant>> grants();
  Future<void> releaseGrant(String grantId);

  /// OS trash / recycle bin with undo where available (FILE-002).
  Future<TrashResult> moveToTrash(List<Uri> uris);
  Future<void> restoreFromTrash(TrashResult result);

  /// MediaStore observers / FSEvents / ReadDirectoryChangesW (LIB-003 watch).
  Stream<Uri> changes(String grantId);

  /// READ_MEDIA_* state (docs/07 §3.1); `notApplicable` off Android.
  Future<MediaPermission> mediaPermission(PickKind kind);
  Future<MediaPermission> requestMediaPermission(PickKind kind);
}

enum PickKind { any, video, audio, image, subtitle, playlist }

enum MediaPermission { granted, limited, denied, notApplicable }

@immutable
final class PickedFile {
  const PickedFile({required this.uri, required this.name, this.size});

  final Uri uri;
  final String name;
  final int? size;
}

@immutable
final class FolderGrant {
  const FolderGrant({
    required this.id,
    required this.uri,
    required this.displayName,
  });

  final String id;
  final Uri uri;
  final String displayName;
}

@immutable
final class TrashResult {
  const TrashResult({required this.trashed, this.undoToken});

  final List<Uri> trashed;
  final String? undoToken;
}

/// OS photo library (IMG-016, PhotosModule): PhotoKit limited/full (I M),
/// MediaStore images (A), Pictures library (W).
abstract interface class PhotoLibraryFacade {
  Future<PhotoAccess> access();
  Future<PhotoAccess> requestAccess();

  /// System UI to change a limited selection.
  Future<void> manageLimitedSelection();
  Stream<List<PhotoAsset>> assets({int pageSize = 500});

  /// Live Photo / Motion Photo video component.
  Future<Uri?> pairedVideo(String assetId);
}

enum PhotoAccess { notDetermined, limited, full, denied }

@immutable
final class PhotoAsset {
  const PhotoAsset({
    required this.id,
    required this.uri,
    required this.created,
    this.width,
    this.height,
    this.isVideo = false,
    this.isLive = false,
  });

  final String id;
  final Uri uri;
  final DateTime created;
  final int? width;
  final int? height;
  final bool isVideo;
  final bool isLive;
}
