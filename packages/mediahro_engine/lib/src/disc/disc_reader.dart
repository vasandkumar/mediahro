/// Menu-less playback of unencrypted DVD-Video (`VIDEO_TS`) and Blu-ray
/// (`BDMV`) folders (VID-007) without GPL code: libdvdnav/libdvdread and
/// libdvdcss are banned (docs/09 §2), so the IFO and MPLS/CLPI structures
/// are read here (own MIT-compatible code under the project licence).
///
/// DVD titles play as one [VirtualFile] stitching the title's cell sector
/// ranges across the title set's VOB files; Blu-ray titles play as an mpv
/// EDL over the playlist's clips. Chapters come from the disc structures.
/// Encrypted discs are detected and refused (no AACS/CSS).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/disc/udf.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

enum DiscKind { dvd, bluray }

/// An audio or subtitle stream as declared by the disc.
@immutable
final class DiscStream {
  const DiscStream({this.language, this.codec, this.channels});
  final String? language;
  final String? codec;
  final int? channels;
}

/// One playable title.
@immutable
final class DiscTitle {
  const DiscTitle({
    required this.number,
    required this.duration,
    required this.chapters,
    required this.source,
    this.audio = const [],
    this.subtitles = const [],
    this.angles = 1,
  });

  /// 1-based title number (DVD title or Blu-ray playlist number).
  final int number;
  final Duration duration;
  final List<Chapter> chapters;
  final List<DiscStream> audio;
  final List<DiscStream> subtitles;
  final int angles;

  /// What to open in the engine; pass [chapters] through [OpenOptions].
  final MediaSource source;

  /// Open options carrying the disc's chapters and languages.
  OpenOptions openOptions([OpenOptions base = const OpenOptions()]) =>
      base.copyWith(chapters: chapters);
}

@immutable
final class DiscInfo {
  const DiscInfo({
    required this.kind,
    required this.root,
    required this.titles,
    this.encrypted = false,
  });

  final DiscKind kind;
  final Directory root;
  final List<DiscTitle> titles;

  /// True when the content is CSS/AACS protected; such discs are not played.
  final bool encrypted;

  /// The longest title, which is the feature on almost every disc.
  DiscTitle? get mainTitle => titles.isEmpty
      ? null
      : titles.reduce((a, b) => b.duration > a.duration ? b : a);
}

/// Thrown for malformed disc structures.
final class DiscFormatException implements Exception {
  const DiscFormatException(this.message);
  final String message;
  @override
  String toString() => 'DiscFormatException: $message';
}

/// A file or folder of a disc: a local path or an entry of a UDF image.
abstract interface class _Node {
  String get name;
  bool get isDirectory;

  /// Local path when the node is on the file system (EDL playback).
  String? get path;
  Future<List<_Node>> children();
  Future<int> length();
  VirtualFile open();
}

final class _FsNode implements _Node {
  _FsNode(this.entity);
  final FileSystemEntity entity;

  @override
  String get name =>
      entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';

  @override
  bool get isDirectory => entity is Directory;

  @override
  String? get path => entity.path;

  @override
  Future<List<_Node>> children() async {
    final d = entity;
    if (d is! Directory || !d.existsSync()) return const [];
    return [for (final e in d.listSync()) _FsNode(e)];
  }

  @override
  Future<int> length() => (entity as File).length();

  @override
  VirtualFile open() => _LocalFile(entity as File);
}

final class _UdfNode implements _Node {
  _UdfNode(this.entry);
  final UdfEntry entry;

  @override
  String get name => entry.name;

  @override
  bool get isDirectory => entry.isDirectory;

  @override
  String? get path => null;

  @override
  Future<List<_Node>> children() async => [
    for (final c in await entry.children()) _UdfNode(c),
  ];

  @override
  Future<int> length() async => entry.size;

  @override
  VirtualFile open() => entry.open();
}

/// A local file as a [VirtualFile] (one handle, serialised reads).
final class _LocalFile implements VirtualFile {
  _LocalFile(this._file);
  final File _file;
  RandomAccessFile? _raf;
  Future<void> _lock = Future.value();

  @override
  Uri get uri => _file.uri;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() => _file.length();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    await previous;
    try {
      final raf = _raf ??= await _file.open();
      await raf.setPosition(offset);
      return await raf.read(length);
    } finally {
      done.complete();
    }
  }

  @override
  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }
}

