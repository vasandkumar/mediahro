import 'package:mediahro/core/db/tables.dart';

/// File-extension classification used by the scanner (LIB-001). Content
/// sniffing happens later in the prober; this only decides what to index.
abstract final class MediaKinds {
  static const video = {
    '3g2', '3gp', 'asf', 'avi', 'divx', 'f4v', 'flv', 'hevc', 'm2t', //
    'm2ts', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'mts', 'mxf',
    'ogv', 'rm', 'rmvb', 'ts', 'vob', 'webm', 'wmv', 'wtv', 'y4m',
  };
  static const audio = {
    'aac', 'ac3', 'aif', 'aifc', 'aiff', 'alac', 'amr', 'ape', 'caf', //
    'dff', 'dsf', 'dts', 'eac3', 'flac', 'it', 'm4a', 'm4b', 'mid', 'midi',
    'mka', 'mod', 'mp2', 'mp3', 'mpc', 'oga', 'ogg', 'opus', 's3m', 'spx',
    'tak', 'tta', 'wav', 'wma', 'wv', 'xm',
  };
  static const image = {
    'apng', 'arw', 'avif', 'bmp', 'cr2', 'cr3', 'dds', 'dng', 'exr', //
    'gif', 'heic', 'heif', 'ico', 'jfif', 'jpeg', 'jpg', 'jxl', 'nef',
    'orf', 'pbm', 'pef', 'pgm', 'png', 'pnm', 'ppm', 'psb', 'psd', 'qoi',
    'raf', 'rw2', 'srw', 'svg', 'tga', 'tif', 'tiff', 'webp',
  };
  static const playlist = {'cue', 'm3u', 'm3u8', 'pls', 'xspf', 'wpl'};
  static const subtitle = {
    'ass', 'dfxp', 'idx', 'lrc', 'sami', 'smi', 'srt', 'ssa', 'sub', //
    'sup', 'ttml', 'vtt',
  };
  static const archive = {
    '7z',
    'cb7',
    'cbr',
    'cbt',
    'cbz',
    'rar',
    'tar',
    'zip',
  };

  /// Lower-case extension without the dot (`''` when there is none).
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static ItemKind classify(String name) {
    final ext = extensionOf(name);
    if (video.contains(ext)) return ItemKind.video;
    if (audio.contains(ext)) return ItemKind.audio;
    if (image.contains(ext)) return ItemKind.image;
    if (playlist.contains(ext)) return ItemKind.playlist;
    if (subtitle.contains(ext)) return ItemKind.subtitle;
    if (archive.contains(ext)) return ItemKind.archive;
    return ItemKind.other;
  }

  /// Whether the scanner indexes a file of [kind] at all.
  static bool indexed(ItemKind kind) => kind != ItemKind.other;
}
