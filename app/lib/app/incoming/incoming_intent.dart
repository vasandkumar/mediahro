import 'package:mediahro/platform/system_integration.dart';
import 'package:meta/meta.dart';

/// What an app intent or shortcut (SYS-003) does inside Mediahro. Intents come
/// from the launcher, the Assistant or another app and are untrusted: they only
/// ever move between the top-level screens.
@immutable
sealed class IncomingAction {
  const IncomingAction();
}

/// Show [location] (a shell route, possibly with a `q` search query).
final class IncomingGo extends IncomingAction {
  const IncomingGo(this.location);

  final String location;
}

/// Start the playlist called [name] in Music.
final class IncomingPlaylist extends IncomingAction {
  const IncomingPlaylist(this.name);

  final String name;
}

/// Show the mode the app was last used in.
final class IncomingResume extends IncomingAction {
  const IncomingResume();
}

/// Nothing to do: an argument the app does not understand.
final class IncomingIgnore extends IncomingAction {
  const IncomingIgnore();
}

/// The longest search text taken from outside.
const incomingQueryLimit = 200;

/// Words that name the vault, hidden albums or private mode. An intent that
/// names one never opens it: the user lands on the Photos tab, where the
/// vault asks for its normal unlock (IMG-011, PRIV-007).
final _sensitive = RegExp(
  'vault|private|hidden|secret|locked|safe|decoy|incognito',
  caseSensitive: false,
);

/// Whether [text] names the vault, hidden albums or private mode.
bool namesSensitiveArea(String? text) =>
    text != null && _sensitive.hasMatch(text);

/// What to do for [intent].
IncomingAction actionForIntent(AppIntent intent) {
  final arg = intent.argument?.trim();
  switch (intent.kind) {
    case AppIntentKind.resumeLast:
      return const IncomingResume();
    case AppIntentKind.openMode:
      if (namesSensitiveArea(arg)) return const IncomingGo('/photos');
      return switch (arg?.toLowerCase()) {
        'video' => const IncomingGo('/video'),
        'music' => const IncomingGo('/music'),
        'photos' => const IncomingGo('/photos'),
        'search' => const IncomingGo('/search'),
        _ => const IncomingIgnore(),
      };
    case AppIntentKind.playPlaylist:
      // A playlist that names the vault, hidden albums or private mode is never
      // looked up: Music opens and nothing starts.
      final name = cleanText(arg);
      if (name.isEmpty || namesSensitiveArea(name)) {
        return const IncomingGo('/music');
      }
      return IncomingPlaylist(name);
    case AppIntentKind.search:
      return IncomingGo(searchLocation(arg));
  }
}

/// The search route for [text] (shared text, a voice search): trimmed, cut to
/// [incomingQueryLimit] and stripped of control characters. Never fetched.
String searchLocation(String? text) {
  final query = cleanText(text);
  if (query.isEmpty) return '/search';
  return Uri(path: '/search', queryParameters: {'q': query}).toString();
}

/// [text] from outside made safe to show or look up: control characters turned
/// into spaces, trimmed, cut to [incomingQueryLimit].
String cleanText(String? text) {
  final clean = (text ?? '')
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .trim();
  return clean.length > incomingQueryLimit
      ? clean.substring(0, incomingQueryLimit)
      : clean;
}
