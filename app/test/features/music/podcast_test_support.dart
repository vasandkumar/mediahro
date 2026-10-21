import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/local_hosts.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/podcasts/podcast_http.dart';
import 'package:mediahro/features/music/podcasts/podcast_service.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart' show VirtualFile;
import 'package:mediahro_servers/mediahro_servers.dart';

/// Shared fakes for the podcast tests (POD-002).

const podcastRss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>The Show &amp; Co</title>
    <link>https://show.example/</link>
    <description><![CDATA[<p>Talk about <b>things</b>.</p><p>Weekly.</p>]]></description>
    <language>en</language>
    <itunes:author>Ann Host</itunes:author>
    <itunes:image href="/art/cover.jpg"/>
    <item>
      <title>Episode 2</title>
      <guid isPermaLink="false">ep-2</guid>
      <pubDate>Tue, 10 Jun 2025 04:00:00 +0200</pubDate>
      <enclosure url="https://cdn.example/ep2.mp3" length="12345" type="audio/mpeg"/>
      <itunes:duration>1:02:03</itunes:duration>
      <itunes:episode>2</itunes:episode>
      <itunes:season>1</itunes:season>
      <itunes:explicit>yes</itunes:explicit>
      <itunes:image href="https://cdn.example/ep2.jpg"/>
      <content:encoded><![CDATA[<p>Hello&nbsp;<a href="https://x">world</a><br/>line two &amp; more</p>]]></content:encoded>
    </item>
    <item>
      <title>Episode 1</title>
      <pubDate>Mon, 02 Jun 2025 10:30:00 GMT</pubDate>
      <enclosure url="/media/ep1.m4a" type="audio/mp4"/>
      <itunes:duration>2710</itunes:duration>
    </item>
    <item>
      <title>A blog post</title>
      <pubDate>Mon, 26 May 2025 10:30:00 GMT</pubDate>
      <description>No enclosure here.</description>
    </item>
    <item>
      <title>Cover</title>
      <enclosure url="https://cdn.example/cover.png" type="image/png"/>
    </item>
    <item>
      <title>Sneaky</title>
      <enclosure url="file:///etc/passwd" type="audio/mpeg"/>
    </item>
  </channel>
</rss>''';

const podcastAtom = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Cast</title>
  <subtitle>An atom feed</subtitle>
  <author><name>Bo</name></author>
  <link rel="alternate" href="https://atom.example/"/>
  <logo>https://atom.example/logo.png</logo>
  <entry>
    <title>Entry A</title>
    <id>tag:atom.example,2025:a</id>
    <published>2025-06-01T12:00:00+02:00</published>
    <link rel="enclosure" type="audio/ogg" href="https://atom.example/a.ogg" length="99"/>
    <summary>Short note</summary>
  </entry>
  <entry>
    <title>Entry B</title>
    <id>tag:atom.example,2025:b</id>
    <updated>2025-06-05T00:00:00Z</updated>
    <link rel="enclosure" type="audio/ogg" href="https://atom.example/b.ogg"/>
  </entry>
</feed>''';

/// A pretend internet: what each address answers, with redirects, and the
/// hosts the code allowed. Like the real gateway it refuses a request to a
/// host nobody has allowed for the chain that is running.
final class FakeNet {
  final _answers = <String, _Answer>{};

  /// Every host a chain allowed, in order.
  final allowed = <String>[];
  final _open = <Set<String>>[];
  final requests = <HttpRequestData>[];

  /// Holds the answer for an address until the gate completes.
  final gates = <String, Completer<void>>{};

  /// What a name resolves to (everything else is a public address).
  final dns = <String, List<InternetAddress>>{};

  /// Answers by code for an address, called for every request to it.
  final handlers =
      <String, FutureOr<HttpStreamResponse> Function(HttpRequestData)>{};

  static const _zoneKey = #fakeNetChain;

  /// The hosts every chain still open allows.
  Set<String> get openHosts => {for (final s in _open) ...s};

  /// Chains started and not yet closed.
  int get openChains => _open.length;

  static HttpStreamResponse response(
    int status,
    List<int> body, [
    Map<String, String> headers = const {},
  ]) => HttpStreamResponse(status, headers, Stream.value(body));

