import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/features/settings/about/about_info.dart';
import 'package:mediahro/features/settings/about/about_panel.dart';
import 'package:mediahro/features/settings/about/native_notices.dart';
import 'package:mediahro/features/settings/core_sections.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart';

NativeNotices _notices() => const NativeNotices(
  release: 'v2026.10.5-android.1',
  releaseUrl: 'https://github.com/vasandkumar/mediahro-deps/releases/tag/v2026.10.5-android.1',
  sourcesUrl: 'https://github.com/vasandkumar/mediahro-deps/releases/download/v2026.10.5-android.1/mediahro-deps-sources.tar',
  sourcesSha256: 'abc123',
  components: [
    NativeComponent(
      name: 'ffmpeg',
      version: '8.1.3',
      license: 'LGPL-2.1-or-later',
      linking: 'dynamic',
      textId: 'lgpl',
      platforms: ['android'],
      patches: ['patches/ffmpeg/0001-x.patch'],
      configure: ['--enable-shared', '--disable-programs'],
    ),
    NativeComponent(
      name: 'mpv',
      version: '0.41.0',
      license: 'LGPL-2.1-or-later',
      linking: 'dynamic',
      textId: 'lgpl',
      platforms: ['android'],
      configure: ['-Dgpl=false'],
    ),
    NativeComponent(
      name: 'dav1d',
      version: '1.5.4',
      license: 'BSD-2-Clause',
      linking: 'static-or-dynamic',
      textId: 'bsd',
      platforms: ['android'],
    ),
    NativeComponent(
      name: 'windows-only',
      version: '1',
      license: 'MIT',
      linking: 'dynamic',
      textId: 'bsd',
      platforms: ['windows'],
    ),
  ],
  texts: {'lgpl': 'GNU LESSER GENERAL PUBLIC LICENSE text', 'bsd': 'BSD text'},
);

