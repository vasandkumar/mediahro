import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/slideshow/slideshow_options.dart';

import '../../helpers.dart';

void main() {
  group('IMG-012 the order of a slideshow', () {
    List<int> run(SlideOrder o) {
      final seen = [o.current];
      while (o.next() && seen.length < 50) {
        seen.add(o.current);
        if (!o.loop && seen.length == o.count) break;
      }
      return seen;
    }

    test('IMG-012 in order it goes from the start and wraps round', () {
      final o = SlideOrder(count: 5, start: 2, random: false, loop: true);
      final seen = <int>[];
      for (var i = 0; i < 5; i++) {
        expect(o.next(), isTrue);
        seen.add(o.current);
      }
      expect(seen, [3, 4, 0, 1, 2]);
      expect(o.next(), isTrue);
      expect(o.current, 3);
    });

    test('IMG-012 without a loop it stops after the last', () {
      final o = SlideOrder(count: 3, start: 0, random: false, loop: false);
      expect(o.hasNext, isTrue);
      expect(o.next(), isTrue);
      expect(o.next(), isTrue);
      expect(o.current, 2);
      expect(o.hasNext, isFalse);
      expect(o.peekNext, isNull);
      expect(o.next(), isFalse);
      expect(o.current, 2);
    });

    test('IMG-012 with a loop the next of the last is the first', () {
      final o = SlideOrder(count: 3, start: 0, random: false, loop: true)
        ..next()
        ..next();
      expect(o.peekNext, 0);
      expect(o.next(), isTrue);
      expect(o.current, 0);
    });

    test('IMG-012 previous steps back and wraps only with a loop', () {
      final loop = SlideOrder(count: 3, start: 0, random: false, loop: true);
      expect(loop.previous(), isTrue);
      expect(loop.current, 2);
      final once = SlideOrder(count: 3, start: 0, random: false, loop: false);
      expect(once.hasPrevious, isFalse);
      expect(once.previous(), isFalse);
      once.next();
      expect(once.previous(), isTrue);
      expect(once.current, 0);
    });

    test(
      'IMG-012 a shuffle starts at the chosen photo and shows each once',
      () {
        for (var seed = 0; seed < 20; seed++) {
          final o = SlideOrder(
            count: 12,
            start: 5,
            random: true,
            loop: false,
            rng: Random(seed),
          );
          final seen = run(o);
          expect(seen.first, 5);
          expect(seen.toSet(), {for (var i = 0; i < 12; i++) i});
          expect(seen, hasLength(12));
        }
      },
    );

    test(
      'IMG-012 different seeds shuffle differently, the same seed alike',
      () {
        List<int> of(int seed) => run(
          SlideOrder(
            count: 10,
            start: 0,
            random: true,
            loop: false,
            rng: Random(seed),
          ),
        );
        expect(of(1), of(1));
        expect(of(1), isNot(of(2)));
        expect(of(1), isNot([for (var i = 0; i < 10; i++) i]));
      },
    );

    test('IMG-012 the place counts from 1', () {
      final o = SlideOrder(count: 4, start: 3, random: false, loop: true);
      expect(o.place, 1);
      o.next();
      expect(o.place, 2);
    });

    test('IMG-012 a start outside the list is brought inside', () {
      expect(
        SlideOrder(count: 3, start: 9, random: false, loop: true).current,
        2,
      );
      expect(
        SlideOrder(count: 3, start: -4, random: false, loop: true).current,
        0,
      );
    });

    test('IMG-012 one photo repeats itself when looping', () {
      final o = SlideOrder(count: 1, start: 0, random: true, loop: true);
      expect(o.peekNext, 0);
      expect(o.next(), isTrue);
      expect(o.current, 0);
    });
  });

  group('IMG-012 slideshow options', () {
    test('IMG-012 the time a photo stays follows the speed', () {
      expect(
        const SlideshowOptions().slideDuration,
        const Duration(seconds: 5),
      );
      expect(
        const SlideshowOptions(speed: 2).slideDuration,
        const Duration(milliseconds: 2500),
      );
      expect(
        const SlideshowOptions(interval: 10, speed: 0.5).slideDuration,
        const Duration(seconds: 20),
      );
    });

    test('IMG-012 interval and speed stay in their range', () {
      final o = const SlideshowOptions().copyWith(interval: 1, speed: 99);
      expect(o.interval, SlideshowOptions.minInterval);
      expect(o.speed, SlideshowOptions.maxSpeed);
      final p = const SlideshowOptions().copyWith(interval: 900, speed: 0);
      expect(p.interval, SlideshowOptions.maxInterval);
      expect(p.speed, SlideshowOptions.minSpeed);
    });

    test('IMG-012 options compare by value', () {
      expect(const SlideshowOptions(), const SlideshowOptions());
      expect(
        const SlideshowOptions(),
        isNot(const SlideshowOptions(kenBurns: true)),
      );
    });

    test('IMG-012 the choices are remembered', () async {
      final store = await memoryStore();
      expect(SlideshowSettings.read(store), const SlideshowOptions());
      const chosen = SlideshowOptions(
        interval: 12,
        transition: SlideChange.zoom,
        kenBurns: true,
        random: true,
        loop: false,
        music: SlideMusicSource.playlist,
        playlistId: 7,
        speed: 1.5,
      );
      SlideshowSettings.write(store, chosen);
      expect(SlideshowSettings.read(store), chosen);
    });

    test('IMG-012 no playlist is remembered as none', () async {
      final store = await memoryStore();
      SlideshowSettings.write(
        store,
        const SlideshowOptions(music: SlideMusicSource.library),
      );
      expect(SlideshowSettings.read(store).playlistId, isNull);
    });
  });
}