/// Reads disc folders and disc images.
abstract final class DiscReader {
  /// Maximum structure file size read (parser limit, docs/13).
  static const int maxStructureBytes = 16 * 1024 * 1024;

  /// Whether [dir] is (or contains) a `VIDEO_TS` or `BDMV` folder.
  static bool isDiscFolder(Directory dir) {
    bool has(Directory d, String child, {bool folder = false}) =>
        d.existsSync() &&
        d.listSync().any(
          (e) =>
              (folder ? e is Directory : e is File) &&
              _FsNode(e).name.toUpperCase() == child,
        );
    final name = _FsNode(dir).name.toUpperCase();
    if (name == 'VIDEO_TS' && has(dir, 'VIDEO_TS.IFO')) return true;
    if (name == 'BDMV' && has(dir, 'PLAYLIST', folder: true)) return true;
    return has(dir, 'VIDEO_TS', folder: true) || has(dir, 'BDMV', folder: true);
  }

  /// Reads the disc at [dir] (the disc root or the VIDEO_TS/BDMV folder),
  /// or returns null when [dir] is not a disc folder.
  static Future<DiscInfo?> read(Directory dir) async {
    final found = await _locate(_FsNode(dir));
    if (found == null) return null;
    return await _read(found.$1, found.$2, dir.parent);
  }

  /// Reads a UDF disc image (`.iso`) from any source (VID-001), or returns
  /// null when it holds no DVD-Video or Blu-ray structure.
  static Future<DiscInfo?> readImage(
    VirtualFile image, {
    Directory? root,
  }) async {
    if (!await UdfImage.isUdf(image)) return null;
    final udf = await UdfImage.open(image);
    final found = await _locate(_UdfNode(udf.root));
    if (found == null) return null;
    return await _read(found.$1, found.$2, root ?? Directory.systemTemp);
  }

  static Future<DiscInfo> _read(DiscKind kind, _Node folder, Directory root) =>
      switch (kind) {
        DiscKind.dvd => _readDvd(folder, root),
        DiscKind.bluray => _readBluray(folder, root),
      };

  static Future<(DiscKind, _Node)?> _locate(_Node dir) async {
    final name = dir.name.toUpperCase();
    if (name == 'VIDEO_TS' && await _child(dir, 'VIDEO_TS.IFO') != null) {
      return (DiscKind.dvd, dir);
    }
    if (name == 'BDMV' && await _childDir(dir, 'PLAYLIST') != null) {
      return (DiscKind.bluray, dir);
    }
    final dvd = await _childDir(dir, 'VIDEO_TS');
    if (dvd != null && await _child(dvd, 'VIDEO_TS.IFO') != null) {
      return (DiscKind.dvd, dvd);
    }
    final bd = await _childDir(dir, 'BDMV');
    if (bd != null && await _childDir(bd, 'PLAYLIST') != null) {
      return (DiscKind.bluray, bd);
    }
    return null;
  }

  /// Case-insensitive child lookup (discs use upper case; copies may not).
  static Future<_Node?> _child(_Node dir, String name) async {
    for (final e in await dir.children()) {
      if (!e.isDirectory && e.name.toUpperCase() == name) return e;
    }
    return null;
  }

  static Future<_Node?> _childDir(_Node dir, String name) async {
    for (final e in await dir.children()) {
      if (e.isDirectory && e.name.toUpperCase() == name) return e;
    }
    return null;
  }

  static Future<Uint8List> _bytes(_Node f) async {
    final len = await f.length();
    if (len > maxStructureBytes) {
      throw DiscFormatException('${f.name} is too large');
    }
    final v = f.open();
    try {
      return await v.read(0, len);
    } finally {
      await v.close();
    }
  }

  // ------------------------------------------------------------------ DVD --

  static const _sector = 2048;

