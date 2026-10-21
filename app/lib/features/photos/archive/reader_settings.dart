import 'dart:convert';

import 'package:mediahro/features/photos/archive/reader_layout.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// What the comic reader remembers (IMG-017): how to read, for every book,
/// and the page each book was left at.
abstract final class ReaderPrefs {
  static final SettingKey<ReadingDirection> direction =
      SettingKey.enumeration<ReadingDirection>(
        'photos.reader.direction',
        ReadingDirection.values,
        defaultValue: ReadingDirection.leftToRight,
      );

  static final SettingKey<PageMode> mode = SettingKey.enumeration<PageMode>(
    'photos.reader.mode',
    PageMode.values,
    defaultValue: PageMode.single,
  );

  static final SettingKey<PageFit> fit = SettingKey.enumeration<PageFit>(
    'photos.reader.fit',
    PageFit.values,
    defaultValue: PageFit.page,
  );

  /// Page per book, as JSON (book key to page), the most recent last.
  static final SettingKey<String> positions = SettingKey.text(
    'photos.reader.positions',
    defaultValue: '{}',
  );

  /// How many books keep their place.
  static const int remembered = 50;

  static ReaderSettings read(SettingsStore s) => ReaderSettings(
    direction: s.get(direction),
    mode: s.get(mode),
    fit: s.get(fit),
  );

  static void write(SettingsStore s, ReaderSettings v) {
    s
      ..set(direction, v.direction)
      ..set(mode, v.mode)
      ..set(fit, v.fit);
  }

  static Map<String, int> _positions(SettingsStore s) {
    try {
      final j = jsonDecode(s.get(positions));
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
      };
    } on FormatException {
      return {};
    }
  }

  /// The page [book] was left at, or 0.
  static int page(SettingsStore s, String book) => _positions(s)[book] ?? 0;

  /// Remembers [page] for [book]; the oldest places are forgotten.
  static void savePage(SettingsStore s, String book, int page) {
    final all = _positions(s)
      ..remove(book)
      ..[book] = page;
    while (all.length > remembered) {
      all.remove(all.keys.first);
    }
    s.set(positions, jsonEncode(all));
  }
}
