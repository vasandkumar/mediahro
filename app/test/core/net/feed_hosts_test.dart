import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/persistent_network_policy.dart';

/// PRIV-004: the hosts of podcast subscriptions and radio stations are the
/// user's own choice: recorded only by an explicit user action, listed with
/// what added them, kept across restarts, and removed with their owners.
void main() {
  late LibraryDatabase db;
  late PersistentNetworkPolicy policy;

  setUp(() async {
    db = LibraryDatabase.memory();
    policy = await PersistentNetworkPolicy.load(db);
  });
  tearDown(() async {
    await policy.dispose();
    await db.close();
  });

  Future<void> add(String url, String owner, [String label = 'L']) =>
      policy.addFeedHost(Uri.parse(url), owner: owner, label: label);

  test('PRIV-004 nothing is allowed until the user adds a feed or a '
      'station', () {
    expect(policy.isUserConfiguredHost('feeds.example.com'), isFalse);
    expect(policy.feedHostEntries, isEmpty);
  });

  test('PRIV-004 a subscription allows its host and lists it with what '
      'added it; other hosts stay blocked', () async {
    await add('https://Feeds.Example.com/show.xml', 'podcast:a', 'The Show');
    expect(policy.isUserConfiguredHost('feeds.example.com'), isTrue);
    expect(policy.isUserConfiguredHost('other.example.com'), isFalse);
    expect(
      policy.isUserConfiguredHost('cdn.example.com'),
      isFalse,
      reason: 'only the feed host, not its neighbours',
    );
    final e = policy.feedHostEntries.single;
    expect(e.origin, 'https://feeds.example.com');
    expect(e.owner, 'podcast:a');
    expect(e.label, 'The Show');
    expect(e.host, 'feeds.example.com');
  });

  test('PRIV-004 hosts are stored as scheme, host and port: default ports '
      'dropped, others kept, case folded', () async {
    await add('HTTPS://A.EXAMPLE.COM:443/x', 'podcast:a');
    await add('http://b.example.com:80/x', 'podcast:b');
    await add('http://c.example.com:8080/x', 'radio:c');
    await add('https://[::1]:8443/x', 'radio:d');
    expect(policy.feedHostEntries.map((e) => e.origin), [
      'http://b.example.com',
      'http://c.example.com:8080',
      'https://[::1]:8443',
      'https://a.example.com',
    ]);
  });

  test('PRIV-004 only plain http(s) addresses count: no other scheme, no '
      'wildcard, no host-less address', () async {
    expect(
      PersistentNetworkPolicy.normalizeOrigin(Uri.parse('file:///x')),
      isNull,
    );
    expect(
      PersistentNetworkPolicy.normalizeOrigin(Uri.parse('rtmp://a.example/x')),
      isNull,
    );
    expect(
      PersistentNetworkPolicy.normalizeOrigin(
        Uri.parse('https://*.example.com/x'),
      ),
      isNull,
    );
    expect(
      PersistentNetworkPolicy.normalizeOrigin(Uri.parse('/relative')),
      isNull,
    );
    expect(
      PersistentNetworkPolicy.normalizeOrigin(Uri.parse('https://')),
      isNull,
    );
    await add('https://*.example.com/x', 'podcast:w');
    await add('ftp://a.example.com/x', 'podcast:f');
    expect(policy.feedHostEntries, isEmpty);
    expect(policy.isUserConfiguredHost('anything.example.com'), isFalse);
  });

  test('PRIV-004 removing the owner takes its host away; a host two '
      'owners share stays until the last one goes', () async {
    await add('https://feeds.example.com/one.xml', 'podcast:one', 'One');
    await add('https://feeds.example.com/two.xml', 'podcast:two', 'Two');
    await add('http://radio.example.net:8000/live', 'radio:r', 'Radio');
    expect(policy.feedHostEntries, hasLength(3));

    await policy.removeFeedOwner('podcast:one');
    expect(policy.isUserConfiguredHost('feeds.example.com'), isTrue);
    expect(policy.feedHostEntries.map((e) => e.owner), [
      'radio:r',
      'podcast:two',
    ]);

    await policy.removeFeedOwner('podcast:two');
    expect(policy.isUserConfiguredHost('feeds.example.com'), isFalse);
    expect(policy.isUserConfiguredHost('radio.example.net'), isTrue);

    await policy.removeFeedOwner('podcast:never-added');
    expect(policy.feedHostEntries, hasLength(1));
  });

  test('PRIV-004 adding the same owner again updates its name, not the '
      'list', () async {
    await add('https://feeds.example.com/x.xml', 'podcast:a', 'Old name');
    await add('https://feeds.example.com/x.xml', 'podcast:a', 'New name');
    expect(policy.feedHostEntries.single.label, 'New name');
  });

  test('PRIV-004 an owner has one origin: editing a station to another '
      'address takes the old one away', () async {
    await add('http://old.example.net:8000/live', 'radio:r', 'Radio');
    await add('https://other.example.com/x.xml', 'podcast:p', 'Other');
    expect(policy.isUserConfiguredHost('old.example.net'), isTrue);
    await add('https://new.example.org/live', 'radio:r', 'Radio');
    expect(policy.isUserConfiguredHost('old.example.net'), isFalse);
    expect(policy.isUserConfiguredHost('new.example.org'), isTrue);
    expect(policy.feedHostEntries.map((e) => e.origin), [
      'https://new.example.org',
      'https://other.example.com',
    ]);
    // Kept across a restart.
    final again = await PersistentNetworkPolicy.load(db);
    expect(again.isUserConfiguredHost('old.example.net'), isFalse);
    await again.dispose();
    // The same host on another port is the same owner's new origin too.
    await add('https://new.example.org:8443/live', 'radio:r', 'Radio');
    expect(
      policy.feedHostEntries.where((e) => e.owner == 'radio:r').single.origin,
      'https://new.example.org:8443',
    );
  });

  test('PRIV-004 pruning forgets owners that no longer exist, only for the '
      'prefix asked', () async {
    await add('https://a.example.com/a.xml', 'podcast:a');
    await add('https://b.example.com/b.xml', 'podcast:b');
    await add('https://c.example.net/live', 'radio:c');
    await policy.pruneFeedOwners('podcast', {'a'});
    expect(policy.feedHostEntries.map((e) => e.owner), [
      'podcast:a',
      'radio:c',
    ]);
    expect(policy.isUserConfiguredHost('b.example.com'), isFalse);
    // Kept across a restart.
    final again = await PersistentNetworkPolicy.load(db);
    expect(again.isUserConfiguredHost('b.example.com'), isFalse);
    expect(again.isUserConfiguredHost('c.example.net'), isTrue);
    await again.dispose();
    await policy.pruneFeedOwners('radio', {});
    expect(policy.feedHostEntries.map((e) => e.owner), ['podcast:a']);
  });

  test('PRIV-004 a fresh start reloads the hosts, and what is not valid '
      'is ignored', () async {
    await add('https://feeds.example.com/x.xml', 'podcast:a', 'The Show');
    await add('http://radio.example.net:8000/live', 'radio:r', 'Radio');
    final again = await PersistentNetworkPolicy.load(db);
    expect(again.feedHostEntries, policy.feedHostEntries);
    expect(again.isUserConfiguredHost('feeds.example.com'), isTrue);
    expect(again.isUserConfiguredHost('radio.example.net'), isTrue);
    await again.dispose();

    // A damaged or tampered record allows nothing.
    await db
        .into(db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(
            key: 'privacy.feedHosts',
            value:
                '[{"origin":"https://*.evil.com","owner":"podcast:x","label":""},'
                '{"origin":"HTTPS://Upper.Example.com","owner":"podcast:y"},'
                '{"origin":"https://ok.example.com","owner":"podcast:z","label":"Z"},'
                '"junk"]',
          ),
        );
    final tampered = await PersistentNetworkPolicy.load(db);
    expect(tampered.feedHostEntries.map((e) => e.origin), [
      'https://ok.example.com',
    ]);
    expect(tampered.isUserConfiguredHost('anything.evil.com'), isFalse);
    await tampered.dispose();
    await db
        .into(db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(
            key: 'privacy.feedHosts',
            value: 'not json',
          ),
        );
    final broken = await PersistentNetworkPolicy.load(db);
    expect(broken.feedHostEntries, isEmpty);
    await broken.dispose();
  });

  test('PRIV-004 removing a host in the dashboard unsubscribes or deletes '
      'what added it, then the host goes', () async {
    final removed = <String>[];
    policy
      ..registerOwnerRemover('podcast', (id) async {
        removed.add('podcast:$id');
        await policy.removeFeedOwner('podcast:$id');
      })
      ..registerOwnerRemover('radio', (id) async => removed.add('radio:$id'));
    await add('https://shared.example.com/a.xml', 'podcast:a');
    await add('https://shared.example.com/b.mp3', 'radio:b');
    await add('https://other.example.com/c.xml', 'podcast:c');
    // The radio remover forgets to clear its entry; the policy still does.
    final owners = await policy.removeFeedHost('shared.example.com');
    expect(owners, ['podcast:a', 'radio:b']);
    expect(removed, ['podcast:a', 'radio:b']);
    expect(policy.isUserConfiguredHost('shared.example.com'), isFalse);
    expect(policy.isUserConfiguredHost('other.example.com'), isTrue);
    expect(await policy.removeFeedHost('gone.example.com'), isEmpty);
  });

  test('PRIV-004 hosts are matched by name: one removal takes the owners '
      'on every scheme and port of that host', () async {
    policy.registerOwnerRemover('radio', (id) async {});
    await add('http://radio.example.net:8000/a', 'radio:a');
    await add('https://radio.example.net/b', 'radio:b');
    await add('https://other.example.net/c', 'radio:c');
    expect(policy.isUserConfiguredHost('radio.example.net'), isTrue);
    expect(await policy.removeFeedHost('RADIO.example.net'), [
      'radio:a',
      'radio:b',
    ]);
    expect(policy.feedHostEntries.map((e) => e.owner), ['radio:c']);
  });

  test('PRIV-004 removing a host is refused, changing nothing, until the '
      'feature that owns it has registered how to remove it', () async {
    await add('https://feeds.example.com/a.xml', 'podcast:a');
    await add('https://feeds.example.com/b.mp3', 'radio:b');
    expect(await policy.removeFeedHost('feeds.example.com'), isNull);
    expect(policy.feedHostEntries, hasLength(2));
    final removed = <String>[];
    policy.registerOwnerRemover('podcast', (id) async => removed.add(id));
    // One of the two is still not registered: nothing happens.
    expect(await policy.removeFeedHost('feeds.example.com'), isNull);
    expect(removed, isEmpty);
    expect(policy.feedHostEntries, hasLength(2));
    policy.registerOwnerRemover('radio', (id) async => removed.add(id));
    expect(await policy.removeFeedHost('feeds.example.com'), hasLength(2));
    expect(removed, ['a', 'b']);
    expect(policy.feedHostEntries, isEmpty);
  });

  test('PRIV-004 changes are announced for the dashboard', () async {
    var n = 0;
    final sub = policy.changes.listen((_) => n++);
    await add('https://feeds.example.com/x.xml', 'podcast:a');
    await policy.removeFeedOwner('podcast:a');
    await Future<void>.delayed(Duration.zero);
    expect(n, 2);
    await sub.cancel();
  });
}
