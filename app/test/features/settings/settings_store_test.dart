import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_store.dart';

void main() {
  group('CORE-006 settings model', () {
    test('typed reads fall back to defaults; writes round-trip', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null);
      expect(s.get(CoreSettings.themeMode), ThemeMode.system);
      s.set(CoreSettings.themeMode, ThemeMode.dark);
      expect(s.get(CoreSettings.themeMode), ThemeMode.dark);
      expect(s.snapshot.values['appearance.themeMode'], 'dark');
    });

    test('values equal to the default are not stored', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null);
      s
        ..set(CoreSettings.amoled, true)
        ..set(CoreSettings.amoled, false);
      expect(s.snapshot.values, isEmpty);
    });

    test('invalid stored values read as the default', () async {
      final s = await SettingsStore.open(
        MemorySettingsPersistence({
          'schema': 1,
          'values': {'appearance.themeMode': 'purple', 'appearance.amoled': 3},
        }),
        null,
      );
      expect(s.get(CoreSettings.themeMode), ThemeMode.system);
      expect(s.get(CoreSettings.amoled), isFalse);
    });

    test('persists to JSON and loads it back', () async {
      final p = MemorySettingsPersistence();
      final a = await SettingsStore.open(p, null);
      a.set(CoreSettings.amoled, true);
      await a.flush();
      final b = await SettingsStore.open(p, null);
      expect(b.get(CoreSettings.amoled), isTrue);
    });

    test('debounces writes', () async {
      final p = MemorySettingsPersistence();
      final s = await SettingsStore.open(p, const Duration(milliseconds: 20));
      s
        ..set(CoreSettings.amoled, true)
        ..set(CoreSettings.modeAccents, false);
      expect(p.saves, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(p.saves, 1);
    });

    test(
      'file persistence writes atomically and quarantines a corrupt file',
      () async {
        final dir = await Directory.systemTemp.createTemp('mediahro-settings');
        addTearDown(() => dir.delete(recursive: true));
        final p = FileSettingsPersistence(directory: () async => dir);
        final s = await SettingsStore.open(p, null);
        s.set(CoreSettings.language, 'de');
        await s.flush();
        final file = File('${dir.path}${Platform.pathSeparator}settings.json');
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect((json['values']! as Map)['appearance.language'], 'de');
        expect(File('${file.path}.tmp').existsSync(), isFalse);

        file.writeAsStringSync('{not json');
        final again = await SettingsStore.open(p, null);
        expect(again.get(CoreSettings.language), '');
        expect(
          File('${dir.path}${Platform.pathSeparator}settings.corrupt.json')
              .existsSync(),
          isTrue,
        );
      },
    );

    test('reset per section clears only that section', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null);
      s
        ..set(CoreSettings.amoled, true)
        ..set(CoreSettings.endpoint('tmdb'), true)
        ..resetSection('appearance');
      expect(s.get(CoreSettings.amoled), isFalse);
      expect(s.get(CoreSettings.endpoint('tmdb')), isTrue);
    });

    test(
      'export then import restores values; shell state stays local',
      () async {
        final a = await SettingsStore.open(MemorySettingsPersistence(), null);
        a
          ..set(CoreSettings.themeMode, ThemeMode.light)
          ..set(CoreSettings.lastMode, 'music');
        final json = a.exportJson(now: DateTime.utc(2026, 10, 19));
        expect(json, contains('"format": "mediahro.settings"'));
        expect(json, isNot(contains('shell.lastMode')));

        final b = await SettingsStore.open(MemorySettingsPersistence(), null);
        b.set(CoreSettings.amoled, true);
        final r = b.importJson(json, known: CoreSettings.all);
        expect(r.imported, 1);
        expect(b.get(CoreSettings.themeMode), ThemeMode.light);
        expect(b.get(CoreSettings.amoled), isFalse, reason: 'import replaces');
      },
    );

    test('import keeps unknown keys, skips invalid and managed ones', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null)
        ..applyManaged({'privacy.endpoint.crash': false});
      final r = s.importJson(
        jsonEncode({
          'format': 'mediahro.settings',
          'schema': 1,
          'values': {
            'video.someFutureOption': 3,
            'appearance.themeMode': 'neon',
            'privacy.endpoint.crash': true,
          },
        }),
        known: CoreSettings.all,
      );
      expect(r.imported, 1);
      expect(r.skippedInvalid, 1);
      expect(r.skippedManaged, 1);
      expect(s.snapshot.values['video.someFutureOption'], 3);
    });

    test('import rejects other files and newer schemas', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null);
      expect(
        () => s.importJson('nope'),
        throwsA(isA<SettingsImportException>()),
      );
      expect(
        () => s.importJson('{"values": {}}'),
        throwsA(isA<SettingsImportException>()),
      );
      expect(
        () => s.importJson(
          '{"format": "mediahro.settings", "schema": 99, "values": {}}',
        ),
        throwsA(
          isA<SettingsImportException>().having(
            (e) => e.reason,
            'reason',
            SettingsImportError.newerSchema,
          ),
        ),
      );
    });

    test('managed overlay wins and is read-only (B2B-001 hook)', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null)
        ..set(CoreSettings.amoled, false)
        ..applyManaged({'appearance.amoled': true});
      expect(s.get(CoreSettings.amoled), isTrue);
      expect(s.isManaged(CoreSettings.amoled), isTrue);
      expect(
        () => s.set(CoreSettings.amoled, false),
        throwsA(isA<ManagedSettingException>()),
      );
      s.applyManaged({});
      expect(s.get(CoreSettings.amoled), isFalse);
    });

    test('PRIV-001 every endpoint and update checks start off', () async {
      final s = await SettingsStore.open(MemorySettingsPersistence(), null);
      for (final id in ['config', 'crash', 'analytics', 'tmdb']) {
        expect(s.get(CoreSettings.endpoint(id)), isFalse);
      }
      expect(s.get(CoreSettings.updateCheck), isFalse);
    });
  });
}
