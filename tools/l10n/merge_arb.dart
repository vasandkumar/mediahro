// Merges per-module ARB fragments into the files `flutter gen-l10n` reads
// (ADR-013) and runs the localisation checks (CORE-008).
//
// Each lane keeps its UI strings in its own folder as
// `<owned folder>/l10n/<module>_<locale>.arb` (for example
// `app/lib/features/video/l10n/video_en.arb`). Keys must start with the
// module name so lanes never collide. Output goes to
// `app/lib/app/l10n/arb/app_<locale>.arb` (git-ignored), plus two
// pseudo-locales generated from English: `en_XA` (accented, 40 % longer)
// and `ar_XB` (right-to-left), used by layout tests.
//
// Usage:
//   dart run tools/l10n/merge_arb.dart            # merge
//   dart run tools/l10n/merge_arb.dart --check    # merge + fail on errors
//   dart run tools/l10n/merge_arb.dart --report   # missing-string report
//   dart run tools/l10n/merge_arb.dart --weblate  # rewrite Weblate config
//
// --check fails on: misnamed fragments, invalid JSON, keys without the
// module prefix, duplicate keys, translations without an English template,
// malformed ICU messages, translations using placeholders the template does
// not have, and a stale `tools/l10n/weblate/components.json`.
//
// --report prints missing translations per locale and module, writes
// build/l10n/missing.md and missing.json, and appends the table to the
// GitHub Actions job summary when GITHUB_STEP_SUMMARY is set.
import 'dart:convert';
import 'dart:io';

import 'pseudo.dart';

/// Launch languages (CORE-008) plus RTL verification locales.
const launchLocales = [
  'en',
  'pt_BR',
  'es',
  'hi',
  'id',
  'de',
  'fr',
  'ja',
  'ru',
  'tr',
  'zh_Hans',
  'it',
  'ar',
  'he',
];
const templateLocale = 'en';
const pseudoExpandedLocale = 'en_XA';
const pseudoRtlLocale = 'ar_XB';
const weblateConfig = 'tools/l10n/weblate/components.json';

void main(List<String> args) {
  final root = _repoRoot();
  final libDir = Directory('${root.path}/app/lib');
  final outDir = Directory('${root.path}/app/lib/app/l10n/arb')
    ..createSync(recursive: true);
  final fragmentName = RegExp(
    r'^([a-z][a-zA-Z0-9]*)_([a-z]{2,3}(?:_[A-Za-z]+)?)\.arb$',
  );

  // locale -> merged entries (insertion-ordered by module then key).
  final merged = <String, Map<String, Object?>>{};
  final owner = <String, String>{}; // locale/key -> fragment path
  final moduleOf = <String, String>{}; // key -> module
  final modulePaths = <String, String>{}; // module -> fragment folder
  final errors = <String>[];

  final fragments =
      libDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .where(
            (f) =>
                _segments(f.path).contains('l10n') &&
                !_segments(f.path).contains('arb') &&
                !_segments(f.path).contains('gen'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in fragments) {
    final name = f.uri.pathSegments.last;
    final m = fragmentName.firstMatch(name);
    if (m == null) {
      errors.add(
        '${_rel(root, f)}: fragment must be named <module>_<locale>.arb',
      );
      continue;
    }
    final module = m.group(1)!;
    final locale = m.group(2)!;
    final dir = _rel(root, f.parent);
    final known = modulePaths[module];
    if (known != null && known != dir) {
      errors.add('${_rel(root, f)}: module "$module" also lives in $known');
    }
    modulePaths[module] = dir;
    final Object? decoded;
    try {
      decoded = jsonDecode(f.readAsStringSync());
    } on FormatException catch (e) {
      errors.add('${_rel(root, f)}: invalid JSON (${e.message})');
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      errors.add('${_rel(root, f)}: top level must be an object');
      continue;
    }
    final target = merged.putIfAbsent(locale, () => {'@@locale': locale});
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key == '@@locale') {
        if (entry.value != locale) {
          errors.add(
            '${_rel(root, f)}: @@locale ${entry.value} does not match file name',
          );
        }
        continue;
      }
      final bare = key.startsWith('@') ? key.substring(1) : key;
      if (!bare.startsWith(module)) {
        errors.add(
          '${_rel(root, f)}: key "$key" must start with module prefix "$module"',
        );
        continue;
      }
      final ownerKey = '$locale/$key';
      if (owner.containsKey(ownerKey)) {
        errors.add(
          '${_rel(root, f)}: duplicate key "$key" (also in ${owner[ownerKey]})',
        );
        continue;
      }
      owner[ownerKey] = _rel(root, f);
      moduleOf[bare] = module;
      final value = entry.value;
      if (!key.startsWith('@')) {
        if (value is! String) {
          errors.add('${_rel(root, f)}: "$key" must be a string');
          continue;
        }
        final icu = icuError(value);
        if (icu != null) {
          errors.add('${_rel(root, f)}: "$key" is not valid ICU ($icu)');
          continue;
        }
      }
      target[key] = value;
    }
  }

  final template = merged[templateLocale];
  if (template == null) {
    errors.add('no template fragments (*_$templateLocale.arb) found');
  }

  // Every launch locale gets a file (missing strings fall back to English);
  // gen-l10n also needs the bare language for script/region variants.
  final locales = {...launchLocales, ...merged.keys};
  for (final l in [...locales]) {
    if (l.contains('_')) locales.add(l.split('_').first);
  }

  final messageKeys =
      template?.keys.where((k) => !k.startsWith('@')).toSet() ?? <String>{};
  final templatePlaceholders = {
    for (final k in messageKeys) k: _safePlaceholders(template![k]! as String),
  };
  // locale -> module -> missing keys
  final missing = <String, Map<String, List<String>>>{};
  for (final locale in locales) {
    final entries = merged[locale] ?? {'@@locale': locale};
    if (locale != templateLocale) {
      for (final k in entries.keys.where((k) => !k.startsWith('@'))) {
        if (!messageKeys.contains(k)) {
          errors.add('locale $locale: key "$k" has no English template');
          continue;
        }
        final extra = _safePlaceholders(entries[k]! as String)
            .difference(templatePlaceholders[k]!);
        if (extra.isNotEmpty) {
          errors.add(
            'locale $locale: "$k" uses placeholders ${extra.join(', ')} '
            'that the English template does not have',
          );
        }
      }
      final byModule = missing.putIfAbsent(locale, () => {});
      for (final k in messageKeys.where((k) => !entries.containsKey(k))) {
        byModule.putIfAbsent(moduleOf[k] ?? '?', () => []).add(k);
      }
    }
    File('${outDir.path}/app_$locale.arb').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(entries)}\n',
    );
  }

  if (template != null) {
    _writePseudo(outDir, pseudoExpandedLocale, template, pseudoExpand, errors);
    _writePseudo(outDir, pseudoRtlLocale, template, pseudoRtl, errors);
  }

  final components = _weblateComponents(modulePaths);
  final configFile = File('${root.path}/$weblateConfig');
  if (args.contains('--weblate')) {
    configFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(components);
    stdout.writeln('l10n: wrote $weblateConfig');
  } else if (args.contains('--check') &&
      (!configFile.existsSync() ||
          configFile.readAsStringSync().replaceAll('\r\n', '\n') !=
              components)) {
    errors.add(
      '$weblateConfig is out of date: run '
      '`dart run tools/l10n/merge_arb.dart --weblate` and commit it',
    );
  }

  if (args.contains('--report')) {
    _report(root, messageKeys.length, missing);
  }
  for (final e in errors) {
    stderr.writeln('l10n: $e');
  }
  if (errors.isNotEmpty && (args.contains('--check') || template == null)) {
    exit(1);
  }
  stdout.writeln(
    'l10n: merged ${fragments.length} fragments into ${locales.length} '
    'locales + 2 pseudo-locales',
  );
}