  static Future<DiscInfo> _readDvd(_Node videoTs, Directory root) async {
    final vmg = await _bytes((await _child(videoTs, 'VIDEO_TS.IFO'))!);
    if (vmg.length < 0x100 ||
        String.fromCharCodes(vmg, 0, 12) != 'DVDVIDEO-VMG') {
      throw const DiscFormatException('VIDEO_TS.IFO: bad signature');
    }
    final r = _Be(vmg);
    final srpt = r.u32(0xC4) * _sector;
    final titleCount = r.u16(srpt);
    final titles = <DiscTitle>[];
    final vtsCache = <int, _Vts>{};
    var encrypted = false;
    for (var t = 0; t < titleCount && t < 99; t++) {
      final o = srpt + 8 + t * 12;
      if (o + 12 > vmg.length) break;
      final angles = vmg[o + 1];
      final vtsNumber = vmg[o + 6];
      final ttn = vmg[o + 7];
      final vts = vtsCache[vtsNumber] ??= await _Vts.read(videoTs, vtsNumber);
      final pgc = vts.pgcForTitle(ttn);
      if (pgc == null) continue;
      encrypted = encrypted || await vts.looksEncrypted();
      titles.add(
        DiscTitle(
          number: t + 1,
          duration: pgc.duration,
          chapters: pgc.chapters,
          audio: vts.audio,
          subtitles: vts.subtitles,
          angles: angles == 0 ? 1 : angles,
          source: VirtualFileSource(
            DvdTitleFile(vts.vobs, vts.vobSizes, pgc.ranges, number: t + 1),
            title: 'Title ${t + 1}',
          ),
        ),
      );
    }
    return DiscInfo(
      kind: DiscKind.dvd,
      root: root,
      titles: titles,
      encrypted: encrypted,
    );
  }

  // -------------------------------------------------------------- Blu-ray --

  static Future<DiscInfo> _readBluray(_Node bdmv, Directory root) async {
    final playlists = (await _childDir(bdmv, 'PLAYLIST'))!;
    final clipinf = await _childDir(bdmv, 'CLIPINF');
    final stream = await _childDir(bdmv, 'STREAM');
    final aacs =
        await _childDir(bdmv, 'AACS') != null ||
        (bdmv.path != null &&
            Directory('${Directory(bdmv.path!).parent.path}/AACS')
                .existsSync());
    final titles = <DiscTitle>[];
    final files =
        (await playlists.children())
            .where(
              (f) => !f.isDirectory && f.name.toLowerCase().endsWith('.mpls'),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    for (final f in files) {
      final mpls = _Mpls.parse(await _bytes(f));
      if (mpls == null || mpls.items.isEmpty || stream == null) continue;
      final segments = <String>[];
      final clips = <VirtualFile>[];
      var total = 0;
      final starts = <int>[];
      var missing = false;
      for (final item in mpls.items) {
        final m2ts = await _child(stream, '${item.clip}.M2TS');
        if (m2ts == null) {
          missing = true;
          break;
        }
        final clpi = clipinf == null
            ? null
            : await _child(clipinf, '${item.clip}.CLPI');
        final clipStart = clpi == null
            ? item.inTime
            : (_clipStart(await _bytes(clpi)) ?? item.inTime);
        starts.add(total);
        final len = item.outTime - item.inTime;
        final path = m2ts.path;
        if (path != null) {
          segments.add(
            '${_edlQuote(path)},'
            '${_seconds(item.inTime - clipStart)},${_seconds(len)}',
          );
        }
        clips.add(m2ts.open());
        total += len;
      }
      if (missing) continue;
      final chapters = <Chapter>[];
      for (final m in mpls.marks) {
        if (m.item >= mpls.items.length) continue;
        final t = starts[m.item] + m.time - mpls.items[m.item].inTime;
        if (t < 0 || t > total) continue;
        chapters.add(Chapter(start: _duration(t)));
      }
      final number = int.tryParse(f.name.split('.').first) ?? titles.length;
      final MediaSource source;
      if (segments.length == clips.length) {
        // An EDL file (not an edl:// URI) keeps mpv's %len% path quoting
        // intact on every platform.
        final edl = File(
          '${(await _edlDir()).path}${Platform.pathSeparator}'
          '${bdmv.path.hashCode.toUnsigned(32)}_$number.edl',
        );
        await edl.writeAsString(
          '# mpv EDL v0\n!no_chapters\n${segments.join('\n')}\n',
        );
        source = UriSource(Uri.file(edl.path), title: 'Playlist $number');
      } else {
        // Inside an image: the playlist's clips back to back (transport
        // streams concatenate; mpv follows the timestamp discontinuities).
        source = VirtualFileSource(
          ConcatenatedFile(clips, name: 'playlist-$number.m2ts'),
          title: 'Playlist $number',
        );
      }
      titles.add(
        DiscTitle(
          number: number,
          duration: _duration(total),
          chapters: chapters,
          audio: mpls.audio,
          subtitles: mpls.subtitles,
          source: source,
        ),
      );
    }
    return DiscInfo(
      kind: DiscKind.bluray,
      root: root,
      titles: titles,
      encrypted: aacs,
    );
  }

  static Directory? _edlTemp;

  static Future<Directory> _edlDir() async =>
      _edlTemp ??= await Directory.systemTemp.createTemp('mediahro-disc');

  static int? _clipStart(Uint8List clpi) {
    if (clpi.length < 0x20 || String.fromCharCodes(clpi, 0, 4) != 'HDMV') {
      return null;
    }
    final r = _Be(clpi);
    final seq = r.u32(0x08);
    // SequenceInfo: length(4) reserved(1) n_atc(1) | SPN_ATC_start(4)
    // n_stc(1) offset_STC_id(1) | PCR_PID(2) SPN_STC_start(4)
    // presentation_start_time(4) presentation_end_time(4)
    final start = seq + 4 + 2 + 4 + 2 + 2 + 4;
    if (start + 4 > clpi.length) return null;
    return r.u32(start);
  }

  /// 45 kHz ticks → seconds string for EDL.
  static String _seconds(int ticks) => (ticks / 45000).toStringAsFixed(6);

  static Duration _duration(int ticks) =>
      Duration(microseconds: (ticks * 1000000 / 45000).round());

  static String _edlQuote(String s) => '%${_utf8Length(s)}%$s';
}

int _utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80
        ? 1
        : r < 0x800
        ? 2
        : r < 0x10000
        ? 3
        : 4;
  }
  return n;
}

