import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// What the engine should open.
///
/// Every source is either a URI mpv understands natively (http(s), hls, dash,
/// rtsp, rtmp, file) or a [VirtualFile] exposed to mpv through a custom
/// stream protocol so SMB/NFS/WebDAV/FTP/SFTP/archives/cloud are seekable
/// (docs/05 §9).
@immutable
sealed class MediaSource {
  const MediaSource({this.title});

  /// Display title for media sessions; the engine falls back to metadata.
  final String? title;
}

/// A URI opened directly by the engine (CORE-005, NET-006).
final class UriSource extends MediaSource {
  const UriSource(
    this.uri, {
    this.headers = const {},
    this.userAgent,
    super.title,
  });

  final Uri uri;

  /// Custom request headers for HTTP-family URIs (NET-006).
  final Map<String, String> headers;
  final String? userAgent;

  @override
  bool operator ==(Object other) =>
      other is UriSource &&
      other.uri == uri &&
      other.userAgent == userAgent &&
      _mapEq(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    uri,
    userAgent,
    Object.hashAllUnordered(headers.entries.map((e) => '${e.key}=${e.value}')),
  );
}

/// A file read through [VirtualFile] (local SAF/bookmark files, network shares,
/// archive entries, server downloads).
final class VirtualFileSource extends MediaSource {
  const VirtualFileSource(this.file, {super.title});

  final VirtualFile file;

  @override
  bool operator ==(Object other) =>
      other is VirtualFileSource && identical(other.file, file);

  @override
  int get hashCode => identityHashCode(file);
}

bool _mapEq(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
