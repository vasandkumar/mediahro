import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/file_systems.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:meta/meta.dart';

/// Values a rename pattern can use for one file (FILE-003 "metadata tokens").
@immutable
final class RenameFacts {
  const RenameFacts({
    required this.name,
    this.modified,
    this.title,
    this.artist,
    this.album,
    this.track,
    this.year,
    this.season,
    this.episode,
    this.width,
    this.height,
  });

  /// Current file name with extension.
  final String name;
  final DateTime? modified;
  final String? title;
  final String? artist;
  final String? album;
  final int? track;
  final int? year;
  final int? season;
  final int? episode;
  final int? width;
  final int? height;

  String get stem {
    final i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  String get ext {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i + 1);
  }
}

@immutable
final class RenamePlan {
  const RenamePlan(this.from, this.to, {this.conflict = false});

  final String from;
  final String to;

  /// Two files would get the same name (or an invalid one): the UI blocks
  /// "Rename" until the pattern changes.
  final bool conflict;
}

final class PatternError implements Exception {
  const PatternError(this.token);

  final String token;

  @override
  String toString() => 'PatternError($token)';
}

final RegExp _token = RegExp(r'\{([a-z]+)(?::([^}]+))?\}');

/// Expands a batch-rename pattern (FILE-003):
///
/// `{name}` stem · `{ext}` extension · `{n}` / `{n:3}` counter (zero-padded)
/// · `{date}` / `{date:yyyy-MM-dd}` modified date · `{title}` `{artist}`
/// `{album}` · `{track:2}` · `{year}` · `{season:2}` `{episode:2}` ·
/// `{width}` `{height}`. A pattern without `{ext}` keeps the extension.
String expandPattern(
  String pattern,
  RenameFacts f,
  int index, {
  int start = 1,
}) {
  final out = pattern.replaceAllMapped(_token, (m) {
    final key = m.group(1)!;
    final arg = m.group(2);
    String pad(int? v) {
      if (v == null) return '';
      final w = int.tryParse(arg ?? '') ?? 0;
      return v.toString().padLeft(w, '0');
    }

    return switch (key) {
      'name' => f.stem,
      'ext' => f.ext,
      'n' => pad(start + index),
      'date' =>
        f.modified == null ? '' : _date(f.modified!, arg ?? 'yyyy-MM-dd'),
      'title' => f.title ?? f.stem,
      'artist' => f.artist ?? '',
      'album' => f.album ?? '',
      'track' => pad(f.track),
      'year' => f.year?.toString() ?? '',
      'season' => pad(f.season),
      'episode' => pad(f.episode),
      'width' => f.width?.toString() ?? '',
      'height' => f.height?.toString() ?? '',
      _ => throw PatternError(m.group(0)!),
    };
  });
  final clean = out.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return pattern.contains('{ext}') || f.ext.isEmpty ? clean : '$clean.${f.ext}';
}

/// Previews a batch rename; conflicts are flagged, nothing is changed.
List<RenamePlan> planRename(
  List<RenameFacts> files,
  String pattern, {
  int start = 1,
}) {
  final names = [
    for (var i = 0; i < files.length; i++)
      expandPattern(pattern, files[i], i, start: start),
  ];
  final counts = <String, int>{};
  for (final n in names) {
    counts[n.toLowerCase()] = (counts[n.toLowerCase()] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < files.length; i++)
      RenamePlan(
        files[i].name,
        names[i],
        conflict:
            names[i].isEmpty ||
            names[i].startsWith('.') ||
            counts[names[i].toLowerCase()]! > 1,
      ),
  ];
}

String _date(DateTime d, String format) => format
    .replaceAll('yyyy', d.year.toString().padLeft(4, '0'))
    .replaceAll('MM', d.month.toString().padLeft(2, '0'))
    .replaceAll('dd', d.day.toString().padLeft(2, '0'))
    .replaceAll('HH', d.hour.toString().padLeft(2, '0'))
    .replaceAll('mm', d.minute.toString().padLeft(2, '0'))
    .replaceAll('ss', d.second.toString().padLeft(2, '0'));

/// Facts for an indexed item (title, tags from the index).
Future<RenameFacts> factsFor(LibraryDatabase db, ItemRow item) async {
  final audio = await (db.select(
    db.audioMeta,
  )..where((a) => a.itemId.equals(item.id))).getSingleOrNull();
  final video = await (db.select(
    db.videoMeta,
  )..where((v) => v.itemId.equals(item.id))).getSingleOrNull();
  return RenameFacts(
    name: item.name,
    modified: item.mtime,
    title: item.title,
    artist: audio?.artist,
    album: audio?.album,
    track: audio?.trackNumber,
    year: audio?.year ?? video?.year,
    season: video?.seasonNumber,
    episode: video?.episodeNumber,
    width: item.width,
    height: item.height,
  );
}

/// Applies a previewed rename (FILE-003); stops at the first conflict.
Future<List<Uri>> applyRename(
  FileOperations ops,
  List<Uri> uris,
  List<RenamePlan> plan,
) async {
  if (plan.any((p) => p.conflict)) throw const PatternError('conflict');
  final out = <Uri>[];
  for (var i = 0; i < uris.length; i++) {
    out.add(
      plan[i].from == plan[i].to
          ? uris[i]
          : await ops.rename(uris[i], plan[i].to),
    );
  }
  return out;
}

/// Batch image conversion (FILE-003: format, size, quality) through the
/// image pipeline (lane C3). Outputs go next to the originals unless
/// [into] is given; originals are untouched.
Future<List<Uri>> convertImages(
  ImagePipeline pipeline,
  MountedFileSystems fileSystems,
  List<Uri> images,
  EncodeOptions options, {
  Uri? into,
  void Function(int done, int total)? onProgress,
}) async {
  final ext = switch (options.format) {
    EncodeFormat.jpeg => 'jpg',
    EncodeFormat.png => 'png',
    EncodeFormat.webp => 'webp',
    EncodeFormat.avif => 'avif',
    EncodeFormat.jxl => 'jxl',
    EncodeFormat.heic => 'heic',
  };
  final out = <Uri>[];
  for (var i = 0; i < images.length; i++) {
    final src = images[i];
    final segs = src.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segs.last;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final dir =
        into ??
        src.replace(pathSegments: [...segs.sublist(0, segs.length - 1), '']);
    final dest = dir.resolve(Uri.encodeComponent('$stem.$ext'));
    final f = await fileSystems.forUri(src).open(src);
    try {
      await pipeline.export(ImageSource(f), const [], dest, options);
    } finally {
      await f.close();
    }
    out.add(dest);
    onProgress?.call(i + 1, images.length);
  }
  return out;
}
