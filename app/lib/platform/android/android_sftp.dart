import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/sftp_api.pigeon.dart';
import 'package:mediahro/platform/secure_transport.dart';

/// [SftpFacade] on Android (NET-004, ADR-017): sshj over the platform JCA
/// (`SftpModule.kt`). Secrets stay native: the endpoint carries only their
/// secure-storage references.
///
/// When the endpoint's confirmed host key is missing or differs, the
/// session ends after the key exchange without sending any credential; its
/// [SftpSession.hostKeySha256] is the key to show, and every operation
/// throws until the user confirms it and connects again.
final class AndroidSftp implements SftpFacade {
  AndroidSftp({SftpHostApi? api}) : _api = api ?? SftpHostApi();

  final SftpHostApi _api;

  @override
  Future<SftpSession> connect(SftpEndpoint endpoint) async {
    final s = await _guard(
      () => _api.connect(
        SftpEndpointMsg(
          host: endpoint.host,
          port: endpoint.port,
          username: endpoint.username,
          passwordSecretRef: endpoint.passwordSecretRef,
          privateKeySecretRef: endpoint.privateKeySecretRef,
          keyPassphraseSecretRef: endpoint.keyPassphraseSecretRef,
          knownHostKeySha256: endpoint.knownHostKeySha256,
        ),
      ),
    );
    return _AndroidSftpSession(_api, s);
  }
}

final class _AndroidSftpSession implements SftpSession {
  _AndroidSftpSession(this._api, this._msg);

  final SftpHostApi _api;
  final SftpSessionMsg _msg;

  String get _id => _msg.id;

  @override
  String get hostKeySha256 => _msg.hostKeySha256;

  @override
  Future<List<SftpEntry>> list(String path) async =>
      (await _guard(() => _api.list(_id, path))).map(_entry).toList();

  @override
  Future<SftpEntry> stat(String path) async =>
      _entry(await _guard(() => _api.stat(_id, path)));

  @override
  Future<Uint8List> read(String path, int offset, int length) =>
      _guard(() => _api.read(_id, path, offset, length));

  @override
  Future<void> rename(String from, String to) =>
      _guard(() => _api.rename(_id, from, to));

  @override
  Future<void> delete(String path) => _guard(() => _api.delete(_id, path));

  @override
  Future<void> mkdir(String path) => _guard(() => _api.mkdir(_id, path));

  @override
  Future<SftpWriteSink> openWrite(String path, {bool truncate = true}) async =>
      _Sink(_api, await _guard(() => _api.openWrite(_id, path, truncate)));

  @override
  Future<void> close() => _guard(() => _api.close(_id));

  static SftpEntry _entry(SftpEntryMsg e) => SftpEntry(
    path: e.path,
    isDirectory: e.isDirectory,
    size: e.size,
    modified: e.modifiedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(e.modifiedMs!),
  );
}

final class _Sink implements SftpWriteSink {
  _Sink(this._api, this._id);

  final SftpHostApi _api;
  final String _id;

  @override
  Future<void> write(Uint8List data) => _guard(() => _api.write(_id, data));

  @override
  Future<void> close() => _guard(() => _api.closeWrite(_id, false));

  @override
  Future<void> abort() => _guard(() => _api.closeWrite(_id, true));
}

/// Module error codes as the exceptions B2's SFTP file system maps:
/// unreachable hosts as [io.SocketException], timeouts as
/// [TimeoutException], missing paths as [io.PathNotFoundException]; the
/// rest stay [PlatformException] with their code (`authFailed`,
/// `notAuthenticated`, `permissionDenied`, `missingSecret`, `unsupportedKey`,
/// `keyPassphrase`).
Future<T> _guard<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    final message = e.message ?? e.code;
    switch (e.code) {
      case 'connectFailed' || 'closed':
        throw io.SocketException(message);
      case 'timeout':
        throw TimeoutException(message);
      case 'notFound':
        throw io.PathNotFoundException('', io.OSError(message), message);
    }
    rethrow;
  }
}