/// Big-endian reader with bounds checks.
final class _Be {
  _Be(this.b);
  final Uint8List b;

  void _check(int o, int n) {
    if (o < 0 || o + n > b.length) {
      throw DiscFormatException('read past end at $o');
    }
  }

  int u8(int o) {
    _check(o, 1);
    return b[o];
  }

  int u16(int o) {
    _check(o, 2);
    return b[o] << 8 | b[o + 1];
  }

  int u32(int o) {
    _check(o, 4);
    return b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];
  }
}

// ------------------------------------------------------------- DVD (VTS) --

/// A program chain: cells as sector ranges plus chapter times.
final class _Pgc {
  _Pgc(this.duration, this.chapters, this.ranges);
  final Duration duration;
  final List<Chapter> chapters;

  /// Inclusive sector ranges within the title set's VOBs.
  final List<(int, int)> ranges;
}

final class _Vts {
  _Vts(
    this.vobs,
    this.vobSizes,
    this.audio,
    this.subtitles,
    this._ifo,
    this._pttSrpt,
    this._pgci,
  );

  final List<VirtualFile> vobs;

  /// Sizes in sectors, one per VOB.
  final List<int> vobSizes;
  final List<DiscStream> audio;
  final List<DiscStream> subtitles;
  final Uint8List _ifo;
  final int _pttSrpt;
  final int _pgci;

  static Future<_Vts> read(_Node videoTs, int n) async {
    final name = 'VTS_${n.toString().padLeft(2, '0')}';
    final ifoFile = await DiscReader._child(videoTs, '${name}_0.IFO');
    if (ifoFile == null) throw DiscFormatException('$name: IFO missing');
    final ifo = await DiscReader._bytes(ifoFile);
    if (ifo.length < 0x400 ||
        String.fromCharCodes(ifo, 0, 12) != 'DVDVIDEO-VTS') {
      throw DiscFormatException('$name: bad signature');
    }
    final r = _Be(ifo);
    final vobs = <VirtualFile>[];
    final sizes = <int>[];
    for (var i = 1; i <= 9; i++) {
      final f = await DiscReader._child(videoTs, '${name}_$i.VOB');
      if (f == null) break;
      vobs.add(f.open());
      sizes.add(await f.length() ~/ DiscReader._sector);
    }
    final audioCount = r.u16(0x202).clamp(0, 8);
    final audio = [
      for (var i = 0; i < audioCount; i++) _audioAttr(ifo, 0x204 + i * 8),
    ];
    final subCount = r.u16(0x254).clamp(0, 32);
    final subs = [
      for (var i = 0; i < subCount; i++)
        DiscStream(
          language: _lang(ifo, 0x256 + i * 6, ifo[0x256 + i * 6] & 0x03),
          codec: 'dvd_subtitle',
        ),
    ];
    return _Vts(
      vobs,
      sizes,
      audio,
      subs,
      ifo,
      r.u32(0xC8) * DiscReader._sector,
      r.u32(0xCC) * DiscReader._sector,
    );
  }

