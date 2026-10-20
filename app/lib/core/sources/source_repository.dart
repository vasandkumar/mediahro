import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/sources/sftp/sftp_file_system.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// A source row with the facts the Sources screen shows (docs/06 §3.4):
/// health dot, last scan, item counts.
@immutable
final class SourceSummary {
  const SourceSummary(
    this.source, {
    required this.items,
    required this.missing,
    this.lastJob,
  });

  final SourceRow source;
  final int items;
  final int missing;
  final ScanJobRow? lastJob;

  SourceHealth get health {
    if (!source.enabled) return SourceHealth.disabled;
    final j = lastJob;
    if (j == null) return SourceHealth.unknown;
    return j.state == ScanJobState.failed
        ? SourceHealth.unreachable
        : SourceHealth.ok;
  }
}

enum SourceHealth { ok, unreachable, unknown, disabled }

/// What the add flow collected before saving.
@immutable
final class NewSource {
  const NewSource({
    required this.kind,
    required this.name,
    required this.root,
    this.grantId,
    this.credential,
    this.options = const {},
    this.schedule = ScanSchedule.manual,
    this.scrapeMetadata = false,
  });

  final SourceKind kind;
  final String name;
  final Uri root;
  final String? grantId;
  final StoredCredential? credential;
  final Map<String, String> options;
  final ScanSchedule schedule;
  final bool scrapeMetadata;
}

/// Adds, tests, updates and removes sources (LIB-002, NET-001…007).
/// Credentials go only to [SecureStorageFacade]; the row keeps the key
/// name (PRIV-006).
final class SourceRepository {
  SourceRepository({
    required this.db,
    required this.resolver,
    this.secureStorage,
    this.storage,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final LibraryDatabase db;
  final SourceResolver resolver;
  final SecureStorageFacade? secureStorage;
  final StorageFacade? storage;
  final DateTime Function() _clock;
  final Random _random;

  /// "Test connection before save" (docs/06 §3.4): lists the root once.
  /// Returns the entry count, or throws the [VirtualFileException] to show.
  Future<int> test(NewSource s) async {
    final row = SourceRow(
      id: -1,
      kind: s.kind,
      name: s.name,
      rootUri: s.root.toString(),
      grantId: s.grantId,
      options: jsonEncode(s.options),
      schedule: s.schedule,
      includeVideo: true,
      includeMusic: true,
      includePhotos: true,
      scrapeMetadata: s.scrapeMetadata,
      locked: false,
      enabled: true,
      addedAt: _clock(),
      sortOrder: 0,
    );
    final r = resolver;
    // Platform SSH clients read secrets by reference: stage them under a
    // throwaway key for the test and remove them afterwards.
    final c = s.credential;
    final store = secureStorage;
    final temp = c != null && store != null && s.kind == SourceKind.sftp
        ? _newKey()
        : null;
    if (temp != null) {
      await _writeCredential(store!, temp, s.kind, c!, s.options);
    }
    try {
      final access = r is DefaultSourceResolver
          ? await r.resolveWith(row, c, credentialKey: temp)
          : await r.resolve(row);
      final fs = access.fileSystem();
      try {
        return (await fs.list(access.root).toList()).length;
      } finally {
        if (fs case final ClosableFileSystem f) await f.close();
      }
    } finally {
      if (temp != null) await _deleteCredential(temp);
    }
  }

  Future<int> add(NewSource s) async {
    String? key;
    final c = s.credential;
    if (c != null) {
      final store = secureStorage;
      if (store == null) {
        throw const PlatformCapabilityUnavailable('secureStorage');
      }
      key = _newKey();
      await _writeCredential(store, key, s.kind, c, s.options);
    }
    final count = await db.select(db.sources).get();
    return await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            kind: s.kind,
            name: s.name,
            rootUri: s.root.toString(),
            grantId: Value(s.grantId),
            credentialKey: Value(key),
            options: Value(jsonEncode(s.options)),
            schedule: Value(s.schedule),
            scrapeMetadata: Value(s.scrapeMetadata),
            addedAt: _clock(),
            sortOrder: Value(count.length),
          ),
        );
  }

  Future<void> update(
    int id, {
    String? name,
    ScanSchedule? schedule,
    bool? includeVideo,
    bool? includeMusic,
    bool? includePhotos,
    bool? scrapeMetadata,
    bool? enabled,
    Map<String, String>? options,
  }) => (db.update(db.sources)..where((s) => s.id.equals(id))).write(
    SourcesCompanion(
      name: name == null ? const Value.absent() : Value(name),
      schedule: schedule == null ? const Value.absent() : Value(schedule),
      includeVideo: includeVideo == null
          ? const Value.absent()
          : Value(includeVideo),
      includeMusic: includeMusic == null
          ? const Value.absent()
          : Value(includeMusic),
      includePhotos: includePhotos == null
          ? const Value.absent()
          : Value(includePhotos),
      scrapeMetadata: scrapeMetadata == null
          ? const Value.absent()
          : Value(scrapeMetadata),
      enabled: enabled == null ? const Value.absent() : Value(enabled),
      options: options == null
          ? const Value.absent()
          : Value(jsonEncode(options)),
    ),
  );

