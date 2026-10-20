// Project rules the analyzer cannot express (CLAUDE.md §1, §4).
//
//   dart run tools/lints/check_rules.dart
//
// Exit code 1 lists every violation as `path:line rule message`.
import 'dart:io';

final class Rule {
  const Rule(
    this.id,
    this.message,
    this.pattern, {
    required this.appliesTo,
    this.allowedIn = const [],
  });

  final String id;
  final String message;
  final RegExp pattern;

  /// Path prefixes (repo-relative, forward slashes) the rule scans.
  final List<String> appliesTo;

  /// Path prefixes exempt from the rule.
  final List<String> allowedIn;

  bool covers(String path) =>
      appliesTo.any(path.startsWith) &&
      !allowedIn.any(path.startsWith) &&
      !_generated.hasMatch(path);
}

final _generated = RegExp(
  r'\.(g|freezed|pigeon|mocks)\.dart$|/l10n/gen/|_bindings\.dart$',
);

final rules = <Rule>[
  Rule(
    'no_direct_channel',
    'Platform channels only inside platform modules; use a typed facade (docs/05 §8).',
    RegExp(
      r'\b(MethodChannel|EventChannel|BasicMessageChannel|OptionalMethodChannel)\s*\(',
    ),
    appliesTo: ['app/lib/', 'packages/'],
    allowedIn: [
      'app/lib/platform/',
      'packages/mediahro_engine/lib/src/bridge/',
    ],
  ),
  Rule(
    'no_direct_http',
    'Outbound HTTP only through NetworkGateway / HttpTransport (PRIV-004).',
    RegExp(
      r'''\bHttpClient\s*\(|import\s+['"]package:(http|dio)/|\bWebSocket\.connect\(''',
    ),
    appliesTo: ['app/lib/', 'packages/'],
    allowedIn: ['app/lib/core/net/'],
  ),
  Rule(
    'no_ui_literal',
    'UI strings come from ARB fragments via AppLocalizations (CLAUDE.md §1.9).',
    RegExp(
      r'''\b(Text|SelectableText|Tooltip)\(\s*['"][^'"]*[A-Za-z]|\b(tooltip|semanticLabel|semanticsLabel|labelText|hintText|helperText|errorText|label)\s*:\s*['"][^'"]*[A-Za-z]''',
    ),
    appliesTo: ['app/lib/', 'packages/mediahro_design/lib/'],
  ),
  Rule(
    'no_string_concat_ui',
    'Never concatenate localised strings; use ARB placeholders (CLAUDE.md §1.9).',
    RegExp(r'\bl10n\.\w+(\([^)]*\))?\s*\+|\+\s*l10n\.\w+'),
    appliesTo: ['app/lib/', 'packages/mediahro_design/lib/'],
  ),
  Rule(
    'no_dynamic',
    'No `dynamic` in library code (CLAUDE.md §4); model JSON with typed classes.',
    RegExp(r'\bdynamic\b'),
    appliesTo: ['app/lib/', 'packages/'],
    allowedIn: ['packages/mediahro_engine/example/'],
  ),
  Rule(
    'no_telemetry_sdk',
    'Telemetry SDKs only in the opt-in privacy module (PRIV-001…003).',
    RegExp(
      r'''import\s+['"]package:(sentry|sentry_flutter|aptabase_flutter|firebase_\w+|amplitude\w*|mixpanel\w*)/''',
    ),
    appliesTo: ['app/lib/', 'packages/'],
    allowedIn: ['app/lib/features/privacy/'],
  ),
];

void main(List<String> args) {
  final root = _repoRoot();
  final violations = <String>[];
  var scanned = 0;
  for (final dirName in ['app/lib', 'packages']) {
    final dir = Directory('${root.path}/$dirName');
    if (!dir.existsSync()) continue;
    for (final f
        in dir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = f.path
          .replaceAll(r'\', '/')
          .substring(root.path.replaceAll(r'\', '/').length + 1);
      if (rel.contains('/.dart_tool/') ||
          rel.contains('/build/') ||
          rel.contains('/test/') ||
          rel.contains('/ephemeral/') ||
          rel.contains('/.plugin_symlinks/')) {
        continue;
      }
      final active = rules.where((r) => r.covers(rel)).toList();
      if (active.isEmpty) continue;
      scanned++;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = _stripComment(line);
        if (code.trim().isEmpty) continue;
        final prev = i > 0 ? lines[i - 1] : '';
        for (final r in active) {
          if (!r.pattern.hasMatch(code)) continue;
          if (prev.contains('mediahro-lint: allow ${r.id}') ||
              line.contains('mediahro-lint: allow ${r.id}')) {
            continue;
          }
          violations.add('$rel:${i + 1} ${r.id} ${r.message}');
        }
      }
    }
  }
  violations.forEach(stderr.writeln);
  stdout.writeln(
    'check_rules: $scanned files, ${violations.length} violations',
  );
  if (violations.isNotEmpty) exit(1);
}

String _stripComment(String line) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) return '';
  return line;
}

Directory _repoRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (!File('${dir.path}/CLAUDE.md').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('repo root not found');
    dir = parent;
  }
  return dir;
}