  static DiscStream _audioAttr(Uint8List b, int o) {
    final coding = b[o] >> 5;
    return DiscStream(
      language: _lang(b, o, (b[o] >> 2) & 0x03),
      codec: switch (coding) {
        0 => 'ac3',
        2 || 3 => 'mp2',
        4 => 'pcm_dvd',
        6 => 'dts',
        _ => null,
      },
      channels: (b[o + 1] & 0x07) + 1,
    );
  }

  /// ISO 639-1 code at [o] + 2 when [languageType] is 1 (code present).
  static String? _lang(Uint8List b, int o, int languageType) {
    if (languageType != 1) return null;
    final c1 = b[o + 2];
    final c2 = b[o + 3];
    if (c1 < 0x61 || c1 > 0x7A || c2 < 0x61 || c2 > 0x7A) return null;
    return String.fromCharCodes([c1, c2]);
  }

  /// The program chain for VTS title [ttn] (via its first part-of-title).
  _Pgc? pgcForTitle(int ttn) {
    final r = _Be(_ifo);
    final ttuCount = r.u16(_pttSrpt);
    if (ttn < 1 || ttn > ttuCount) return null;
    final ttuOffset = _pttSrpt + r.u32(_pttSrpt + 8 + (ttn - 1) * 4);
    final pgcn = r.u16(ttuOffset);
    final pgcCount = r.u16(_pgci);
    if (pgcn < 1 || pgcn > pgcCount) return null;
    final pgc = _pgci + r.u32(_pgci + 8 + (pgcn - 1) * 8 + 4);
    return _parsePgc(pgc);
  }

  _Pgc _parsePgc(int pgc) {
    final r = _Be(_ifo);
    final programs = r.u8(pgc + 2);
    final cells = r.u8(pgc + 3);
    final programMap = pgc + r.u16(pgc + 0xE6);
    final cellPlayback = pgc + r.u16(pgc + 0xE8);
    final cellTimes = <Duration>[];
    final ranges = <(int, int)>[];
    for (var c = 0; c < cells; c++) {
      final o = cellPlayback + c * 24;
      cellTimes.add(_bcdTime(_ifo, o + 4));
      final first = r.u32(o + 8);
      final last = r.u32(o + 20);
      if (ranges.isNotEmpty && ranges.last.$2 + 1 == first) {
        ranges[ranges.length - 1] = (ranges.last.$1, last);
      } else {
        ranges.add((first, last));
      }
    }
    final chapters = <Chapter>[];
    for (var p = 0; p < programs; p++) {
      final entryCell = r.u8(programMap + p) - 1;
      var t = Duration.zero;
      for (var c = 0; c < entryCell && c < cellTimes.length; c++) {
        t += cellTimes[c];
      }
      chapters.add(Chapter(start: t, title: 'Chapter ${p + 1}'));
    }
    final total = _bcdTime(_ifo, pgc + 4);
    return _Pgc(
      total == Duration.zero
          ? cellTimes.fold(Duration.zero, (a, b) => a + b)
          : total,
      chapters,
      ranges,
    );
  }

  /// DVD BCD time `hh mm ss ff` with the frame rate in the top bits of ff.
  static Duration _bcdTime(Uint8List b, int o) {
    int bcd(int v) => (v >> 4) * 10 + (v & 0x0F);
    final h = bcd(b[o]);
    final m = bcd(b[o + 1]);
    final s = bcd(b[o + 2]);
    final fps = (b[o + 3] >> 6) == 1 ? 25.0 : 29.97;
    final f = bcd(b[o + 3] & 0x3F);
    return Duration(
      microseconds: ((h * 3600 + m * 60 + s) * 1e6 + f / fps * 1e6).round(),
    );
  }

