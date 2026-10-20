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

  // ---- Reading and writing inside grants (LIB-001/002 scans, FILE-001/002
  // browsing and file operations, NET-018 downloads into a chosen folder).

  /// Starts access to a granted folder and returns where to read it while
  /// the lease is held (LIB-002, FILE-001). iOS / macOS: resolves the
  /// security-scoped bookmark and calls `startAccessingSecurityScopedResource`
  /// (`stop()` ends it), so dart:io works on [ScopedAccess.root]. Windows:
  /// the folder path; `stop()` is a no-op. Android: the SAF tree URI, read
  /// through the `*Document*` members below.
  Future<ScopedAccess> startAccess(String grantId);

  /// Children of a directory inside a granted SAF tree
  /// (`DocumentsContract.buildChildDocumentsUriUsingTree` + one query).
  /// Android only; elsewhere throws [UnsupportedError] (use [startAccess]).
  Future<List<DocumentEntry>> listDocuments(Uri directory);

  /// One document's metadata (`DocumentsContract` query). Android only.
  Future<DocumentEntry> statDocument(Uri uri);

  /// A detached POSIX file descriptor for [uri]
  /// (`ContentResolver.openFileDescriptor` + `ParcelFileDescriptor.detachFd`).
  /// The caller owns it and closes it; B2 reads and writes with pread/pwrite
  /// through mediahro_ffi, which also gives mpv random access. Android only.
  Future<int> openDocumentFd(Uri uri, {DocumentMode mode = DocumentMode.read});

  /// Creates a file or (with [directory]) a folder under [parent]
  /// (`DocumentsContract.createDocument`); returns its document URI.
  /// Android only (FILE-002 new folder, copy/move/upload targets).
  Future<Uri> createDocument(
    Uri parent,
    String name, {
    String? mimeType,
    bool directory = false,
  });

  /// `DocumentsContract.renameDocument`; returns the new URI (FILE-002/006).
  /// Android only.
  Future<Uri> renameDocument(Uri uri, String newName);

  /// `DocumentsContract.moveDocument` (API 24+) between folders of granted
  /// trees; returns the new URI (FILE-002). Android only.
  Future<Uri> moveDocument(
    Uri uri, {
    required Uri fromParent,
    required Uri toParent,
  });

  /// `DocumentsContract.deleteDocument` (permanent; [moveToTrash] first
  /// where the provider supports trash). Android only (FILE-002).
  Future<void> deleteDocument(Uri uri);

  /// Video and audio from MediaStore (LIB-002 Android "MediaStore + SAF
  /// trees"), newest first, optionally only entries changed since
  /// [modifiedSince] (incremental rescans, LIB-003). Images stay on
  /// [PhotoLibraryFacade]. Android only; elsewhere an empty stream.
  Stream<MediaStoreEntry> mediaStoreEntries({
    required Set<PickKind> kinds,
    DateTime? modifiedSince,
  });

  // ---- Export, share, open in (FILE-002, CORE-014 backup, LIB-007
  // playlist export).

  /// Lets the user choose where to save [content] and writes it there:
  /// `ACTION_CREATE_DOCUMENT` (A), the document picker's export mode (I),
  /// `NSSavePanel` (M), `FileSavePicker` (W). Returns the saved URI, or
  /// null when cancelled.
  Future<Uri?> saveFile({
    required String suggestedName,
    required String mimeType,
    required Stream<List<int>> content,
  });

  /// The system share sheet for [uris] (FILE-002 "share"):
  /// `ACTION_SEND(_MULTIPLE)` with content URIs (A),
  /// `UIActivityViewController` (I), `NSSharingServicePicker` (M),
  /// `DataTransferManager` (W).
  Future<void> share(List<Uri> uris, {String? subject});

  /// Opens [uri] in another app the user picks (FILE-002 "open in"):
  /// `ACTION_VIEW` chooser (A), `UIDocumentInteractionController` (I),
  /// `NSWorkspace` "Open With" (M), `Launcher.LaunchFileAsync` with the app
  /// picker (W). False when no app can open it.
  Future<bool> openWith(Uri uri);
}

/// Access to a granted folder held until [stop] (see
/// [StorageFacade.startAccess]).
abstract interface class ScopedAccess {
  /// Where to read the folder while access is held: a `file:` URI on
  /// I / M / W, the SAF tree URI on A.
  Uri get root;

  /// Ends access (`stopAccessingSecurityScopedResource` on I / M).
  Future<void> stop();
}

enum DocumentMode { read, write, readWrite }

/// A file or folder inside a SAF tree (Android).
@immutable
final class DocumentEntry {
  const DocumentEntry({
    required this.uri,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
    this.mimeType,
  });

  final Uri uri;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final String? mimeType;
}

/// A MediaStore row (Android, LIB-002).
@immutable
final class MediaStoreEntry {
  const MediaStoreEntry({
    required this.uri,
    required this.relativePath,
    required this.name,
    required this.size,
    required this.modified,
    required this.kind,
  });

  /// `content://media/...` URI, readable with [StorageFacade.openDocumentFd].
  final Uri uri;

  /// `MediaStore.MediaColumns.RELATIVE_PATH`, e.g. `Movies/Holiday/`.
  final String relativePath;
  final String name;
  final int size;
  final DateTime modified;

  /// [PickKind.video] or [PickKind.audio].
  final PickKind kind;
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
