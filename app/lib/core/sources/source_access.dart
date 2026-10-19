import 'dart:convert';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/scanner/scan_run.dart';
import 'package:mediahro/platform/security.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// Everything needed to open a source, as plain values that can cross
/// isolates (the secret is resolved from SecureStorageFacade on the main
/// isolate and lives only in memory, PRIV-006).
@immutable
final class SourceSpec {
  const SourceSpec({
    required this.kind,
    required this.root,
    this.options = const {},
    this.userName,
    this.secret,
  });

  final SourceKind kind;
  final Uri root;
  final Map<String, String> options;
  final String? userName;
  final String? secret;
}

/// Resolved access to a source: its root and a factory for its file system.
@immutable
final class SourceAccess {
  const SourceAccess(this.spec, this.fileSystem);

  final SourceSpec spec;

  /// Creates the file system; safe to call inside a scan isolate.
  final FileSystemFactory fileSystem;

  Uri get root => spec.root;
}

/// Builds a file system for a [SourceSpec] (one entry per protocol).
typedef FileSystemBuilder = VirtualFileSystem Function(SourceSpec spec);

/// Turns a `source` row into [SourceAccess] (grant and credential lookup).
abstract interface class SourceResolver {
  Future<SourceAccess> resolve(SourceRow source);
}

final class SourceUnavailable implements Exception {
  const SourceUnavailable(this.sourceId, this.reason);

  final int sourceId;
  final String reason;

  @override
  String toString() => 'SourceUnavailable($sourceId: $reason)';
}

/// Default resolver: storage grants for local sources (SAF tree, bookmark),
/// SecureStorageFacade for credentials, [builders] per protocol.
final class DefaultSourceResolver implements SourceResolver {
  DefaultSourceResolver({
    required this.builders,
    this.storage,
    this.secureStorage,
  });

  final Map<SourceKind, FileSystemBuilder> builders;
  final StorageFacade? storage;
  final SecureStorageFacade? secureStorage;

  @override
  Future<SourceAccess> resolve(SourceRow source) async {
    var root = Uri.parse(source.rootUri);
    final grant = source.grantId;
    if (grant != null) {
      final s = storage;
      final resolved = s == null ? null : await s.resolveGrant(grant);
      if (resolved == null) {
        throw SourceUnavailable(source.id, 'folder access was revoked');
      }
      root = resolved;
    }
    String? secret;
    String? user;
    final key = source.credentialKey;
    if (key != null) {
      final raw = await secureStorage?.read(key);
      if (raw != null) {
        final c = StoredCredential.decode(raw);
        user = c.userName;
        secret = c.secret;
      }
    }
    final builder = builders[source.kind];
    if (builder == null) {
      throw SourceUnavailable(source.id, 'no client for ${source.kind.name}');
    }
    final spec = SourceSpec(
      kind: source.kind,
      root: root,
      options: decodeOptions(source.options),
      userName: user,
      secret: secret,
    );
    return SourceAccess(spec, () => builder(spec));
  }
}

/// A credential as stored in SecureStorageFacade under `sources.credentialKey`.
@immutable
final class StoredCredential {
  const StoredCredential({this.userName, this.secret, this.kind = 'password'});

  factory StoredCredential.decode(String raw) {
    final m = jsonDecode(raw) as Map<String, Object?>;
    return StoredCredential(
      userName: m['user'] as String?,
      secret: m['secret'] as String?,
      kind: m['kind'] as String? ?? 'password',
    );
  }

  final String? userName;

  /// Password, SFTP private key (PEM), or OAuth refresh token.
  final String? secret;

  /// `password`, `sshKey`, `oauth`, `guest`.
  final String kind;

  String encode() =>
      jsonEncode({'user': userName, 'secret': secret, 'kind': kind});
}

Map<String, String> decodeOptions(String json) {
  final m = jsonDecode(json);
  if (m is! Map<String, Object?>) return const {};
  return {for (final e in m.entries) e.key: '${e.value}'};
}
