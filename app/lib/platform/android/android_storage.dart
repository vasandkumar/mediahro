import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/storage_api.pigeon.dart';
import 'package:mediahro/platform/storage.dart';

/// [StorageFacade] on Android (SYS-007, LIB-002/003, FILE-002): SAF trees,
/// MediaStore, the Photo Picker and OS trash, in `StorageModule.kt`.
///
/// Errors: a missing document throws [PathNotFoundException], a revoked or
/// refused grant [PathAccessException], an operation the provider cannot do
/// [UnsupportedError], anything else [FileSystemException].
final class AndroidStorage implements StorageFacade {
  AndroidStorage({
    StorageHostApi? api,
    Stream<StorageChangeMsg> Function()? events,
  }) : _api = api ?? StorageHostApi(),
       _events = events ?? storageChanges;

  final StorageHostApi _api;
  final Stream<StorageChangeMsg> Function() _events;

  /// MediaStore page size: one binder transaction stays well under 1 MB.
  static const int pageSize = 500;

  /// Write chunk for [saveFile]: large enough to keep channel overhead low.
  static const int writeChunk = 256 * 1024;

  /// `changes(mediaStoreGrant)` watches MediaStore itself (LIB-003 watch for
  /// `mediastore:` sources).
  static const mediaStoreGrant = 'mediastore';

  @override
  Future<List<PickedFile>> pickFiles({
    Set<PickKind> kinds = const {PickKind.any},
    bool multiple = false,
  }) => _call(() async {
    final picked = await _api.pickFiles(kinds.map(_kind).toList(), multiple);
    return [
      for (final p in picked)
        PickedFile(uri: Uri.parse(p.uri), name: p.name, size: p.size),
    ];
  });

  @override
  Future<FolderGrant?> pickFolder() => _call(() async {
    final g = await _api.pickFolder();
    return g == null ? null : _grant(g);
  });

  @override
  Future<Uri?> resolveGrant(String grantId) => _call(() async {
    final uri = await _api.resolveGrant(grantId);
    return uri == null ? null : Uri.parse(uri);
  });

  @override
  Future<List<FolderGrant>> grants() =>
      _call(() async => (await _api.grants()).map(_grant).toList());

  @override
  Future<void> releaseGrant(String grantId) =>
      _call(() => _api.releaseGrant(grantId));

  @override
  Future<TrashResult> moveToTrash(List<Uri> uris) => _call(() async {
    final r = await _api.moveToTrash([for (final u in uris) '$u']);
    return TrashResult(
      trashed: r.trashed.map(Uri.parse).toList(),
      undoToken: r.undoToken,
    );
  });

  @override
  Future<void> restoreFromTrash(TrashResult result) => _call(
    () => _api.restoreFromTrash([
      for (final u in result.trashed) '$u',
    ], result.undoToken),
  );

