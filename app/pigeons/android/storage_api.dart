// Pigeon messages for StorageFacade and PhotoLibraryFacade on Android
// (lane C4a, SYS-007, LIB-002, FILE-002, IMG-016).
//
//   dart run pigeon --input pigeons/android/storage_api.dart   (from app/)
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/storage_api.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/StorageApi.g.kt',
    kotlinOptions: KotlinOptions(
      // The shared error and event-channel classes live here; the other
      // Android Pigeon files set includeErrorClass / includeSharedClasses
      // to false so all of them share one Kotlin package.
      package: 'com.mediahro.mediahro.pigeon',
    ),
    dartPackageName: 'mediahro',
  ),
)
enum PickKindMsg { any, video, audio, image, subtitle, playlist }

enum DocumentModeMsg { read, write, readWrite }

enum MediaPermissionMsg { granted, limited, denied, notApplicable }

enum PhotoAccessMsg { notDetermined, limited, full, denied }

class PickedFileMsg {
  PickedFileMsg(this.uri, this.name, this.size);
  String uri;
  String name;
  int? size;
}

class FolderGrantMsg {
  FolderGrantMsg(this.id, this.uri, this.displayName);
  String id;
  String uri;
  String displayName;
}

class TrashResultMsg {
  TrashResultMsg(this.trashed, this.undoToken);
  List<String> trashed;
  String? undoToken;
}

class DocumentEntryMsg {
  DocumentEntryMsg(
    this.uri,
    this.name,
    this.isDirectory,
    this.size,
    this.modifiedMs,
    this.mimeType,
  );
  String uri;
  String name;
  bool isDirectory;
  int? size;
  int? modifiedMs;
  String? mimeType;
}

class MediaStoreEntryMsg {
  MediaStoreEntryMsg(
    this.uri,
    this.relativePath,
    this.name,
    this.size,
    this.modifiedMs,
    this.kind,
  );
  String uri;
  String relativePath;
  String name;
  int size;
  int modifiedMs;
  PickKindMsg kind;
}

class PhotoAssetMsg {
  PhotoAssetMsg(
    this.id,
    this.uri,
    this.createdMs,
    this.width,
    this.height,
    this.isVideo,
    this.isLive,
  );
  String id;
  String uri;
  int createdMs;
  int? width;
  int? height;
  bool isVideo;
  bool isLive;
}

/// A change under a watched grant (or `mediastore` for MediaStore).
class StorageChangeMsg {
  StorageChangeMsg(this.grantId, this.uri);
  String grantId;
  String uri;
}

@HostApi()
abstract class StorageHostApi {
  @async
  List<PickedFileMsg> pickFiles(List<PickKindMsg> kinds, bool multiple);

  @async
  FolderGrantMsg? pickFolder();

  String? resolveGrant(String grantId);
  List<FolderGrantMsg> grants();
  void releaseGrant(String grantId);

  @async
  TrashResultMsg moveToTrash(List<String> uris);

  @async
  void restoreFromTrash(List<String> uris, String? undoToken);

  void watch(String grantId);
  void unwatch(String grantId);

  MediaPermissionMsg mediaPermission(PickKindMsg kind);

  @async
  MediaPermissionMsg requestMediaPermission(PickKindMsg kind);

  @async
  List<DocumentEntryMsg> listDocuments(String directory);

  @async
  DocumentEntryMsg statDocument(String uri);

  @async
  int openDocumentFd(String uri, DocumentModeMsg mode);

  @async
  String createDocument(
    String parent,
    String name,
    String? mimeType,
    bool directory,
  );

  @async
  String renameDocument(String uri, String newName);

  @async
  String moveDocument(String uri, String fromParent, String toParent);

  @async
  void deleteDocument(String uri);

  /// One page of MediaStore video/audio, newest first.
  @async
  List<MediaStoreEntryMsg> mediaStorePage(
    List<PickKindMsg> kinds,
    int? modifiedSinceMs,
    int offset,
    int limit,
  );

  /// `ACTION_CREATE_DOCUMENT`; null when cancelled.
  @async
  String? createSaveTarget(String suggestedName, String mimeType);

  /// Opens [uri] for writing; returns a write-session handle.
  @async
  int openWrite(String uri);

  @async
  void write(int handle, Uint8List data);

  @async
  void closeWrite(int handle, bool abort);

  @async
  void share(List<String> uris, String? subject);

  @async
  bool openWith(String uri);
}

@HostApi()
abstract class PhotoLibraryHostApi {
  PhotoAccessMsg access();

  @async
  PhotoAccessMsg requestAccess();

  @async
  void manageLimitedSelection();

  /// One page of MediaStore images and videos, newest first.
  @async
  List<PhotoAssetMsg> assetsPage(int offset, int limit);

  /// The Motion Photo video, extracted to the cache; null if none.
  @async
  String? pairedVideo(String assetId);
}

@EventChannelApi()
abstract class StorageEventsApi {
  StorageChangeMsg storageChanges();
}
