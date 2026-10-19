import 'package:drift/drift.dart';
import 'package:mediahro/core/backup/backup_crypto.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/platform/security.dart';
import 'package:meta/meta.dart';

/// What a restore changed (CORE-014).
@immutable
final class RestoreReport {
  const RestoreReport({
    this.sources = 0,
    this.matchedItems = 0,
    this.unmatchedItems = 0,
    this.playlists = 0,
    this.queues = 0,
    this.settings = 0,
    this.urls = 0,
  });

  final int sources;
  final int matchedItems;

  /// Entries whose file is not (yet) in this library; they apply on the
  /// next restore after the source is scanned.
  final int unmatchedItems;
  final int playlists;
  final int queues;
  final int settings;
  final int urls;
}

/// Exports library metadata — positions, watched state, play counts,
/// playlists, queues, ratings, tags, labels, hidden/locked state, sources
/// and settings — to one encrypted file, and restores it on any platform
/// (CORE-014). Items are matched by content hash + size first, then by
/// source name + relative path, then by file name + size, so a backup made
/// on Windows restores on Android although the paths differ.
final class BackupService {
  BackupService(
    this.db, {
    this.secureStorage,
    IndexWriter? writer,
    DateTime Function()? clock,
  }) : _writer = writer ?? IndexWriter(db),
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;

  /// Needed only to include credentials (opt-in, PRIV-006).
  final SecureStorageFacade? secureStorage;
  final IndexWriter _writer;
  final DateTime Function() _clock;

  static const formatVersion = 1;

  Future<Uint8List> export(
    String passphrase, {
    bool includeCredentials = false,
    int iterations = 310000,
  }) async {
    if (passphrase.length < 8) {
      throw ArgumentError.value('***', 'passphrase', 'at least 8 characters');
    }
    return await encryptBackup(
      await collect(includeCredentials: includeCredentials),
      passphrase,
      iterations: iterations,
    );
  }

  Future<RestoreReport> restore(Uint8List file, String passphrase) async =>
      await apply(await decryptBackup(file, passphrase));

