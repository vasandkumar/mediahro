import 'package:mediahro_subtitles/src/subtitle_parser.dart';
import 'package:meta/meta.dart';

/// A subtitle file that belongs to a video (SUB-012).
@immutable
final class SidecarMatch {
  const SidecarMatch({
    required this.folder,
    required this.name,
    required this.format,
    this.language,
    this.forced = false,
    this.hearingImpaired = false,
    this.companions = const [],
  });

  /// Folder relative to the video's folder ('' for the same folder).
  final String folder;
  final String name;
  final SubtitleFormat format;

  /// ISO 639-1 code when the name carries one.
  final String? language;
  final bool forced;
  final bool hearingImpaired;

  /// Files that must travel with this one (the `.sub` of a VobSub `.idx`).
  final List<String> companions;

  String get path => folder.isEmpty ? name : '$folder/$name';

  @override
  String toString() => 'SidecarMatch($path, $language)';
}

/// Extensions treated as subtitles next to a video. `.txt` is left out:
/// alone it is far more often notes than subtitles.
const _extensions = {
  'srt', 'ass', 'ssa', 'vtt', 'webvtt', 'sub', 'idx', 'sup', 'smi', 'sami', //
  'ttml', 'dfxp', 'lrc',
};

bool isSubtitleName(String name) => _extensions.contains(_ext(name));

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String _stem(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? name : name.substring(0, i);
}

/// Folders searched besides the video's own (scene-release layout).
List<String> sidecarFolders(String videoName) => [
  'Subs',
  'Subs/${_stem(videoName)}',
];

/// Finds the subtitle files for [videoName] among [files] (folder relative
/// to the video's folder, file name) (SUB-012):
///
/// - in the same folder, files named like the video, with optional tags
///   after it: `Film.srt`, `Film.en.srt`, `Film.eng.forced.ass`,
///   `Film.English.sdh.vtt`;
/// - in `Subs/` and `Subs/<video name>/`, every subtitle file, its
///   language read from the name (`2_English.srt`);
/// - a VobSub `.idx` keeps its `.sub` as a companion; a `.sub` alone is
///   MicroDVD text.
///
/// Matching ignores case. Order follows [files].
List<SidecarMatch> matchSidecars(
  String videoName,
  Iterable<(String, String)> files,
) {
  final stem = _stem(videoName).toLowerCase();
  final subsFolders = {
    for (final f in sidecarFolders(videoName)) f.toLowerCase(),
  };
  final list = files.toList();
  final idxStems = {
    for (final (folder, name) in list)
      if (_ext(name) == 'idx')
        '${folder.toLowerCase()}/${_stem(name).toLowerCase()}',
  };
  final out = <SidecarMatch>[];
  for (final (folder, name) in list) {
    final ext = _ext(name);
    if (!_extensions.contains(ext)) continue;
    final base = _stem(name);
    final key = '${folder.toLowerCase()}/${base.toLowerCase()}';
    // The .sub half of a VobSub pair is carried by its .idx.
    if (ext == 'sub' && idxStems.contains(key)) continue;
    List<String> tags;
    if (folder.isEmpty) {
      final lower = base.toLowerCase();
      if (lower == stem) {
        tags = const [];
      } else if (lower.startsWith('$stem.')) {
        tags = base.substring(stem.length + 1).split('.');
      } else {
        continue;
      }
    } else if (subsFolders.contains(folder.toLowerCase())) {
      tags = base.split(RegExp(r'[._\-\s]+'));
    } else {
      continue;
    }
    final format =
        subtitleFormatForExtension(ext) ??
        (ext == 'idx' ? SubtitleFormat.vobSub : SubtitleFormat.srt);
    String? language;
    var forced = false;
    var sdh = false;
    for (final t in tags) {
      final l = t.toLowerCase();
      if (l == 'forced') {
        forced = true;
      } else if (l == 'sdh' || l == 'cc' || l == 'hi') {
        sdh = true;
      } else {
        language ??= _language(l);
      }
    }
    final companions = <String>[];
    if (ext == 'idx') {
      for (final (f2, n2) in list) {
        if (f2 == folder &&
            _ext(n2) == 'sub' &&
            _stem(n2).toLowerCase() == base.toLowerCase()) {
          companions.add(n2);
        }
      }
    }
    out.add(
      SidecarMatch(
        folder: folder,
        name: name,
        format: ext == 'idx' ? SubtitleFormat.vobSub : format,
        language: language,
        forced: forced,
        hearingImpaired: sdh,
        companions: companions,
      ),
    );
  }
  return out;
}