  bool? _encrypted;

  /// CSS-scrambled VOBs carry PES scrambling-control bits.
  Future<bool> looksEncrypted() async {
    if (_encrypted != null) return _encrypted!;
    if (vobs.isEmpty) return _encrypted = false;
    {
      final head = await vobs.first.read(0, 256 * 1024);
      for (var i = 0; i + 7 < head.length; i++) {
        if (head[i] == 0 && head[i + 1] == 0 && head[i + 2] == 1) {
          final id = head[i + 3];
          if (id >= 0xE0 && id <= 0xEF ||
              id == 0xBD ||
              id >= 0xC0 && id <= 0xDF) {
            return _encrypted = (head[i + 6] & 0x30) != 0;
          }
        }
      }
      return _encrypted = false;
    }
  }
}

/// A DVD title's cells across the title set's VOB files, as one seekable
/// [VirtualFile] (mpv reads it through the `mhvf://` stream protocol).
final class DvdTitleFile implements VirtualFile {
  DvdTitleFile(this._vobs, this._sizes, this._ranges, {required this.number});

  final List<VirtualFile> _vobs;

  /// VOB sizes in sectors.
  final List<int> _sizes;
  final List<(int, int)> _ranges;
  final int number;

  @override
  Uri get uri => Uri(
    scheme: 'dvdtitle',
    path: _vobs.firstOrNull?.uri.path ?? '',
    fragment: '$number',
  );

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _ranges.fold<int>(
    0,
    (a, r) => a + (r.$2 - r.$1 + 1) * DiscReader._sector,
  );

