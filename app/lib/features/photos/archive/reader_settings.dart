import 'package:mediahro/features/photos/archive/reader_layout.dart';
import 'package:mediahro/features/settings/settings_store.dart';

/// What the comic reader remembers (IMG-017): how to read, for every book.
/// The page each book was left at is kept apart (`ReaderPositions`).
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
}
