import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/media_store_file_system.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

/// Writing systems for the manual character-set choice (SUB-013).
enum CharsetScript {
  unicode,
  western,
  centralEuropean,
  cyrillic,
  greek,
  turkish,
  hebrew,
  arabic,
  baltic,
  vietnamese,
  chineseSimplified,
  chineseTraditional,
  japanese,
  korean,
  thai,
}

/// iconv names mpv accepts for `sub-codepage`, with their script (SUB-013).
const List<(String, CharsetScript)> subtitleCharsets = [
  ('utf-8', CharsetScript.unicode),
  ('utf-16', CharsetScript.unicode),
  ('cp1252', CharsetScript.western),
  ('iso-8859-15', CharsetScript.western),
  ('cp1250', CharsetScript.centralEuropean),
  ('iso-8859-2', CharsetScript.centralEuropean),
  ('cp1251', CharsetScript.cyrillic),
  ('koi8-r', CharsetScript.cyrillic),
  ('cp866', CharsetScript.cyrillic),
  ('cp1253', CharsetScript.greek),
  ('iso-8859-7', CharsetScript.greek),
  ('cp1254', CharsetScript.turkish),
  ('cp1255', CharsetScript.hebrew),
  ('cp1256', CharsetScript.arabic),
  ('cp1257', CharsetScript.baltic),
  ('cp1258', CharsetScript.vietnamese),
  ('gb18030', CharsetScript.chineseSimplified),
  ('big5', CharsetScript.chineseTraditional),
  ('shift_jis', CharsetScript.japanese),
  ('euc-jp', CharsetScript.japanese),
  ('euc-kr', CharsetScript.korean),
  ('tis-620', CharsetScript.thai),
];

/// "Windows-1251" for `cp1251`; other names upper-cased.
String charsetDisplayName(String iconv) => iconv.startsWith('cp125')
    ? 'Windows-${iconv.substring(2)}'
    : iconv.toUpperCase();

String charsetLabel(AppLocalizations l, String? iconv) {
  if (iconv == null) return l.videoCharsetAuto;
  final script = subtitleCharsets
      .where((c) => c.$1 == iconv)
      .map((c) => c.$2)
      .firstOrNull;
  final name = charsetDisplayName(iconv);
  return script == null
      ? name
      : l.videoCharsetNamed(l.videoCharsetScript(script.name), name);
}

/// A subtitle file the user picked (SUB-012).
@immutable
final class PickedSubtitle {
  const PickedSubtitle(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// The file picked is not a subtitle file (by name or by what is in it).
final class NotASubtitleFile implements Exception {
  const NotASubtitleFile(this.name);

  final String name;

  @override
  String toString() => 'NotASubtitleFile($name)';
}

/// The name to keep a picked file under, or null when it is not a subtitle.
///
/// Providers report `.srt` as `application/x-subrip`, `text/plain` or
/// `application/octet-stream`, and some give names with no extension at all,
/// so the picker takes any file and the check is made here: a known
/// subtitle extension, or else the text itself looks like a subtitle format
/// (and the matching extension is added so the engine recognises it).
String? subtitleNameFor(String name, List<int> bytes) {
  if (isSubtitleName(name)) return name;
  final head = utf8.decode(
    bytes.length > 4000 ? bytes.sublist(0, 4000) : bytes,
    allowMalformed: true,
  );
  final ext = switch (sniffSubtitleFormat(head)) {
    SubtitleFormat.srt => 'srt',
    SubtitleFormat.webvtt => 'vtt',
    SubtitleFormat.ass => 'ass',
    SubtitleFormat.ssa => 'ssa',
    SubtitleFormat.smi => 'smi',
    SubtitleFormat.microDvd => 'sub',
    SubtitleFormat.lrc => 'lrc',
    _ => null,
  };
  if (ext == null) return null;
  final base = name.trim().isEmpty ? 'subtitle' : name.trim();
  return '$base.$ext';
}

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// "Add a subtitle file": the system picker, read through C4's storage
/// facade (Android `content://` via a descriptor). Null where the platform
/// has no picker; tests replace it.
final subtitleFilePickerProvider =
    Provider<Future<PickedSubtitle?> Function()?>((ref) {
      final storage = _optional(() => ref.watch(storageProvider));
      if (storage == null) return null;
      final io = ref.watch(fdIoProvider);
      return () async {
        final picked = await storage.pickFiles(
          kinds: const {PickKind.subtitle},
        );
        if (picked.isEmpty) return null;
        final f = picked.first;
        final bytes = await readPickedFile(
          storage,
          f.uri,
          maxBytes: 20 * 1024 * 1024,
          io: io,
        );
        final name = subtitleNameFor(f.name, bytes);
        developer.log(
          'picked ${f.name} (${bytes.length} bytes) -> $name',
          name: 'mediahro.subtitles',
        );
        if (name == null) throw NotASubtitleFile(f.name);
        return PickedSubtitle(name, bytes);
      };
    });

/// The file systems the sidecar search lists folders through: the mounted
/// sources, except for device media (`mediastore:`). The library's MediaStore
/// tree holds video and audio only, so a subtitle next to a video would never
/// show in it; subtitles come from a MediaStore query of their own, asked
/// again after [maxAge] so a file added meanwhile is found (SUB-012).
final class SidecarFileSystems {
  SidecarFileSystems({
    required this.mounted,
    this.storage,
    this.io,
    this.maxAge = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VirtualFileSystem Function(Uri uri) mounted;
  final StorageFacade? storage;
  final FdIo? io;
  final Duration maxAge;
  final DateTime Function() _clock;

  MediaStoreFileSystem? _subtitles;
  DateTime? _since;

  VirtualFileSystem forUri(Uri uri) {
    final s = storage;
    if (uri.scheme != 'mediastore' || s == null) return mounted(uri);
    final now = _clock();
    final since = _since;
    if (_subtitles == null || since == null || now.difference(since) > maxAge) {
      _subtitles = MediaStoreFileSystem(
        s,
        io: io,
        kinds: const {PickKind.subtitle},
      );
      _since = now;
    }
    return _subtitles!;
  }
}

/// Sidecar search over mounted sources, cached in the app data folder.
final sidecarLoaderProvider = Provider<SidecarLoader>((ref) {
  final mounts = ref.watch(mountsProvider);
  final systems = SidecarFileSystems(
    mounted: mounts.forUri,
    storage: _optional(() => ref.watch(storageProvider)),
    io: ref.watch(fdIoProvider),
  );
  return SidecarLoader(
    fileSystemFor: systems.forUri,
    cacheDir: Directory(
      '${ref.watch(appDataDirectoryProvider).path}/subtitle_cache',
    ),
  );
});
