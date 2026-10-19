// Merges per-module ARB fragments into the files `flutter gen-l10n` reads.
//
// Each lane keeps its UI strings in its own folder as
// `<owned folder>/l10n/<module>_<locale>.arb` (for example
// `app/lib/features/video/l10n/video_en.arb`). Keys must start with the
// module name so lanes never collide. Output goes to
// `app/lib/app/l10n/arb/app_<locale>.arb` (git-ignored).
//
// Usage:
//   dart run tools/l10n/merge_arb.dart          # merge
//   dart run tools/l10n/merge_arb.dart --check  # merge + fail on orphan keys
//   dart run tools/l10n/merge_arb.dart --report # also print missing counts
import 'dart:convert';
import 'dart:io';

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
  final owner = <String, String>{}; // key -> fragment path
  final errors = <String>[];

  final fragments =
      libDir
          .listSync(recursive: true)
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
      target[key] = entry.value;
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
  final report = <String, int>{};
  for (final locale in locales) {
    final entries = merged[locale] ?? {'@@locale': locale};
    if (locale != templateLocale) {
      final orphans = entries.keys.where(
        (k) => !k.startsWith('@') && !messageKeys.contains(k),
      );
      for (final o in orphans) {
        errors.add('locale $locale: key "$o" has no English template');
      }
      report[locale] = messageKeys.where((k) => !entries.containsKey(k)).length;
    }
    File('${outDir.path}/app_$locale.arb').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(entries)}\n',
    );
  }

  if (args.contains('--report')) {
    stdout.writeln('${messageKeys.length} messages in template');
    for (final e
        in report.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      stdout.writeln('  ${e.key.padRight(8)} missing ${e.value}');
    }
  }
  for (final e in errors) {
    stderr.writeln('l10n: $e');
  }
  if (errors.isNotEmpty && (args.contains('--check') || template == null)) {
    exit(1);
  }
  stdout.writeln(
    'l10n: merged ${fragments.length} fragments into ${locales.length} locales',
  );
}

List<String> _segments(String path) => path.replaceAll(r'\', '/').split('/');

String _rel(Directory root, File f) => f.path
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
