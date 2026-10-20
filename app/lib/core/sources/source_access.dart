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
    this.credentialKey,
  });

  final SourceKind kind;
  final Uri root;
  final Map<String, String> options;
  final String? userName;
  final String? secret;

  /// SecureStorage key of the credential, for platform clients that take
  /// references instead of values (SftpFacade, ADR-017).
  final String? credentialKey;
}

/// Resolved access to a source: its root and a factory for its file system.
@immutable
final class SourceAccess {
  const SourceAccess(
    this.spec,
    this.fileSystem, {
    this.mainIsolate = false,
    this.release,
  });

  final SourceSpec spec;

  /// Creates the file system; safe to call inside a scan isolate unless
  /// [mainIsolate].
  final FileSystemFactory fileSystem;

  /// The file system talks to platform facades (TLS sockets, SFTP), which
  /// live on the main isolate: scans run there, as async I/O.
  final bool mainIsolate;

  /// Ends a scoped grant (security-scoped bookmark access on Apple) once the
  /// scan or the browsing session is over.
  final Future<void> Function()? release;

  Uri get root => spec.root;

  Future<void> close() => release?.call() ?? Future.value();
}

/// URI schemes whose file systems call platform facades (SAF, MediaStore),
/// so their scans run on the main isolate.
const Set<String> mainIsolateSchemes = {'saf', 'mediastore'};

/// The readable root of a granted folder (LIB-002): starts scoped access
/// ([StorageFacade.startAccess]). An Android SAF tree becomes the
/// path-shaped `saf://tree/<grantId>/` root, with the tree URI passed to the
/// file system in the `safTree` option.
Future<(Uri, Map<String, String>, Future<void> Function())> grantRoot(
  StorageFacade storage,
  String grantId,
) async {
  final scoped = await storage.startAccess(grantId);
  final root = scoped.root;
  if (root.scheme == 'content') {
    return (
      Uri(scheme: 'saf', host: 'tree', pathSegments: [grantId, '']),
      {'safTree': root.toString()},
      scoped.stop,
    );
  }
  return (root, const <String, String>{}, scoped.stop);
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
    this.mainIsolateKinds = const {},
  });

  final Map<SourceKind, FileSystemBuilder> builders;

  /// Kinds whose file systems use platform facades (see [SourceAccess]).
  final Set<SourceKind> mainIsolateKinds;
  final StorageFacade? storage;
  final SecureStorageFacade? secureStorage;

  @override
  Future<SourceAccess> resolve(SourceRow source) async {
    var root = Uri.parse(source.rootUri);
    var extra = const <String, String>{};
    Future<void> Function()? release;
    final grant = source.grantId;
    if (grant != null) {
      final s = storage;
      if (s == null) {
        throw SourceUnavailable(source.id, 'folder access needs the platform');
      }
      try {
        (root, extra, release) = await grantRoot(s, grant);
      } on Exception catch (e) {
        throw SourceUnavailable(source.id, 'folder access was revoked ($e)');
      }
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
      options: {...decodeOptions(source.options), ...extra},
      userName: user,
      secret: secret,
      credentialKey: key,
    );
    return SourceAccess(
      spec,
      () => builder(spec),
      mainIsolate:
          mainIsolateKinds.contains(source.kind) ||
          mainIsolateSchemes.contains(root.scheme),
      release: release,
    );
  }
}

/// A credential as stored in SecureStorageFacade under `sources.credentialKey`.
@immutable
final class StoredCredential {
  const StoredCredential({
    this.userName,
    this.secret,
    this.kind = 'password',
    this.passphrase,
  });

  factory StoredCredential.decode(String raw) {
    final m = jsonDecode(raw) as Map<String, Object?>;
    return StoredCredential(
      userName: m['user'] as String?,
      secret: m['secret'] as String?,
      kind: m['kind'] as String? ?? 'password',
      passphrase: m['passphrase'] as String?,
    );
  }

  final String? userName;

  /// Password, SFTP private key (PEM), or OAuth refresh token.
  final String? secret;

  /// `password`, `sshKey`, `oauth`, `guest`.
  final String kind;

  /// Passphrase of an encrypted SSH private key.
  final String? passphrase;

  String encode() => jsonEncode({
    'user': userName,
    'secret': secret,
    'kind': kind,
    if (passphrase != null) 'passphrase': passphrase,
  });
}

Map<String, String> decodeOptions(String json) {
  final m = jsonDecode(json);
  if (m is! Map<String, Object?>) return const {};
  return {for (final e in m.entries) e.key: '${e.value}'};
}
