import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/capabilities.dart';

/// Where the generated notices live (`tools/licences/gen_native_notices.py`).
const nativeNoticesAsset = 'assets/licences/native_libraries.json';

/// One native library shipped in the app (FFmpeg, mpv, libass, ...): what
/// the licences ask us to show (CORE-013, docs/09 §2).
@immutable
final class NativeComponent {
  const NativeComponent({
    required this.name,
    required this.version,
    required this.license,
    required this.linking,
    required this.textId,
    required this.platforms,
    this.sourceUrl,
    this.sourceSha256,
    this.patches = const [],
    this.configure,
  });

  factory NativeComponent.fromJson(Map<String, Object?> j) => NativeComponent(
    name: j['name']! as String,
    version: j['version']! as String,
    license: j['license']! as String,
    linking: j['linking']! as String,
    textId: j['textId']! as String,
    platforms: [for (final p in j['platforms']! as List<Object?>) p! as String],
    sourceUrl: j['sourceUrl'] as String?,
    sourceSha256: j['sourceSha256'] as String?,
    patches: [
      for (final p in (j['patches'] as List<Object?>?) ?? const [])
        (p! as Map<String, Object?>)['file']! as String,
    ],
    configure: (j['configure'] as List<Object?>?)?.cast<String>(),
  );

  final String name;
  final String version;

  /// SPDX expression.
  final String license;

  /// `dynamic`, `static-or-dynamic` or `build-only`.
  final String linking;
  final String textId;
  final List<String> platforms;
  final String? sourceUrl;
  final String? sourceSha256;

  /// Files of the patches applied to the upstream source.
  final List<String> patches;

  /// The exact configure line, kept for the libraries whose licence asks
  /// for it.
  final List<String>? configure;

  /// Whether the library is under the LGPL (the source offer and
  /// replace-the-library notice apply).
  bool get isLgpl => license.contains('LGPL');
}

/// The notices for the native libraries of this build.
@immutable
final class NativeNotices {
  const NativeNotices({
    required this.release,
    required this.releaseUrl,
    required this.components,
    required this.texts,
    this.sourcesUrl,
    this.sourcesSha256,
  });

  factory NativeNotices.parse(String json) {
    final j = jsonDecode(json) as Map<String, Object?>;
    final sources = j['sources'] as Map<String, Object?>?;
    return NativeNotices(
      release: j['release']! as String,
      releaseUrl: j['releaseUrl']! as String,
      sourcesUrl: sources?['url'] as String?,
      sourcesSha256: sources?['sha256'] as String?,
      components: [
        for (final c in j['components']! as List<Object?>)
          NativeComponent.fromJson(c! as Map<String, Object?>),
      ],
      texts: (j['texts']! as Map<String, Object?>).cast<String, String>(),
    );
  }

  /// The pinned `mediahro-deps` release the libraries were built in.
  final String release;
  final String releaseUrl;

  /// The archive with the source of every library of the release.
  final String? sourcesUrl;
  final String? sourcesSha256;
  final List<NativeComponent> components;
  final Map<String, String> texts;

  NativeComponent? component(String name) {
    for (final c in components) {
      if (c.name == name) return c;
    }
    return null;
  }

  String textOf(NativeComponent c) => texts[c.textId] ?? '';

  /// The libraries shipped on [platform].
  List<NativeComponent> forPlatform(AppPlatform platform) => [
    for (final c in components)
      if (c.platforms.contains(platform.name)) c,
  ];
}

/// Reads the notices off the UI isolate; null when this build carries none
/// (a platform whose native libraries are not pinned yet).
Future<NativeNotices?> loadNativeNotices([AssetBundle? bundle]) async {
  final String json;
  try {
    json = await (bundle ?? rootBundle).loadString(nativeNoticesAsset);
  } on Object {
    return null;
  }
  return await Isolate.run(() => NativeNotices.parse(json));
}

final nativeNoticesProvider = FutureProvider<NativeNotices?>(
  (ref) => loadNativeNotices(),
);

var _registered = false;

/// Adds the native libraries of [platform] to Flutter's licence list, so the
/// standard licence page shows them with the Dart and Flutter packages. Once
/// per process.
void registerNativeLicences(NativeNotices notices, AppPlatform platform) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final c in notices.forPlatform(platform)) {
      yield LicenseEntryWithLineBreaks([
        '${c.name} ${c.version} (${c.license})',
      ], notices.textOf(c));
    }
  });
}

@visibleForTesting
void resetNativeLicenceRegistration() => _registered = false;
