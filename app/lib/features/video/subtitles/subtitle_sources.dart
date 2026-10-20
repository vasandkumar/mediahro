import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/video/subtitles/sidecar_loader.dart';
import 'package:mediahro/platform/platform_facades.dart';

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
        return PickedSubtitle(f.name, bytes);
      };
    });

/// Sidecar search over mounted sources, cached in the app data folder.
final sidecarLoaderProvider = Provider<SidecarLoader>((ref) {
  final mounts = ref.watch(mountsProvider);
  return SidecarLoader(
    fileSystemFor: mounts.forUri,
    cacheDir: Directory(
      '${ref.watch(appDataDirectoryProvider).path}/subtitle_cache',
    ),
  );
});
