import 'package:mediahro/core/sources/url_open.dart';
import 'package:meta/meta.dart';

/// Why something another app handed to Mediahro was not opened.
enum IncomingRefusal {
  /// A scheme Mediahro does not take from other apps.
  scheme,

  /// A file the app holds no permission to read, or one of its own private files.
  notPermitted,

  /// A kind of file the app has no way to open from outside yet.
  unsupportedType,

  /// An image: the viewer only shows library photos so far.
  imageViewer,
}

/// What to do with one URI handed over by Open with, Share or a link
/// (CORE-003, SYS-004). Everything arriving here comes from another app and
/// is untrusted: only these targets are ever acted on.
@immutable
sealed class IncomingTarget {
  const IncomingTarget();
}

/// A network stream the user chose to open in Mediahro.
final class IncomingStream extends IncomingTarget {
  const IncomingStream(this.url);

  final OpenableUrl url;
}

/// A file read through a grant: `content://` from the system, or a `file://`
/// inside a folder the app already holds.
final class IncomingDocument extends IncomingTarget {
  const IncomingDocument(this.uri);

  final Uri uri;
}

final class IncomingRefused extends IncomingTarget {
  const IncomingRefused(this.reason);

  final IncomingRefusal reason;
}

/// Schemes of links taken as streams: the ones the app registers for in its
/// manifest (`http(s)`, `rtsp(s)`, `rtmp(s)`, `mms`, `srt`).
const incomingStreamSchemes = {
  'http', 'https', 'rtsp', 'rtsps', 'rtmp', 'rtmps', 'mms', 'srt', //
};

/// The prefix of this app's own provider authorities; nothing from another app
/// may point at them, so private files (the vault, caches) cannot be opened.
const ownAuthorityPrefix = 'com.mediahro.';

/// The most URIs taken from one hand-over.
const incomingLimit = 100;

/// Decides what to do with [uri]. [fileRoots] are the `file://` folders the
/// app already holds a grant for; a `file://` URI outside them is refused.
IncomingTarget classifyIncoming(Uri uri, {List<Uri> fileRoots = const []}) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'content') {
    if (uri.authority.toLowerCase().startsWith(ownAuthorityPrefix)) {
      return const IncomingRefused(IncomingRefusal.notPermitted);
    }
    return IncomingDocument(uri);
  }
  if (scheme == 'file') {
    return _inside(uri, fileRoots)
        ? IncomingDocument(uri)
        : const IncomingRefused(IncomingRefusal.notPermitted);
  }
  if (incomingStreamSchemes.contains(scheme)) {
    try {
      final url = parseUserUrl(uri.toString());
      if (url.kind == UrlKind.stream) return IncomingStream(url);
    } on UrlRejected {
      // Falls through to the refusal below.
    }
  }
  return const IncomingRefused(IncomingRefusal.scheme);
}

bool _inside(Uri file, List<Uri> roots) {
  if (file.pathSegments.contains('..')) return false;
  for (final root in roots) {
    if (root.scheme != 'file') continue;
    final base = root.path.endsWith('/') ? root.path : '${root.path}/';
    if (file.path.startsWith(base)) return true;
  }
  return false;
}