/// The language a subtitle file name carries in its dot-separated tags
/// (`Film.en.srt`, `Film.English.forced.ass`), as ISO 639-1; null when
/// none.
String? languageOfName(String name) {
  final parts = _stem(name).split(RegExp(r'[._\-\s]+'));
  for (final t in parts.skip(1).toList().reversed) {
    final l = t.toLowerCase();
    if (l == 'forced' || l == 'sdh' || l == 'cc' || l == 'hi') continue;
    final lang = _language(l);
    if (lang != null) return lang;
  }
  return null;
}

String? _language(String tag) {
  if (_names.containsKey(tag)) return _names[tag];
  if (_iso639_2.containsKey(tag)) return _iso639_2[tag];
  if (tag.length == 2 && _iso639_2.containsValue(tag)) return tag;
  return null;
}

/// English language names often used in file names.
const _names = {
  'english': 'en', 'german': 'de', 'deutsch': 'de', 'french': 'fr', //
  'francais': 'fr', 'spanish': 'es', 'espanol': 'es', 'italian': 'it',
  'portuguese': 'pt', 'brazilian': 'pt', 'dutch': 'nl', 'swedish': 'sv',
  'norwegian': 'no', 'danish': 'da', 'finnish': 'fi', 'polish': 'pl',
  'czech': 'cs', 'slovak': 'sk', 'hungarian': 'hu', 'romanian': 'ro',
  'bulgarian': 'bg', 'greek': 'el', 'turkish': 'tr', 'russian': 'ru',
  'ukrainian': 'uk', 'arabic': 'ar', 'hebrew': 'he', 'persian': 'fa',
  'hindi': 'hi', 'tamil': 'ta', 'telugu': 'te', 'bengali': 'bn',
  'thai': 'th', 'vietnamese': 'vi', 'indonesian': 'id', 'malay': 'ms',
  'chinese': 'zh', 'japanese': 'ja', 'korean': 'ko', 'croatian': 'hr',
  'serbian': 'sr', 'slovenian': 'sl', 'estonian': 'et', 'latvian': 'lv',
  'lithuanian': 'lt', 'icelandic': 'is', 'catalan': 'ca',
};

/// ISO 639-2 (B and T) to 639-1.
const _iso639_2 = {
  'eng': 'en', 'ger': 'de', 'deu': 'de', 'fre': 'fr', 'fra': 'fr', //
  'spa': 'es', 'ita': 'it', 'por': 'pt', 'dut': 'nl', 'nld': 'nl',
  'swe': 'sv', 'nor': 'no', 'nob': 'no', 'dan': 'da', 'fin': 'fi',
  'pol': 'pl', 'cze': 'cs', 'ces': 'cs', 'slo': 'sk', 'slk': 'sk',
  'hun': 'hu', 'rum': 'ro', 'ron': 'ro', 'bul': 'bg', 'gre': 'el',
  'ell': 'el', 'tur': 'tr', 'rus': 'ru', 'ukr': 'uk', 'ara': 'ar',
  'heb': 'he', 'per': 'fa', 'fas': 'fa', 'hin': 'hi', 'tam': 'ta',
  'tel': 'te', 'ben': 'bn', 'tha': 'th', 'vie': 'vi', 'ind': 'id',
  'may': 'ms', 'msa': 'ms', 'chi': 'zh', 'zho': 'zh', 'jpn': 'ja',
  'kor': 'ko', 'hrv': 'hr', 'srp': 'sr', 'slv': 'sl', 'est': 'et',
  'lav': 'lv', 'lit': 'lt', 'ice': 'is', 'isl': 'is', 'cat': 'ca',
  // Two-letter codes map to themselves.
  'en': 'en', 'de': 'de', 'fr': 'fr', 'es': 'es', 'it': 'it', 'pt': 'pt',
  'nl': 'nl', 'sv': 'sv', 'no': 'no', 'da': 'da', 'fi': 'fi', 'pl': 'pl',
  'cs': 'cs', 'sk': 'sk', 'hu': 'hu', 'ro': 'ro', 'bg': 'bg', 'el': 'el',
  'tr': 'tr', 'ru': 'ru', 'uk': 'uk', 'ar': 'ar', 'he': 'he', 'fa': 'fa',
  'ta': 'ta', 'te': 'te', 'bn': 'bn', 'th': 'th', 'vi': 'vi', 'id': 'id',
  'ms': 'ms', 'zh': 'zh', 'ja': 'ja', 'ko': 'ko', 'hr': 'hr', 'sr': 'sr',
  'sl': 'sl', 'et': 'et', 'lv': 'lv', 'lt': 'lt', 'is': 'is', 'ca': 'ca',
};