  void serve(
    String url,
    String body, {
    int status = 200,
    String? etag,
    String? modified,
    String type = 'application/xml',
    bool blocked = false,
    bool tooLarge = false,
  }) => _answers[url] = _Answer(
    status,
    utf8.encode(body),
    {'content-type': type, 'etag': ?etag, 'last-modified': ?modified},
    blocked: blocked,
    tooLarge: tooLarge,
  );

  void redirect(String from, String to) =>
      _answers[from] = _Answer(302, const [], {'location': to});

  late final http = PodcastHttp(
    nonPublic: (host) => resolvesToNonPublic(
      host,
      lookup: (n) async => dns[n] ?? [InternetAddress('93.184.216.34')],
    ),
    beginChain: () {
      final hosts = <String>{};
      _open.add(hosts);
      return ChainAllowance(
        allow: (h) {
          allowed.add(h);
          hosts.add(h);
        },
        close: () {
          hosts.clear();
          _open.remove(hosts);
        },
        run: <T>(body) => runZoned(body, zoneValues: {_zoneKey: hosts}),
      );
    },
    send: (request, {maxRedirects = 5}) async {
      requests.add(request);
      // Like the gateway: only a request made inside an allowance that
      // names its host goes out, and the gateway is asked to follow nothing.
      final chain = Zone.current[_zoneKey];
      if (chain is! Set<String> || !chain.contains(request.uri.host)) {
        throw NetworkBlocked(request.uri.host, 'not allowed');
      }
      if (maxRedirects != 0) {
        throw StateError('the gateway must not follow redirects here');
      }
      await gates[request.uri.toString()]?.future;
      final handler = handlers[request.uri.toString()];
      if (handler != null) return await handler(request);
      final a = _answers[request.uri.toString()];
      if (a == null) {
        return HttpStreamResponse(404, const {}, Stream.value(const []));
      }
      if (a.blocked) throw NetworkBlocked(request.uri.host, 'off');
      final body = a.tooLarge ? List.filled(25 << 20, 0) : a.body;
      return HttpStreamResponse(
        a.status,
        a.headers,
        Stream.fromIterable([
          for (var i = 0; i < body.length; i += 1 << 20)
            body.sublist(i, (i + (1 << 20)).clamp(0, body.length)),
        ]),
      );
    },
  );
}

final class _Answer {
  _Answer(
    this.status,
    this.body,
    this.headers, {
    this.blocked = false,
    this.tooLarge = false,
  });

  final int status;
  final List<int> body;
  final Map<String, String> headers;
  final bool blocked;
  final bool tooLarge;
}

final class FakeDownloads implements EpisodeDownloads {
  final enqueued = <(Uri, String, int?)>[];
  final removed = <Uri>[];
  final have = <String>{};

  @override
  Future<void> enqueue(Uri url, {required String title, int? size}) async {
    enqueued.add((url, title, size));
    have.add(url.toString());
  }

  @override
  Future<EpisodeDownload?> status(Uri url) async {
    if (!statusAsked.isCompleted) statusAsked.complete();
    await statusGate?.future;
    return _status(url);
  }

  EpisodeDownload? _status(Uri url) => have.contains(url.toString())
      ? const EpisodeDownload(DownloadState.queued)
      : null;

  @override
  Future<void> remove(Uri url) async {
    removed.add(url);
    have.remove(url.toString());
  }

  /// Addresses opened to be streamed, and what they opened to.
  final streamed = <StubFile>[];

  /// Set to refuse a stream.
  Exception? streamError;

  /// Holds [status] until it completes (a window for a test to step in).
  Completer<void>? statusGate;
  Completer<void> statusAsked = Completer<void>();

  @override
  Future<VirtualFile> openStream(Uri url) async {
    final e = streamError;
    if (e != null) throw e;
    final f = StubFile(url);
    streamed.add(f);
    return f;
  }
}

/// A file that reads nothing and knows whether it was closed.
final class StubFile implements VirtualFile {
  StubFile(this.uri);

  @override
  final Uri uri;
  bool closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => 5;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List(0);

  @override
  Future<void> close() async => closed = true;
}
