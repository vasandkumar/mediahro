import 'package:mediahro/core/db/tables.dart';
import 'package:mediahro/core/index/media_kind.dart';
import 'package:meta/meta.dart';

enum SidecarKind { subtitle, audio, nfo, artwork, chapters, lyrics }

/// A file that belongs to a media file (FILE-006): `Movie.en.forced.srt`
/// next to `Movie.mkv`, `Movie.ac3`, `Movie.nfo`, `Movie-poster.jpg`.
@immutable
final class Sidecar {
  const Sidecar(
    this.name,
    this.kind, {
    this.language,
    this.forced = false,
    this.sdh = false,
    this.isDefault = false,
    this.title,
  });

  final String name;
  final SidecarKind kind;

  /// BCP-47-ish code from the name (`en`, `pt-BR`, `zh-Hans`, `eng`).
  final String? language;
  final bool forced;

  /// Hearing-impaired (`.sdh.`, `.hi.`, `.cc.`).
  final bool sdh;
  final bool isDefault;

  /// Free-text label between the base name and the language.
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is Sidecar &&
      other.name == name &&
      other.kind == kind &&
      other.language == language &&
      other.forced == forced &&
      other.sdh == sdh &&
      other.isDefault == isDefault &&
      other.title == title;

  @override
  int get hashCode =>
      Object.hash(name, kind, language, forced, sdh, isDefault, title);

  @override
  String toString() =>
      'Sidecar($name, $kind, $language, forced: $forced, sdh: $sdh)';
}

const _audioSidecar = {
  'ac3',
  'eac3',
  'dts',
  'aac',
  'mka',
  'flac',
  'opus',
  'mp3',
  'thd',
};
const _artwork = {'jpg', 'jpeg', 'png', 'webp'};
const _artworkSuffixes = {
  'poster',
  'fanart',
  'backdrop',
  'thumb',
  'banner',
  'cover',
  'folder',
};

// ISO 639-1 / 639-2 codes and common names that appear in sidecar names.
const _languageNames = {
  'english': 'en', 'french': 'fr', 'german': 'de', 'spanish': 'es', //
  'italian': 'it', 'portuguese': 'pt', 'russian': 'ru', 'japanese': 'ja',
  'chinese': 'zh', 'korean': 'ko', 'arabic': 'ar', 'hebrew': 'he',
  'hindi': 'hi', 'turkish': 'tr', 'dutch': 'nl', 'polish': 'pl',
  'swedish': 'sv', 'indonesian': 'id',
};
final RegExp _langCode = RegExp(
  r'^([a-z]{2,3})(?:[-_]([a-z]{2}|[a-z]{4}|\d{3}))?$',
  caseSensitive: false,
);

/// Sidecars of [mediaName] among [siblings] (names in the same folder).
/// Matching is by base name, case-insensitive; the media file itself and
/// other media files are never sidecars.
List<Sidecar> findSidecars(String mediaName, Iterable<String> siblings) {
  final base = _stem(mediaName).toLowerCase();
  final out = <Sidecar>[];
  for (final s in siblings) {
    if (s == mediaName) continue;
    final ext = MediaKinds.extensionOf(s);
    final stem = _stem(s);
    final lower = stem.toLowerCase();
    if (lower != base &&
        !lower.startsWith('$base.') &&
        !lower.startsWith('$base-') &&
        !lower.startsWith('${base}_')) {
      continue;
    }
    final rest = stem.substring(base.length).replaceFirst(RegExp('^[._-]'), '');
    final tokens = rest.isEmpty ? <String>[] : rest.split(RegExp('[._]'));
    final kind = switch (ext) {
      'lrc' => SidecarKind.lyrics,
      'nfo' => SidecarKind.nfo,
      'xml' when lower.endsWith('chapters') => SidecarKind.chapters,
      _ when MediaKinds.subtitle.contains(ext) => SidecarKind.subtitle,
      _
          when _audioSidecar.contains(ext) &&
              MediaKinds.classify(mediaName) == ItemKind.video =>
        SidecarKind.audio,
      _
          when _artwork.contains(ext) &&
              (tokens.isEmpty ||
                  tokens.any(
                    (t) => _artworkSuffixes.contains(t.toLowerCase()),
                  ) ||
                  rest.isEmpty) =>
        SidecarKind.artwork,
      _ => null,
    };
    if (kind == null) continue;
    String? lang;
    var forced = false;
    var sdh = false;
    var isDefault = false;
    final title = <String>[];
    for (final t in tokens) {
      final l = t.toLowerCase();
      if (l == 'forced') {
        forced = true;
      } else if (l == 'sdh' || l == 'hi' && lang != null || l == 'cc') {
        sdh = true;
      } else if (l == 'default') {
        isDefault = true;
      } else if (lang == null && _languageNames.containsKey(l)) {
        lang = _languageNames[l];
      } else if (lang == null &&
          _langCode.hasMatch(t) &&
          !_artworkSuffixes.contains(l)) {
        final m = _langCode.firstMatch(t)!;
        final region = m.group(2);
        lang = region == null
            ? m.group(1)!.toLowerCase()
            : '${m.group(1)!.toLowerCase()}-${region.length == 4 ? region[0].toUpperCase() + region.substring(1).toLowerCase() : region.toUpperCase()}';
      } else if (!_artworkSuffixes.contains(l)) {
        title.add(t);
      }
    }
    out.add(
      Sidecar(
        s,
        kind,
        language: lang,
        forced: forced,
        sdh: sdh,
        isDefault: isDefault,
        title: title.isEmpty ? null : title.join(' '),
      ),
    );
  }
  return out;
}

/// New names for sidecars when [oldMedia] is renamed to [newMedia], so
/// they stay together (FILE-006): `Old.en.srt` → `New.en.srt`.
Map<String, String> renameSidecars(
  String oldMedia,
  String newMedia,
  Iterable<String> siblings,
) {
  final oldStem = _stem(oldMedia);
  final newStem = _stem(newMedia);
  return {
    for (final s in findSidecars(oldMedia, siblings))
      s.name: '$newStem${s.name.substring(oldStem.length)}',
  };
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