  /// The backup payload (exposed for tests).
  Future<Map<String, Object?>> collect({
    bool includeCredentials = false,
  }) async {
    final sources = await db.select(db.sources).get();
    final items = await db.select(db.items).get();
    final byId = {for (final i in items) i.id: i};
    final srcName = {for (final s in sources) s.id: s.name};
    Map<String, Object?> key(ItemRow i) => {
      'src': srcName[i.sourceId],
      'path': i.relPath,
      'name': i.name,
      'size': i.size,
      'hash': ?i.contentHash,
    };

    final progress = await db.select(db.progress).get();
    final ratings = {
      for (final r in await db.select(db.ratings).get()) r.itemId: r.value,
    };
    final labels = {
      for (final l in await db.select(db.labels).get()) l.itemId: l.color.name,
    };
    final tagRows = await db.select(db.itemTags).join([
      innerJoin(db.tags, db.tags.id.equalsExp(db.itemTags.tagId)),
    ]).get();
    final tags = <int, List<String>>{};
    for (final r in tagRows) {
      (tags[r.readTable(db.itemTags).itemId] ??= []).add(
        r.readTable(db.tags).name,
      );
    }
    final prog = {for (final p in progress) p.itemId: p};
    final interesting = {
      ...prog.keys,
      ...ratings.keys,
      ...labels.keys,
      ...tags.keys,
      for (final i in items)
        if (i.playCount > 0 || i.hidden) i.id,
    };

    final playlists = <Map<String, Object?>>[];
    for (final p in await db.select(db.playlists).get()) {
      final entries =
          await (db.select(db.playlistItems)
                ..where((e) => e.playlistId.equals(p.id))
                ..orderBy([(e) => OrderingTerm.asc(e.position)]))
              .get();
      playlists.add({
        'name': p.name,
        'mode': p.mode,
        'rule': ?p.rule,
        'entries': [
          for (final e in entries)
            if (e.itemId != null && byId[e.itemId] != null)
              {'item': key(byId[e.itemId]!)}
            else if (e.uri != null)
              {'uri': e.uri, 'title': ?e.title},
        ],
      });
    }
    final queues = <Map<String, Object?>>[];
    for (final q in await db.select(db.queues).get()) {
      final entries =
          await (db.select(db.queueItems)
                ..where((e) => e.queueId.equals(q.id))
                ..orderBy([(e) => OrderingTerm.asc(e.position)]))
              .get();
      queues.add({
        'name': q.name,
        'mode': q.mode,
        'current': q.currentIndex,
        'positionMs': q.positionMs,
        'active': q.active,
        'repeat': q.repeat,
        'entries': [
          for (final e in entries)
            if (e.itemId != null && byId[e.itemId] != null)
              {'item': key(byId[e.itemId]!)}
            else if (e.uri != null)
              {'uri': e.uri},
        ],
      });
    }
    final credentials = <String, String>{};
    if (includeCredentials) {
      for (final s in sources) {
        final k = s.credentialKey;
        final v = k == null ? null : await secureStorage?.read(k);
        if (k != null && v != null) credentials[k] = v;
      }
    }
    return {
      'format': 'mediahro-backup',
      'version': formatVersion,
      'createdAt': _clock().toUtc().toIso8601String(),
      'sources': [
        for (final s in sources)
          {
            'name': s.name,
            'kind': s.kind.name,
            'rootUri': s.rootUri,
            'options': s.options,
            'schedule': s.schedule.name,
            'credentialKey': ?s.credentialKey,
            'includeVideo': s.includeVideo,
            'includeMusic': s.includeMusic,
            'includePhotos': s.includePhotos,
            'scrapeMetadata': s.scrapeMetadata,
            'locked': s.locked,
          },
      ],
      'lockedFolders': [
        for (final f in await db.select(db.lockedFolders).get())
          {'src': srcName[f.sourceId], 'path': f.relPath},
      ],
      'items': [
        for (final id in interesting)
          if (byId[id] case final ItemRow i)
            {
              'key': key(i),
              if (prog[id] case final ProgressRow p) ...{
                'positionMs': p.positionMs,
                'watched': p.watched,
                'progressAt': p.updatedAt.toUtc().toIso8601String(),
              },
              if (i.playCount > 0) 'playCount': i.playCount,
              if (i.lastPlayedAt != null)
                'lastPlayedAt': i.lastPlayedAt!.toUtc().toIso8601String(),
              'rating': ?ratings[id],
              'label': ?labels[id],
              if (tags[id] case final List<String> t) 'tags': t,
              if (i.hidden) 'hidden': true,
            },
      ],
      'playlists': playlists,
      'queues': queues,
      'settings': {
        for (final s in await db.select(db.settingsTable).get())
          if (!s.key.startsWith('privacy.lastUsed.')) s.key: s.value,
      },
      'urlHistory': [
        for (final u in await db.select(db.urlHistory).get())
          {
            'url': u.url,
            'headers': u.headers,
            'userAgent': ?u.userAgent,
            'openedAt': u.openedAt.toUtc().toIso8601String(),
          },
      ],
      if (credentials.isNotEmpty) 'credentials': credentials,
    };
  }

