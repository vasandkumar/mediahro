import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/backup/backup_crypto.dart';
import 'package:mediahro/core/backup/backup_service.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/playlists.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/core/library/tags.dart';
import 'package:mediahro/core/rules/smart_rule.dart';

import '../fakes.dart';
import '../seed.dart';

void main() {
  test('CORE-014 backup is one encrypted file; wrong passphrase and tampering are detected', () async {
    final file = await encryptBackup(
      {'hello': 'world'},
      'correct horse',
      iterations: 100000,
    );
    expect(String.fromCharCodes(file.sublist(0, 7)), 'MHROBK1');
    expect(
      String.fromCharCodes(file).contains('world'),
      isFalse,
      reason: 'payload is not readable',
    );
    expect(await decryptBackup(file, 'correct horse'), {'hello': 'world'});
    await expectLater(
      decryptBackup(file, 'wrong'),
      throwsA(isA<BackupDecryptError>()),
    );
    final tampered = Uint8List.fromList(file)..[file.length - 20] ^= 1;
    await expectLater(
      decryptBackup(tampered, 'correct horse'),
      throwsA(isA<BackupDecryptError>()),
    );
    await expectLater(
      decryptBackup(Uint8List.fromList([1, 2, 3]), 'x'),
      throwsA(isA<BackupDecryptError>()),
    );
  });

  test('CORE-014 restore on another device: positions, playlists, ratings, tags, settings, queues', () async {
    // Device A (e.g. Windows): D:\Media
    final a = LibraryDatabase.memory();
    addTearDown(a.close);
    final seedA = Seed(a);
    final srcA = await a
        .into(a.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Media',
            rootUri: 'file:///D:/Media/',
            addedAt: DateTime.utc(2026),
          ),
        );
    final film = await seedA.item('Films/Film.mkv', sourceId: srcA, size: 1234);
    final song = await seedA.item(
      'Music/Song.flac',
      sourceId: srcA,
      kind: ItemKind.audio,
      size: 99,
    );
    await (a.update(a.items)..where((i) => i.id.equals(film))).write(
      const ItemsCompanion(contentHash: Value('abc')),
    );
    await a
        .into(a.progress)
        .insert(
          ProgressCompanion.insert(
            itemId: Value(film),
            positionMs: 600000,
            updatedAt: DateTime.utc(2026, 10),
          ),
        );
    await seedA.rate(song, 8);
    await TagRepository(a).addTag([song], 'Workout');
    await TagRepository(a).setLabel([film], LabelColor.blue);
    final pl = PlaylistRepository(a);
    final manual = await pl.createManual('Mix');
    await pl.addItems(manual, [song]);
    await pl.addUri(manual, 'https://radio.example/stream', title: 'Radio');
    await pl.createSmart(
      'Rock',
      const SmartRule(
        root: RuleGroup(
          children: [RuleCondition(RuleField.genre, RuleOp.equals, 'Rock')],
        ),
      ),
    );
    final q = QueueRepository(a);
    final qid = await q.createAudioQueue('Gym');
    await q.replace(qid, [song]);
    await a
        .into(a.settingsTable)
        .insert(
          SettingsTableCompanion.insert(
            key: 'library.viewMode.music',
            value: 'folders',
          ),
        );
    await a
        .into(a.settingsTable)
        .insert(
          SettingsTableCompanion.insert(
            key: 'privacy.lastUsed.lrclib',
            value: 'x',
          ),
        );
    final secrets = FakeSecureStorage()
      ..values['cred.nas'] = '{"user":"u","secret":"p"}';
    await (a.update(a.sources)..where((s) => s.id.equals(srcA))).write(
      const SourcesCompanion(credentialKey: Value('cred.nas')),
    );
    final file = await BackupService(
      a,
      secureStorage: secrets,
    ).export('passphrase-1', includeCredentials: true, iterations: 100000);

    // Device B (e.g. Android): the same files under another root; the film
    // was renamed but has the same content hash.
    final b = LibraryDatabase.memory();
    addTearDown(b.close);
    final seedB = Seed(b);
    final srcB = await b
        .into(b.sources)
        .insert(
          SourcesCompanion.insert(
            kind: SourceKind.local,
            name: 'Phone',
            rootUri: 'content://tree/primary%3AMedia/',
            addedAt: DateTime.utc(2026),
          ),
        );
    final filmB = await seedB.item(
      'Movies/Renamed.mkv',
      sourceId: srcB,
      size: 1234,
    );
    await (b.update(b.items)..where((i) => i.id.equals(filmB))).write(
      const ItemsCompanion(contentHash: Value('abc')),
    );
    final songB = await seedB.item(
      'Music/Song.flac',
      sourceId: srcB,
      kind: ItemKind.audio,
      size: 99,
    );
    final secretsB = FakeSecureStorage();
    final report = await BackupService(
      b,
      secureStorage: secretsB,
    ).restore(file, 'passphrase-1');

    expect(report.matchedItems, 2);
    expect(report.unmatchedItems, 0);
    expect(
      (await (b.select(
        b.progress,
      )..where((p) => p.itemId.equals(filmB))).getSingle()).positionMs,
      600000,
    );
    expect(
      (await (b.select(
        b.ratings,
      )..where((r) => r.itemId.equals(songB))).getSingle()).value,
      8,
    );
    expect(await TagRepository(b).tagsOf(songB), ['Workout']);
    expect(await TagRepository(b).labelOf(filmB), LabelColor.blue);
    final playlists = await PlaylistRepository(b).all();
    expect(playlists.map((p) => p.name).toSet(), {'Mix', 'Rock'});
    final mix = await PlaylistRepository(b)
        .tracks(playlists.firstWhere((p) => p.name == 'Mix').id);
    expect(mix.first.item?.id, songB);
    expect(mix.last.uri, 'https://radio.example/stream');
    final queues = await QueueRepository(b).audioQueues();
    expect(
      (await QueueRepository(b).load(queues.single.id)).entries.single.itemId,
      songB,
    );
    final settings = {
      for (final s in await b.select(b.settingsTable).get()) s.key: s.value,
    };
    expect(settings['library.viewMode.music'], 'folders');
    expect(settings.containsKey('privacy.lastUsed.lrclib'), isFalse);
    final restoredSource = await (b.select(
      b.sources,
    )..where((s) => s.name.equals('Media'))).getSingle();
    expect(
      restoredSource.enabled,
      isFalse,
      reason: 'root must be re-picked on this device',
    );
    expect(secretsB.values['cred.nas'], contains('"user":"u"'));
  });

  test('CORE-014 newer local progress is kept on restore', () async {
    final db = LibraryDatabase.memory();
    addTearDown(db.close);
    final seed = Seed(db);
    final id = await seed.item('a.mkv');
    await db
        .into(db.progress)
        .insert(
          ProgressCompanion.insert(
            itemId: Value(id),
            positionMs: 5000,
            updatedAt: DateTime.utc(2026, 10, 10),
          ),
        );
    final svc = BackupService(db);
    final payload = await svc.collect();
    await (db.update(db.progress)..where((p) => p.itemId.equals(id))).write(
      ProgressCompanion(
        positionMs: const Value(9000),
        updatedAt: Value(DateTime.utc(2026, 10, 11)),
      ),
    );
    await svc.apply(payload);
    expect((await db.select(db.progress).getSingle()).positionMs, 9000);
  });
}