void main() {
  group('CORE-013 the bundled notices', () {
    late NativeNotices notices;
    late String raw;

    setUpAll(() {
      raw = File('assets/licences/native_libraries.json').readAsStringSync();
      notices = NativeNotices.parse(raw);
    });

    test('are for the pinned mediahro-deps release', () {
      final lock = RegExp(r'"release":\s*"([^"]+)"')
          .firstMatch(File('../deps.lock').readAsStringSync())!
          .group(1);
      expect(notices.release, lock);
      expect(notices.releaseUrl, contains(notices.release));
      expect(notices.sourcesUrl, contains(notices.release));
      expect(notices.sourcesSha256, hasLength(64));
    });

    test('name FFmpeg and mpv under the LGPL, built without GPL', () {
      final ffmpeg = notices.component('ffmpeg')!;
      final mpv = notices.component('mpv')!;
      expect(ffmpeg.license, 'LGPL-2.1-or-later');
      expect(mpv.license, 'LGPL-2.1-or-later');
      expect(ffmpeg.linking, 'dynamic');
      expect(mpv.linking, 'dynamic');
      final line = ffmpeg.configure!.join(' ');
      expect(line, isNot(contains('--enable-gpl')));
      expect(line, isNot(contains('--enable-nonfree')));
      expect(line, isNot(contains('--enable-version3')));
      expect(line, contains('--enable-shared'));
      final meson = mpv.configure!;
      expect(meson, contains('-Dgpl=false'));
      expect(meson, contains('-Dlua=disabled'));
      expect(meson, contains('-Djavascript=disabled'));
    });

    test('carry a licence text, a version and a source for every library', () {
      expect(notices.components.length, greaterThan(30));
      for (final c in notices.components) {
        expect(c.version, isNotEmpty, reason: c.name);
        expect(notices.textOf(c).trim(), isNotEmpty, reason: c.name);
        expect(c.sourceUrl, startsWith('https://'), reason: c.name);
        expect(c.platforms, isNotEmpty, reason: c.name);
      }
    });

    test('hold no GPL-only or AGPL library', () {
      for (final c in notices.components) {
        expect(c.license, isNot(contains('AGPL')), reason: c.name);
        expect(
          RegExp(r'(^|[^L])GPL-[23]\.0-(only|or-later)(?! WITH)')
              .hasMatch(c.license),
          isFalse,
          reason: '${c.name}: ${c.license}',
        );
      }
    });

    test('are not much larger than they need to be', () {
      expect(raw.length, lessThan(1500 * 1024));
    });

    test('only the libraries of the platform are listed', () {
      expect(
        notices.forPlatform(AppPlatform.windows).length,
        lessThanOrEqualTo(notices.components.length),
      );
      for (final c in notices.forPlatform(AppPlatform.android)) {
        expect(c.platforms, contains('android'));
      }
    });
  });

  test('CORE-013 the default version is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(
      r'^version:\s*([^+\s]+)\+(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(AboutInfo.version, m.group(1));
    expect(AboutInfo.build, m.group(2));
  });

  test('CORE-013 About is a section of Settings with one entry', () {
    final registry = SettingsRegistry(
      coreSettingsContributions,
      const Capabilities(flavor: Flavor.store, platform: AppPlatform.android),
    );
    final about = registry.section(SettingsSectionId.about)!;
    expect(about.entries.map((e) => e.id), ['about.build']);
  });

  group('CORE-013 About', () {
    Future<void> pump(
      WidgetTester tester, {
      NativeNotices? notices,
      Flavor flavor = Flavor.store,
      AppPlatform platform = AppPlatform.android,
    }) async {
      resetNativeLicenceRegistration();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            capabilitiesProvider.overrideWithValue(
              Capabilities(flavor: flavor, platform: platform),
            ),
            nativeNoticesProvider.overrideWith((ref) async => notices),
          ],
          child: MaterialApp(
            theme: kTestTheme(PlatformFamily.material, Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                KStringsScope(strings: const KTestStrings(), child: child!),
            home: const Scaffold(
              body: SingleChildScrollView(child: AboutPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the name, version, flavour and platform', (
      tester,
    ) async {
      await pump(tester, notices: _notices());
      expect(find.text('Mediahro'), findsOneWidget);
      expect(
        find.text('Version ${AboutInfo.version} (${AboutInfo.build})'),
        findsOneWidget,
      );
      expect(find.text('Store build for Android'), findsOneWidget);
    });

    testWidgets('names the flavour and platform of other builds', (
      tester,
    ) async {
      await pump(
        tester,
        notices: _notices(),
        flavor: Flavor.foss,
        platform: AppPlatform.windows,
      );
      expect(find.text('Open source build for Windows'), findsOneWidget);
    });

    testWidgets('shows the engine versions and the decoder statement', (
      tester,
    ) async {
      await pump(tester, notices: _notices());
      expect(find.text('mpv 0.41.0'), findsOneWidget);
      expect(find.text('FFmpeg 8.1.3'), findsOneWidget);
      expect(find.textContaining("device's own decoders"), findsOneWidget);
    });

    testWidgets('lists the policies and source links to copy', (tester) async {
      await pump(tester, notices: _notices());
      for (final url in [
        AboutLinks.privacy,
        AboutLinks.terms,
        AboutLinks.trademark,
        AboutLinks.source,
      ]) {
        expect(find.text(url), findsOneWidget, reason: url);
      }
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Trademark policy'), findsOneWidget);
      expect(
        find.textContaining('makes no network connections'),
        findsOneWidget,
      );
    });

    testWidgets('copies a link to the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, notices: _notices());

      await tester.tap(find.byTooltip('Copy link').first);
      await tester.pumpAndSettle();

      expect(copied, AboutLinks.privacy);
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('the licence page lists the native libraries', (tester) async {
      await pump(tester, notices: _notices());

      await tester.tap(find.text('Open-source licences'));
      await tester.pumpAndSettle();

      // The page lists packages; the native libraries of this platform are
      // among them and another platform's are not.
      expect(find.text('ffmpeg 8.1.3 (LGPL-2.1-or-later)'), findsOneWidget);
      expect(find.text('dav1d 1.5.4 (BSD-2-Clause)'), findsOneWidget);
      expect(find.textContaining('windows-only'), findsNothing);
    });

    testWidgets('the source page offers the source and the exact build', (
      tester,
    ) async {
      await pump(tester, notices: _notices());

      await tester.tap(find.text('Source code and build details'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('v2026.10.5-android.1 release'),
        findsOneWidget,
      );
      expect(
        find.textContaining('replace them with your own build'),
        findsOneWidget,
      );
      expect(find.text(_notices().sourcesUrl!), findsOneWidget);
      expect(find.text('SHA-256: abc123'), findsOneWidget);
      expect(find.text('--enable-shared --disable-programs'), findsOneWidget);
      expect(find.text('-Dgpl=false'), findsOneWidget);
      expect(
        find.textContaining('Patches: patches/ffmpeg/0001-x.patch'),
        findsOneWidget,
      );
      // Only the LGPL libraries are listed as such.
      expect(
        find.byKey(const ValueKey('lgpl.ffmpeg'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lgpl.mpv'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lgpl.dav1d'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('a build without library notices says so and keeps the rest', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text("Library details aren't included in this build."),
        findsOneWidget,
      );
      expect(find.text('Source code and build details'), findsNothing);
      expect(find.text('Open-source licences'), findsOneWidget);
      expect(find.text(AboutLinks.privacy), findsOneWidget);
    });
  });
}
