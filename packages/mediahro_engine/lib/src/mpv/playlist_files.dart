/// Playlist formats mpv does not read natively (VID-001). M3U, PLS and CUE
/// are handled by mpv's own demuxers; XSPF is expanded here.
library;

/// Maximum entries read from one playlist file (parser limit, docs/13).
const int maxPlaylistEntries = 100000;

/// Whether [path] is a playlist the engine expands itself.
bool needsPlaylistExpansion(String path) =>
    path.toLowerCase().endsWith('.xspf');

/// Parses an XSPF document into entry URIs resolved against [base]
/// (the playlist's own location).
///
/// A deliberately small reader: `<location>` elements inside `<track>`,
/// XML entities decoded, everything else ignored. Malformed input yields the
/// entries read so far.
List<Uri> parseXspf(String xml, Uri base) {
  final out = <Uri>[];
  final track = RegExp(r'<track\b[^>]*>(.*?)</track>', dotAll: true);
  final location = RegExp(r'<location\b[^>]*>(.*?)</location>', dotAll: true);
  for (final t in track.allMatches(xml)) {
    final loc = location.firstMatch(t.group(1)!);
    if (loc == null) continue;
    final text = _unescape(loc.group(1)!.trim());
    if (text.isEmpty) continue;
    final uri = Uri.tryParse(text);
    if (uri == null) continue;
    out.add(uri.hasScheme ? uri : base.resolveUri(uri));
    if (out.length >= maxPlaylistEntries) break;
  }
  return out;
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(
      RegExp('&#(x?)([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(
        int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16),
      ),
    )
    .replaceAll('&amp;', '&');