  @override
  Stream<Uri> changes(String grantId) {
    StreamSubscription<StorageChangeMsg>? sub;
    late final StreamController<Uri> out;
    out = StreamController<Uri>(
      onListen: () async {
        sub = _events()
            .where((e) => e.grantId == grantId)
            .listen((e) => out.add(Uri.parse(e.uri)), onError: out.addError);
        try {
          await _call(() => _api.watch(grantId));
        } on Object catch (e, s) {
          out.addError(e, s);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        await _api.unwatch(grantId);
      },
    );
    return out.stream;
  }

  @override
  Future<MediaPermission> mediaPermission(PickKind kind) =>
      _call(() async => _permission(await _api.mediaPermission(_kind(kind))));

  @override
  Future<MediaPermission> requestMediaPermission(PickKind kind) => _call(
    () async => _permission(await _api.requestMediaPermission(_kind(kind))),
  );

  @override
  Future<ScopedAccess> startAccess(String grantId) => _call(() async {
    final uri = await _api.resolveGrant(grantId);
    if (uri == null) {
      throw PathAccessException(
        grantId,
        const OSError('grant revoked or unknown'),
        'startAccess',
      );
    }
    return _SafAccess(Uri.parse(uri));
  });

  @override
  Future<List<DocumentEntry>> listDocuments(Uri directory) => _call(
    () async => (await _api.listDocuments('$directory')).map(_entry).toList(),
  );

  @override
  Future<DocumentEntry> statDocument(Uri uri) =>
      _call(() async => _entry(await _api.statDocument('$uri')));

  @override
  Future<int> openDocumentFd(
    Uri uri, {
    DocumentMode mode = DocumentMode.read,
  }) => _call(
    () => _api.openDocumentFd('$uri', DocumentModeMsg.values[mode.index]),
  );

  @override
  Future<Uri> createDocument(
    Uri parent,
    String name, {
    String? mimeType,
    bool directory = false,
  }) => _call(
    () async => Uri.parse(
      await _api.createDocument('$parent', name, mimeType, directory),
    ),
  );

  @override
  Future<Uri> renameDocument(Uri uri, String newName) =>
      _call(() async => Uri.parse(await _api.renameDocument('$uri', newName)));

  @override
  Future<Uri> moveDocument(
    Uri uri, {
    required Uri fromParent,
    required Uri toParent,
  }) => _call(
    () async =>
        Uri.parse(await _api.moveDocument('$uri', '$fromParent', '$toParent')),
  );

  @override
  Future<void> deleteDocument(Uri uri) =>
      _call(() => _api.deleteDocument('$uri'));

  @override
  Stream<MediaStoreEntry> mediaStoreEntries({
    required Set<PickKind> kinds,
    DateTime? modifiedSince,
  }) async* {
    final k = kinds.map(_kind).toList();
    for (var offset = 0; ; offset += pageSize) {
      final page = await _call(
        () => _api.mediaStorePage(
          k,
          modifiedSince?.millisecondsSinceEpoch,
          offset,
          pageSize,
        ),
      );
      for (final e in page) {
        yield MediaStoreEntry(
          uri: Uri.parse(e.uri),
          relativePath: e.relativePath,
          name: e.name,
          size: e.size,
          modified: DateTime.fromMillisecondsSinceEpoch(e.modifiedMs),
          kind: switch (e.kind) {
            PickKindMsg.video => PickKind.video,
            PickKindMsg.subtitle => PickKind.subtitle,
            _ => PickKind.audio,
          },
        );
      }
      if (page.length < pageSize) return;
    }
  }

  @override
  Future<Uri?> saveFile({
    required String suggestedName,
    required String mimeType,
    required Stream<List<int>> content,
  }) => _call(() async {
    final target = await _api.createSaveTarget(suggestedName, mimeType);
    if (target == null) return null;
    final handle = await _api.openWrite(target);
    final buffer = BytesBuilder(copy: false);
    try {
      await for (final chunk in content) {
        buffer.add(chunk);
        if (buffer.length >= writeChunk) {
          await _api.write(handle, buffer.takeBytes());
        }
      }
      if (buffer.isNotEmpty) await _api.write(handle, buffer.takeBytes());
      await _api.closeWrite(handle, false);
    } on Object {
      await _api.closeWrite(handle, true);
      rethrow;
    }
    return Uri.parse(target);
  });

  @override
  Future<void> share(List<Uri> uris, {String? subject}) =>
      _call(() => _api.share([for (final u in uris) '$u'], subject));

  @override
  Future<bool> openWith(Uri uri) => _call(() => _api.openWith('$uri'));

  static FolderGrant _grant(FolderGrantMsg g) =>
      FolderGrant(id: g.id, uri: Uri.parse(g.uri), displayName: g.displayName);

  static DocumentEntry _entry(DocumentEntryMsg e) => DocumentEntry(
    uri: Uri.parse(e.uri),
    name: e.name,
    isDirectory: e.isDirectory,
    size: e.size,
    modified: e.modifiedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(e.modifiedMs!),
    mimeType: e.mimeType,
  );
}

/// [PhotoLibraryFacade] on Android (IMG-016): MediaStore images and videos
/// with partial access, in `PhotoLibraryModule.kt`.
final class AndroidPhotoLibrary implements PhotoLibraryFacade {
  AndroidPhotoLibrary({PhotoLibraryHostApi? api})
    : _api = api ?? PhotoLibraryHostApi();

  final PhotoLibraryHostApi _api;

  @override
  Future<PhotoAccess> access() =>
      _call(() async => PhotoAccess.values[(await _api.access()).index]);

  @override
  Future<PhotoAccess> requestAccess() =>
      _call(() async => PhotoAccess.values[(await _api.requestAccess()).index]);

  @override
  Future<void> manageLimitedSelection() => _call(_api.manageLimitedSelection);

  @override
  Stream<List<PhotoAsset>> assets({int pageSize = 500}) async* {
    for (var offset = 0; ; offset += pageSize) {
      final page = await _call(() => _api.assetsPage(offset, pageSize));
      if (page.isNotEmpty) {
        yield [
          for (final a in page)
            PhotoAsset(
              id: a.id,
              uri: Uri.parse(a.uri),
              created: DateTime.fromMillisecondsSinceEpoch(a.createdMs),
              width: a.width,
              height: a.height,
              isVideo: a.isVideo,
              isLive: a.isLive,
            ),
        ];
      }
      if (page.length < pageSize) return;
    }
  }

  @override
  Future<Uri?> pairedVideo(String assetId) => _call(() async {
    final uri = await _api.pairedVideo(assetId);
    return uri == null ? null : Uri.parse(uri);
  });
}

final class _SafAccess implements ScopedAccess {
  _SafAccess(this.root);

  @override
  final Uri root;

  // SAF grants are persisted by the OS; there is no lease to end.
  @override
  Future<void> stop() async {}
}

PickKindMsg _kind(PickKind k) => PickKindMsg.values[k.index];

MediaPermission _permission(MediaPermissionMsg m) =>
    MediaPermission.values[m.index];

/// Maps the module's error codes (`Documents.kt`) to dart:io exceptions.
Future<T> _call<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    final path = e.details is String ? e.details as String : '';
    final message = e.message ?? e.code;
    if (e.code == 'unsupported') throw UnsupportedError(message);
    throw switch (e.code) {
      'notFound' => PathNotFoundException(path, OSError(message), message),
      'permissionDenied' => PathAccessException(
        path,
        OSError(message),
        message,
      ),
      _ => FileSystemException(message, path),
    };
  }
}