Set<String> _safePlaceholders(String message) {
  try {
    return placeholdersOf(message);
  } on FormatException {
    return const {};
  }
}

void _writePseudo(
  Directory outDir,
  String locale,
  Map<String, Object?> template,
  String Function(String) transform,
  List<String> errors,
) {
  final out = <String, Object?>{'@@locale': locale};
  for (final e in template.entries) {
    if (e.key.startsWith('@')) continue;
    try {
      out[e.key] = transform(e.value! as String);
    } on FormatException catch (x) {
      errors.add('pseudo $locale: "${e.key}" ${x.message}');
    }
  }
  File(
    '${outDir.path}/app_$locale.arb',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
}

/// One Weblate component per fragment glob (ADR-013). Applied with the
/// Weblate API or `wlc`; see tools/l10n/weblate/README.md.
String _weblateComponents(Map<String, String> modulePaths) {
  final modules = modulePaths.keys.toList()..sort();
  final list = [
    for (final m in modules)
      {
        'name': m,
        'slug': m.replaceAllMapped(
          RegExp('[A-Z]'),
          (x) => '-${x[0]!.toLowerCase()}',
        ),
        'file_format': 'arb',
        'filemask': '${modulePaths[m]}/${m}_*.arb',
        'template': '${modulePaths[m]}/${m}_$templateLocale.arb',
        'new_base': '${modulePaths[m]}/${m}_$templateLocale.arb',
        'source_language': templateLocale,
        'language_regex': r'^(?!en$)[a-z]{2,3}(_[A-Za-z]+)?$',
        'edit_template': false,
      },
  ];
  return '${const JsonEncoder.withIndent('  ').convert({'project': 'mediahro', 'repo': 'https://github.com/vasandkumar/mediahro.git', 'branch': 'main', 'components': list})}\n';
}

void _report(
  Directory root,
  int total,
  Map<String, Map<String, List<String>>> missing,
) {
  final locales = missing.keys.toList()..sort();
  final modules = {for (final m in missing.values) ...m.keys}.toList()..sort();
  stdout.writeln('$total messages in template');
  final md = StringBuffer()
    ..writeln('### Localisation: missing translations')
    ..writeln()
    ..writeln('$total English messages. Missing strings fall back to English.')
    ..writeln()
    ..writeln('| Locale | Missing | ${modules.join(' | ')} |')
    ..writeln('|---|---|${'---|' * modules.length}');
  for (final l in locales) {
    final byModule = missing[l]!;
    final count = byModule.values.fold<int>(0, (a, b) => a + b.length);
    stdout.writeln('  ${l.padRight(8)} missing $count');
    md.writeln(
      '| $l | $count | '
      '${modules.map((m) => byModule[m]?.length ?? 0).join(' | ')} |',
    );
  }
  final dir = Directory('${root.path}/build/l10n')..createSync(recursive: true);
  File('${dir.path}/missing.md').writeAsStringSync(md.toString());
  File('${dir.path}/missing.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(missing)}\n',
  );
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync(md.toString(), mode: FileMode.append);
  }
}

List<String> _segments(String path) => path.replaceAll(r'\', '/').split('/');

String _rel(Directory root, FileSystemEntity f) => f.path
    .replaceAll(r'\', '/')
    .replaceFirst('${root.path.replaceAll(r'\', '/')}/', '');

Directory _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (!File('${dir.path}/CLAUDE.md').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('repo root not found');
    dir = parent;
  }
  return dir;
}
