import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/library/queues.dart';
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/books/book_player.dart';
import 'package:mediahro/features/music/books/book_store.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/music_player.dart';
import 'package:mediahro/features/music/player/music_prefs.dart';
import 'package:mediahro/features/music/player/spoken_mode.dart';
import 'package:mediahro/features/music/podcasts/feed_parser.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_player.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro/features/music/podcasts/podcast_store.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';

import 'music_test_support.dart';

/// Audiobooks and podcasts share one music engine and one speed setting. A
/// player that gives way to another must not undo what the other set, and a
/// book must not mistake an episode (or a station) for its own files.
void main() {
  late LibraryDatabase db;
  late ScriptedMusicEngine engine;
  late MusicPlayer player;
  late MusicDsp dsp;
  late BookPlayer book;
  late PodcastPlayer pod;
  late BookStore bookStore;
  late PodcastStore podStore;
  late Book emma;
  late PodcastShow show;

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    db = LibraryDatabase.memory();
    engine = ScriptedMusicEngine();
    final seed = MusicSeed(db);
    for (var i = 1; i <= 2; i++) {
      await seed.song(
        'Emma/0$i.mp3',
        title: 'Part $i',
        album: 'Emma',
        genre: 'Audiobook',
        track: i,
        durationMs: 600000,
      );
    }
    player = MusicPlayer(
      engine: engine,
      queues: QueueRepository(db),
      library: MusicLibrary(db),
      files: localMusicFiles(db),
      openTimeout: const Duration(milliseconds: 100),
    );
    await player.init();
    dsp = MusicDsp(engine: engine, prefs: MusicPrefs(db), db: db);
    final mode = SpokenMode();
    bookStore = BookStore(MusicPrefs(db));
    final library = BookLibrary(
      library: MusicLibrary(db),
      store: bookStore,
      files: localMusicFiles(db),
      readTags: readTagsOf,
    );
    book = BookPlayer(
      player: player,
      engine: engine,
      dsp: dsp,
      library: library,
      store: bookStore,
      mode: mode,
    );
    podStore = PodcastStore(MusicPrefs(db));
    final service = PodcastService(
      store: podStore,
      http: PodcastHttp(
        send: (r, {maxRedirects = 5}) => throw StateError('no network'),
        beginChain: () => ChainAllowance(allow: (_) {}, close: () {}),
      ),
      downloads: _NoDownloads(),
    );
    pod = PodcastPlayer(
      player: player,
      engine: engine,
      dsp: dsp,
      service: service,
      mode: mode,
    );
    show = PodcastShow(
      id: 's1',
      url: 'https://show.example/rss',
      title: 'The Show',
      subscribedAt: DateTime.utc(2026),
      speed: 1.5,
      episodes: const [
        ParsedEpisode(
          guid: 'g1',
          title: 'Episode 1',
          url: 'https://cdn.example/e1.mp3',
        ),
      ],
    );
    await podStore.save(show);
    emma = (await library.books()).single;
  });
  tearDown(() async {
    await book.dispose();
    await pod.dispose();
    await player.dispose();
    await db.close();
  });

  test('POD-002 an episode that starts while a book is open ends book '
      'mode: the book keeps its place, and the book leaving does not reset '
      "the episode's speed", () async {
    await book.open(emma);
    await book.setSpeed(2);
    engine.at(const Duration(minutes: 3));
    await settle();

    await pod.play(show, show.episodes.single);
    await settle();
    expect(book.state.active, isFalse);
    expect(pod.state.active, isTrue);
    // The book's place is where it was, not the episode's position.
    final saved = (await bookStore.progress(emma.id))!;
    expect(saved.position, const Duration(minutes: 3));
    expect(saved.speed, 2);
    // The episode's speed stands.
    expect(engine.current.rate, 1.5);
    expect(pod.state.speed, 1.5);

    // The episode moving never moves the book.
    engine.at(const Duration(minutes: 8));
    await settle();
    expect(
      (await bookStore.progress(emma.id))!.position,
      const Duration(minutes: 3),
    );
  });

  test('POD-001 a book that starts while an episode plays takes over the '
      'speed; the episode keeps its place', () async {
    await pod.play(show, show.episodes.single);
    await pod.setSpeed(1.25);
    engine.at(const Duration(minutes: 1));
    await settle();

    await bookStore.saveProgress(
      emma.id,
      const BookProgress(speed: 2.25, skipSilence: true),
    );
    await book.open(emma);
    await settle();
    expect(pod.state.active, isFalse);
    expect(book.state.active, isTrue);
    expect(engine.current.rate, 2.25);
    expect(engine.dsp?.skipSilence, isTrue);
    expect(
      (await podStore.progress('s1'))['g1']!.position,
      const Duration(minutes: 1),
    );
  });

  test('POD-001 a radio station playing ends book mode', () async {
    await book.open(emma);
    await book.setSpeed(2);
    await player.playStation(
      RadioStation(id: 'r', name: 'Radio', url: Uri.parse('http://r.example/')),
    );
    await settle();
    expect(book.state.active, isFalse);
    // Nobody took over: the engine goes back to normal.
    expect(engine.current.rate, 1);
  });
}

final class _NoDownloads implements EpisodeDownloads {
  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {}

  @override
  Future<EpisodeDownload?> status(Uri url) async => null;

  @override
  Future<void> remove(Uri url) async {}
}