  /// Replaces the stored credential (e.g. after a password change).
  Future<void> setCredential(int id, StoredCredential credential) async {
    final s = await (db.select(
      db.sources,
    )..where((x) => x.id.equals(id))).getSingle();
    final store =
        secureStorage ??
        (throw const PlatformCapabilityUnavailable('secureStorage'));
    final key = s.credentialKey ?? 'source.$id';
    await _writeCredential(
      store,
      key,
      s.kind,
      credential,
      decodeOptions(s.options),
    );
    if (s.credentialKey == null) {
      await (db.update(db.sources)..where((x) => x.id.equals(id))).write(
        SourcesCompanion(credentialKey: Value(key)),
      );
    }
  }

  /// Removes the source, its index rows (cascade), its credential and its
  /// folder grant. Files are never touched.
  Future<void> remove(int id) async {
    final s = await (db.select(
      db.sources,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (s == null) return;
    final key = s.credentialKey;
    if (key != null) await _deleteCredential(key);
    final grant = s.grantId;
    if (grant != null) await storage?.releaseGrant(grant);
    await (db.delete(db.sources)..where((x) => x.id.equals(id))).go();
  }

  String _newKey() =>
      'source.${List.generate(8, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  /// The credential as one record, plus, for SFTP, the raw secret under the
  /// reference the platform reads (ADR-017: secrets never cross as values).
  Future<void> _writeCredential(
    SecureStorageFacade store,
    String key,
    SourceKind kind,
    StoredCredential c,
    Map<String, String> options,
  ) async {
    await store.write(key, c.encode());
    if (kind != SourceKind.sftp) return;
    final refs = SftpSecretRefs(key);
    final secret = c.secret;
    final keyAuth = c.kind == 'sshKey' || options['auth'] == 'key';
    await store.delete(refs.password);
    await store.delete(refs.privateKey);
    await store.delete(refs.keyPassphrase);
    if (secret != null) {
      await store.write(keyAuth ? refs.privateKey : refs.password, secret);
    }
    if (c.passphrase case final p? when keyAuth) {
      await store.write(refs.keyPassphrase, p);
    }
  }

  Future<void> _deleteCredential(String key) async {
    final store = secureStorage;
    if (store == null) return;
    final refs = SftpSecretRefs(key);
    await store.delete(key);
    await store.delete(refs.password);
    await store.delete(refs.privateKey);
    await store.delete(refs.keyPassphrase);
  }

  Future<List<SourceSummary>> summaries() async {
    final sources =
        await (db.select(db.sources)..orderBy([
              (s) => OrderingTerm.asc(s.sortOrder),
              (s) => OrderingTerm.asc(s.id),
            ]))
            .get();
    final counts = await db
        .customSelect(
          'SELECT source_id, count(*) AS n, sum(missing) AS m FROM item GROUP BY source_id',
        )
        .get();
    final byId = {
      for (final r in counts)
        r.read<int>('source_id'): (r.read<int>('n'), r.read<int>('m')),
    };
    final out = <SourceSummary>[];
    for (final s in sources) {
      final job =
          await (db.select(db.scanJobs)
                ..where((j) => j.sourceId.equals(s.id))
                ..orderBy([(j) => OrderingTerm.desc(j.id)])
                ..limit(1))
              .getSingleOrNull();
      final c = byId[s.id] ?? (0, 0);
      out.add(
        SourceSummary(s, items: c.$1 - c.$2, missing: c.$2, lastJob: job),
      );
    }
    return out;
  }

  Stream<void> watch() => db.tableUpdates(
    TableUpdateQuery.onAllTables([db.sources, db.scanJobs, db.items]),
  );

  /// Adds a local folder from the platform picker (LIB-002): SAF tree (A),
  /// security-scoped bookmark (I M), folder picker (W).
  Future<int?> addLocalFolder({
    ScanSchedule schedule = ScanSchedule.watch,
  }) async {
    final s = storage ?? (throw const PlatformCapabilityUnavailable('storage'));
    final grant = await s.pickFolder();
    if (grant == null) return null;
    return await add(
      NewSource(
        kind: SourceKind.local,
        name: grant.displayName,
        root: grant.uri,
        grantId: grant.id,
        schedule: schedule,
      ),
    );
  }
}

extension DefaultSourceResolverTest on DefaultSourceResolver {
  /// Resolves an unsaved source with an in-memory credential (test before save).
  Future<SourceAccess> resolveWith(
    SourceRow row,
    StoredCredential? credential, {
    String? credentialKey,
  }) async {
    final builder = builders[row.kind];
    if (builder == null) {
      throw SourceUnavailable(row.id, 'no client for ${row.kind.name}');
    }
    var root = Uri.parse(row.rootUri);
    final grant = row.grantId;
    if (grant != null) root = await storage?.resolveGrant(grant) ?? root;
    final spec = SourceSpec(
      kind: row.kind,
      root: root,
      options: decodeOptions(row.options),
      userName: credential?.userName,
      secret: credential?.secret,
      credentialKey: credentialKey,
    );
    return SourceAccess(
      spec,
      () => builder(spec),
      mainIsolate: mainIsolateKinds.contains(row.kind),
    );
  }
}
