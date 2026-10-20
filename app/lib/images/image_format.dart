import 'dart:typed_data';

/// Image container formats the pipeline recognises (IMG-001). The short name
/// is what `ImageInfo.format` carries.
enum ImageFormat {
  jpeg('jpeg'),
  png('png'),
  gif('gif'),
  webp('webp'),
  avif('avif'),
  heic('heic'),
  jxl('jxl'),
  tiff('tiff'),
  bmp('bmp'),
  ico('ico'),
  svg('svg'),
  psd('psd'),
  exr('exr'),
  hdr('hdr'),
  dds('dds'),
  tga('tga'),
  pnm('pnm'),
  qoi('qoi'),

  /// Camera RAW (LibRaw); the vendor is told apart by file extension.
  raw('raw'),
  unknown('unknown');

  const ImageFormat(this.shortName);

  final String shortName;

  /// Formats whose metadata lives in a TIFF structure that is the file.
  bool get isTiffBased => this == tiff || this == raw;

  /// Formats read through libvips.
  bool get vipsDecodable => switch (this) {
    jpeg || png || gif || webp || tiff || avif || exr || psd || hdr => true,
    _ => false,
  };
}

/// RAW extensions LibRaw reads (IMG-001): the vendor families the spec names
/// plus the common others.
const Set<String> rawExtensions = {
  'cr2',
  'cr3',
  'crw',
  'nef',
  'nrw',
  'arw',
  'sr2',
  'srf',
  'dng',
  'raf',
  'orf',
  'rw2',
  'pef',
  'srw',
  '3fr',
  'fff',
  'iiq',
  'kdc',
  'dcr',
  'mef',
  'mos',
  'mrw',
  'erf',
  'rwl',
  'x3f',
  'raw',
  'gpr',
  'cap',
};

/// Detects the format from the first bytes of a file and, for the TIFF-based
/// RAW families that share TIFF's magic, from [extension] (no dot).
ImageFormat sniffImageFormat(Uint8List head, {String? extension}) {
  final ext = extension?.toLowerCase().replaceFirst('.', '');
  final isRawExt = ext != null && rawExtensions.contains(ext);
  bool at(int o, List<int> m) {
    if (o + m.length > head.length) return false;
    for (var i = 0; i < m.length; i++) {
      if (head[o + i] != m[i]) return false;
    }
    return true;
  }

  bool ascii(int o, String s) => at(o, s.codeUnits);

  if (at(0, const [0xFF, 0xD8, 0xFF])) return ImageFormat.jpeg;
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return ImageFormat.png;
  }
  if (ascii(0, 'GIF8')) return ImageFormat.gif;
  if (ascii(0, 'RIFF') && ascii(8, 'WEBP')) return ImageFormat.webp;
  if (at(0, const [0xFF, 0x0A]) ||
      at(0, const [0, 0, 0, 0x0C, 0x4A, 0x58, 0x4C, 0x20])) {
    return ImageFormat.jxl;
  }
  if (ascii(4, 'ftyp')) {
    final brand = String.fromCharCodes(
      head.sublist(8, head.length < 12 ? head.length : 12),
    );
    if (brand == 'avif' || brand == 'avis') return ImageFormat.avif;
    if (brand == 'crx ') return ImageFormat.raw;
    return ImageFormat.heic;
  }
  if (ascii(0, 'FUJIFILMCCD-RAW') || ascii(6, 'HEAPCCDR') || ascii(0, 'FOVb')) {
    return ImageFormat.raw;
  }
  final tiffLE =
      at(0, const [0x49, 0x49]) &&
      (at(2, const [0x2A, 0]) ||
          at(2, const [0x52, 0x4F]) ||
          at(2, const [0x55, 0]));
  final tiffBE =
      at(0, const [0x4D, 0x4D]) &&
      (at(2, const [0, 0x2A]) || at(2, const [0x4F, 0x52]));
  if (tiffLE || tiffBE) {
    return isRawExt || ascii(8, 'CR') ? ImageFormat.raw : ImageFormat.tiff;
  }
  if (ascii(0, 'BM') && head.length > 14) return ImageFormat.bmp;
  if (ascii(0, '8BPS')) return ImageFormat.psd;
  if (at(0, const [0x76, 0x2F, 0x31, 0x01])) return ImageFormat.exr;
  if (ascii(0, '#?RADIANCE') || ascii(0, '#?RGBE')) return ImageFormat.hdr;
  if (ascii(0, 'DDS ')) return ImageFormat.dds;
  if (ascii(0, 'qoif')) return ImageFormat.qoi;
  if (at(0, const [0, 0, 1, 0]) && head.length >= 6) return ImageFormat.ico;
  if (head.length >= 2 &&
      head[0] == 0x50 &&
      head[1] >= 0x31 &&
      head[1] <= 0x37 &&
      (head.length < 3 ||
          head[2] == 0x0A ||
          head[2] == 0x20 ||
          head[2] == 0x0D)) {
    return ImageFormat.pnm;
  }
  // SVG is text: look for an <svg element in the first 1 KiB.
  final text = String.fromCharCodes(
    head.sublist(0, head.length < 1024 ? head.length : 1024),
  );
  if (text.contains('<svg')) return ImageFormat.svg;
  if (isRawExt) return ImageFormat.raw;
  if (ext == 'tga') return ImageFormat.tga;
  return ImageFormat.unknown;
}