  @override
  Future<Uint8List> read(int offset, int length) async {
    final out = BytesBuilder(copy: false);
    var pos = offset;
    var remaining = length;
    var base = 0;
    for (final (first, last) in _ranges) {
      final bytes = (last - first + 1) * DiscReader._sector;
      if (remaining > 0 && pos < base + bytes) {
        // Absolute byte offset within the concatenated VOBs.
        var abs = first * DiscReader._sector + (pos - base);
        var take = (base + bytes - pos).clamp(0, remaining);
        while (take > 0) {
          var vob = 0;
          var vobStart = 0;
          while (vob < _sizes.length &&
              abs >= vobStart + _sizes[vob] * DiscReader._sector) {
            vobStart += _sizes[vob] * DiscReader._sector;
            vob++;
          }
          if (vob >= _sizes.length) break;
          final inVob = abs - vobStart;
          final n = (_sizes[vob] * DiscReader._sector - inVob).clamp(0, take);
          final chunk = await _vobs[vob].read(inVob, n);
          if (chunk.isEmpty) break;
          out.add(chunk);
          abs += chunk.length;
          pos += chunk.length;
          take -= chunk.length;
          remaining -= chunk.length;
        }
      }
      base += bytes;
      if (remaining <= 0) break;
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() async {
    for (final v in _vobs) {
      await v.close();
    }
  }
}

/// Files played back to back as one stream (Blu-ray playlist clips inside a
/// disc image).
final class ConcatenatedFile implements VirtualFile {
  ConcatenatedFile(this._parts, {required this.name});

  final List<VirtualFile> _parts;
  final String name;
  List<int>? _sizes;

  @override
  Uri get uri => Uri(scheme: 'concat', path: name);

  @override
  bool get isSeekable => _parts.every((p) => p.isSeekable);

  Future<List<int>> _lengths() async =>
      _sizes ??= [for (final p in _parts) await p.length() ?? 0];

  @override
  Future<int?> length() async =>
      (await _lengths()).fold<int>(0, (a, b) => a + b);

  @override
  Future<Uint8List> read(int offset, int length) async {
    final sizes = await _lengths();
    final out = BytesBuilder(copy: false);
    var pos = offset;
    var left = length;
    var base = 0;
    for (var i = 0; i < _parts.length && left > 0; i++) {
      final size = sizes[i];
      if (pos < base + size) {
        final chunk = await _parts[i].read(
          pos - base,
          (base + size - pos).clamp(0, left),
        );
        out.add(chunk);
        pos += chunk.length;
        left -= chunk.length;
        if (chunk.isEmpty) break;
      }
      base += size;
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() async {
    for (final p in _parts) {
      await p.close();
    }
  }
}

// --------------------------------------------------------- Blu-ray (MPLS) --

final class _PlayItem {
  _PlayItem(this.clip, this.inTime, this.outTime);
  final String clip;
  final int inTime;
  final int outTime;
}

final class _Mark {
  _Mark(this.item, this.time);
  final int item;
  final int time;
}

final class _Mpls {
  _Mpls(this.items, this.marks, this.audio, this.subtitles);
  final List<_PlayItem> items;
  final List<_Mark> marks;
  final List<DiscStream> audio;
  final List<DiscStream> subtitles;

  static _Mpls? parse(Uint8List b) {
    if (b.length < 0x14 || String.fromCharCodes(b, 0, 4) != 'MPLS') return null;
    final r = _Be(b);
    final playlist = r.u32(0x08);
    final marksAt = r.u32(0x0C);
    final itemCount = r.u16(playlist + 6);
    final items = <_PlayItem>[];
    final audio = <DiscStream>[];
    final subs = <DiscStream>[];
    var o = playlist + 10;
    for (var i = 0; i < itemCount && i < 999; i++) {
      final len = r.u16(o);
      final clip = String.fromCharCodes(b, o + 2, o + 7);
      final multiAngle = (b[o + 12] & 0x10) != 0;
      final inTime = r.u32(o + 14);
      final outTime = r.u32(o + 18);
      items.add(_PlayItem(clip, inTime, outTime));
      if (i == 0) {
        // STN table follows UO mask (8), flags (1), still mode/time (3) and
        // any angle entries.
        var stn = o + 2 + 32;
        if (multiAngle) {
          final angles = b[stn];
          stn += 2 + (angles - 1) * 10;
        }
        _streams(b, stn, audio, subs);
      }
      o += 2 + len;
    }
    final marks = <_Mark>[];
    final markCount = r.u16(marksAt + 4);
    for (var i = 0; i < markCount && i < 9999; i++) {
      final m = marksAt + 6 + i * 14;
      if (b[m + 1] != 1) continue; // entry marks are chapters
      marks.add(_Mark(r.u16(m + 2), r.u32(m + 4)));
    }
    return _Mpls(items, marks, audio, subs);
  }

  static void _streams(
    Uint8List b,
    int stn,
    List<DiscStream> audio,
    List<DiscStream> subs,
  ) {
    if (stn + 16 > b.length) return;
    final nVideo = b[stn + 4];
    final nAudio = b[stn + 5];
    final nPg = b[stn + 6];
    var o = stn + 16;
    // Each entry: stream_entry (len byte + body) then attributes (len + body).
    (int, int)? next() {
      if (o >= b.length) return null;
      final entryLen = b[o];
      final attr = o + 1 + entryLen;
      if (attr >= b.length) return null;
      final attrLen = b[attr];
      final start = attr + 1;
      o = start + attrLen;
      return (start, attrLen);
    }

    for (var i = 0; i < nVideo; i++) {
      if (next() == null) return;
    }
    for (var i = 0; i < nAudio; i++) {
      final a = next();
      if (a == null || a.$2 < 5) return;
      audio.add(
        DiscStream(
          language: _iso639(b, a.$1 + 2),
          codec: switch (b[a.$1]) {
            0x80 => 'pcm_bluray',
            0x81 || 0x84 || 0xA1 => 'ac3',
            0x83 => 'truehd',
            0x82 || 0x85 || 0x86 || 0xA2 => 'dts',
            _ => null,
          },
        ),
      );
    }
    for (var i = 0; i < nPg; i++) {
      final s = next();
      if (s == null || s.$2 < 4) return;
      subs.add(
        DiscStream(language: _iso639(b, s.$1 + 1), codec: 'hdmv_pgs_subtitle'),
      );
    }
  }

  static String? _iso639(Uint8List b, int o) {
    if (o + 3 > b.length) return null;
    final s = String.fromCharCodes(b, o, o + 3);
    return RegExp(r'^[a-z]{3}$').hasMatch(s) ? s : null;
  }
}