  /// Applies a payload; existing data is merged (newer progress wins).
  Future<RestoreReport> apply(Map<String, Object?> b) async {
    if (b['format'] != 'mediahro-backup' ||
        (b['version'] as int? ?? 0) > formatVersion) {
      throw const BackupDecryptError('unsupportedVersion');
    }
    return await db.transaction(() async {
      final now = _clock();
      var sourcesAdded = 0;
      final sourceIdByName = {
        for (final s in await db.select(db.sources).get()) s.name: s.id,
      };
      for (final s in _maps(b['sources'])) {
        final name = s['name']! as String;
        if (sourceIdByName.containsKey(name)) continue;
        // Sources are recreated disabled: their roots may not exist on this
        // device (other platform, other paths) until the user re-picks them.
        sourceIdByName[name] = await db
            .into(db.sources)
            .insert(
              SourcesCompanion.insert(
                kind: SourceKind.values.byName(s['kind']! as String),
                name: name,
                rootUri: s['rootUri']! as String,
                options: Value(s['options'] as String? ?? '{}'),
                schedule: Value(
                  ScanSchedule.values.byName(
                    s['schedule'] as String? ?? 'manual',
                  ),
                ),
                credentialKey: Value(s['credentialKey'] as String?),
                includeVideo: Value(s['includeVideo'] as bool? ?? true),
                includeMusic: Value(s['includeMusic'] as bool? ?? true),
                includePhotos: Value(s['includePhotos'] as bool? ?? true),
                scrapeMetadata: Value(s['scrapeMetadata'] as bool? ?? false),
                locked: Value(s['locked'] as bool? ?? false),
                enabled: const Value(false),
                addedAt: now,
              ),
            );
        sourcesAdded++;
      }
      final creds = b['credentials'];
      if (creds is Map<String, Object?> && secureStorage != null) {
        for (final e in creds.entries) {
          await secureStorage!.write(e.key, '${e.value}');
        }
      }
      for (final f in _maps(b['lockedFolders'])) {
        final sid = sourceIdByName[f['src']];
        if (sid == null) continue;
        await db
            .into(db.lockedFolders)
            .insertOnConflictUpdate(
              LockedFoldersCompanion.insert(
                sourceId: sid,
                relPath: f['path']! as String,
              ),
            );
      }

      final resolver = await _ItemResolver.load(db);
      var matched = 0;
      var unmatched = 0;
      final touched = <int>[];
      for (final e in _maps(b['items'])) {
        final item = resolver.find(e['key']! as Map<String, Object?>);
        if (item == null) {
          unmatched++;
          continue;
        }
        matched++;
        touched.add(item.id);
        final pos = e['positionMs'] as int?;
        if (pos != null) {
          final at = DateTime.parse(e['progressAt']! as String);
          final local = await (db.select(
            db.progress,
          )..where((p) => p.itemId.equals(item.id))).getSingleOrNull();
          if (local == null || local.updatedAt.isBefore(at)) {
            await db
                .into(db.progress)
                .insertOnConflictUpdate(
                  ProgressCompanion.insert(
                    itemId: Value(item.id),
                    positionMs: pos,
                    watched: Value(e['watched'] as bool? ?? false),
                    updatedAt: at,
                  ),
                );
          }
        }
        final plays = e['playCount'] as int?;
        if (plays != null && plays > item.playCount) {
          await (db.update(db.items)..where((i) => i.id.equals(item.id))).write(
            ItemsCompanion(
              playCount: Value(plays),
              lastPlayedAt: Value(
                e['lastPlayedAt'] == null
                    ? null
                    : DateTime.parse(e['lastPlayedAt']! as String),
              ),
            ),
          );
        }
        if (e['rating'] case final int r) {
          await db
              .into(db.ratings)
              .insertOnConflictUpdate(
                RatingsCompanion.insert(itemId: Value(item.id), value: r),
              );
        }
        if (e['label'] case final String l) {
          await db
              .into(db.labels)
              .insertOnConflictUpdate(
                LabelsCompanion.insert(
                  itemId: Value(item.id),
                  color: LabelColor.values.byName(l),
                ),
              );
        }
        for (final t in (e['tags'] as List<Object?>? ?? const [])) {
          final name = '$t';
          final existing = await (db.select(
            db.tags,
          )..where((x) => x.name.equals(name))).getSingleOrNull();
          final tid =
              existing?.id ??
              await db.into(db.tags).insert(TagsCompanion.insert(name: name));
          await db
              .into(db.itemTags)
              .insert(
                ItemTagsCompanion.insert(itemId: item.id, tagId: tid),
                mode: InsertMode.insertOrIgnore,
              );
        }
        if (e['hidden'] == true) {
          await (db.update(db.items)..where((i) => i.id.equals(item.id))).write(
            const ItemsCompanion(hidden: Value(true)),
          );
        }
      }
      await _writer.refreshFts(touched);

      var playlists = 0;
      for (final p in _maps(b['playlists'])) {
        final id = await db
            .into(db.playlists)
            .insert(
              PlaylistsCompanion.insert(
                name: p['name']! as String,
                mode: Value(p['mode'] as String? ?? 'mixed'),
                rule: Value(p['rule'] as String?),
                createdAt: now,
                updatedAt: now,
              ),
            );
        var pos = 0;
        for (final entry in _maps(p['entries'])) {
          final k = entry['item'];
          final item = k is Map<String, Object?> ? resolver.find(k) : null;
          await db
              .into(db.playlistItems)
              .insert(
                PlaylistItemsCompanion.insert(
                  playlistId: id,
                  position: pos++,
                  itemId: Value(item?.id),
                  uri: Value(
                    item == null
                        ? (entry['uri'] as String? ??
                              (k is Map<String, Object?>
                                  ? k['name'] as String?
                                  : null))
                        : null,
                  ),
                  title: Value(entry['title'] as String?),
                ),
              );
        }
        playlists++;
      }

      var queues = 0;
      for (final q in _maps(b['queues'])) {
        final mode = q['mode']! as String;
        if (mode == 'video') {
          await (db.delete(
            db.queues,
          )..where((x) => x.mode.equals('video'))).go();
        }
        final id = await db
            .into(db.queues)
            .insert(
              QueuesCompanion.insert(
                name: q['name']! as String,
                mode: mode,
                currentIndex: Value(q['current'] as int? ?? 0),
                positionMs: Value(q['positionMs'] as int? ?? 0),
                active: Value(q['active'] as bool? ?? false),
                repeat: Value(q['repeat'] as String? ?? 'off'),
                updatedAt: now,
              ),
            );
        var pos = 0;
        for (final entry in _maps(q['entries'])) {
          final k = entry['item'];
          final item = k is Map<String, Object?> ? resolver.find(k) : null;
          if (item == null && entry['uri'] == null) continue;
          await db
              .into(db.queueItems)
              .insert(
                QueueItemsCompanion.insert(
                  queueId: id,
                  position: pos++,
                  itemId: Value(item?.id),
                  uri: Value(entry['uri'] as String?),
                ),
              );
        }
        queues++;
      }

      var settings = 0;
      final s = b['settings'];
      if (s is Map<String, Object?>) {
        for (final e in s.entries) {
          await db
              .into(db.settingsTable)
              .insertOnConflictUpdate(
                SettingsTableCompanion.insert(key: e.key, value: '${e.value}'),
              );
          settings++;
        }
      }
      var urls = 0;
      for (final u in _maps(b['urlHistory'])) {
        await db
            .into(db.urlHistory)
            .insert(
              UrlHistoryCompanion.insert(
                url: u['url']! as String,
                headers: Value(u['headers'] as String? ?? '{}'),
                userAgent: Value(u['userAgent'] as String?),
                openedAt: DateTime.parse(u['openedAt']! as String),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        urls++;
      }
      return RestoreReport(
        sources: sourcesAdded,
        matchedItems: matched,
        unmatchedItems: unmatched,
        playlists: playlists,
        queues: queues,
        settings: settings,
        urls: urls,
      );
    });
  }

  static Iterable<Map<String, Object?>> _maps(Object? v) =>
      v is List<Object?> ? v.whereType<Map<String, Object?>>() : const [];
}

final class _ItemResolver {
  _ItemResolver(this.byHash, this.byPath, this.byName);

  static Future<_ItemResolver> load(LibraryDatabase db) async {
    final names = {
      for (final s in await db.select(db.sources).get()) s.id: s.name,
    };
    final byHash = <String, ItemRow>{};
    final byPath = <String, ItemRow>{};
    final byName = <String, ItemRow>{};
    for (final i in await db.select(db.items).get()) {
      final h = i.contentHash;
      if (h != null) byHash['$h:${i.size}'] = i;
      byPath['${names[i.sourceId]}\u0000${i.relPath}'] = i;
      byName.putIfAbsent('${i.name.toLowerCase()}\u0000${i.size}', () => i);
    }
    return _ItemResolver(byHash, byPath, byName);
  }

  final Map<String, ItemRow> byHash;
  final Map<String, ItemRow> byPath;
  final Map<String, ItemRow> byName;

  ItemRow? find(Map<String, Object?> k) {
    final hash = k['hash'];
    if (hash is String) {
      final h = byHash['$hash:${k['size']}'];
      if (h != null) return h;
    }
    return byPath['${k['src']}\u0000${k['path']}'] ??
        byName['${'${k['name']}'.toLowerCase()}\u0000${k['size']}'];
  }
}
