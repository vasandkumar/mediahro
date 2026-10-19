import 'dart:convert';

import 'package:mediahro/core/metadata/metadata_clients.dart'
    show decodeJsonIsolated;
import 'package:mediahro/core/sources/cloud/oauth.dart';
import 'package:mediahro/core/sources/http/http_session.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:meta/meta.dart';

/// A file or folder in a cloud drive.
@immutable
final class CloudEntry {
  const CloudEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.modified,
    this.path,
  });

  final String id;
  final String name;
  final bool isFolder;
  final int? size;
  final DateTime? modified;

  /// Provider path for path-based APIs (Dropbox, Yandex).
  final String? path;
}

/// What providers need from an account connection (tests fake it).
abstract interface class CloudCalls {
  Future<String> token();

  Future<Map<String, Object?>> json(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers,
    bool form,
  });
}

/// Authorised JSON calls to one account, refreshing the access token on
/// expiry or 401 and persisting it through [onTokens].
final class CloudApi implements CloudCalls {
  CloudApi({
    required this.session,
    required this.oauth,
    required this._tokens,
    this.onTokens,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Session without credentials; the bearer is added per request.
  final HttpSession session;
  final OAuthClient oauth;
  final Future<void> Function(OAuthTokens tokens)? onTokens;
  final DateTime Function() _clock;
  OAuthTokens _tokens;

  String get accessToken => _tokens.accessToken;

  @override
  Future<String> token() async {
    if (_tokens.expiredAt(_clock())) await _refresh();
    return _tokens.accessToken;
  }

  Future<void> _refresh() async {
    _tokens = await oauth.refresh(_tokens);
    await onTokens?.call(_tokens);
  }

  @override
  Future<Map<String, Object?>> json(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
    bool form = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final t = await token();
      final (status, _, bytes) = await session.fetch(
        method,
        uri,
        extra: {
          'Authorization': 'Bearer $t',
          'Accept': 'application/json',
          if (body != null)
            'Content-Type': form
                ? 'application/x-www-form-urlencoded'
                : 'application/json',
          ...headers,
        },
        body: body == null
            ? null
            : utf8.encode(
                form
                    ? Uri(queryParameters: body as Map<String, String>).query
                    : jsonEncode(body),
              ),
      );
      if (status == 401 && attempt == 0) {
        await _refresh();
        continue;
      }
      HttpSession.check(status, uri);
      if (bytes.isEmpty) return const {};
      return await decodeJsonIsolated(bytes);
    }
    throw VirtualFileException(VirtualFileError.authenticationRequired, uri);
  }
}

/// One cloud-drive REST API (NET-007). No vendor SDKs; every request goes
/// through NetworkGateway. Hosts the provider may contact are listed so
/// the network policy allows them once the user connected the account.
abstract interface class CloudProvider {
  String get id;
  String get displayName;

  /// Exact hosts or `*.suffix` patterns.
  List<String> get hosts;
  OAuthConfig oauth(String clientId);
  String get rootId;
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder);

  /// A GET URL that honours `Range`, and its headers (the bearer only when
  /// the URL is on the provider's own API host).
  Future<(Uri, Map<String, String>)> download(CloudCalls api, CloudEntry file);
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
Iterable<Map<String, Object?>> _maps(Object? v) =>
    v is List<Object?> ? v.whereType<Map<String, Object?>>() : const [];

final class GoogleDriveProvider implements CloudProvider {
  const GoogleDriveProvider();

  @override
  String get id => 'gdrive';
  @override
  String get displayName => 'Google Drive';
  @override
  List<String> get hosts => const [
    'accounts.google.com',
    'oauth2.googleapis.com',
    'www.googleapis.com',
  ];
  @override
  String get rootId => 'root';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
    token: Uri.parse('https://oauth2.googleapis.com/token'),
    scopes: const ['https://www.googleapis.com/auth/drive.readonly'],
    clientId: clientId,
    extraAuthParams: const {'access_type': 'offline', 'prompt': 'consent'},
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final out = <CloudEntry>[];
    String? page;
    do {
      final j = await api.json(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q':
              "'${folder.id.replaceAll("'", r"\'")}' in parents and trashed = false",
          'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
          'pageSize': '1000',
          'supportsAllDrives': 'true',
          'includeItemsFromAllDrives': 'true',
          'pageToken': ?page,
        }),
      );
      for (final f in _maps(j['files'])) {
        final mime = f['mimeType'] as String? ?? '';
        // Google Docs/Sheets have no bytes to play; skip them.
        if (mime.startsWith('application/vnd.google-apps.') &&
            mime != 'application/vnd.google-apps.folder') {
          continue;
        }
        out.add(
          CloudEntry(
            id: f['id']! as String,
            name: f['name'] as String? ?? '',
            isFolder: mime == 'application/vnd.google-apps.folder',
            size: _int(f['size']),
            modified: _date(f['modifiedTime']),
          ),
        );
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async => (
    Uri.https('www.googleapis.com', '/drive/v3/files/${file.id}', {
      'alt': 'media',
      'supportsAllDrives': 'true',
    }),
    {'Authorization': 'Bearer ${await api.token()}'},
  );
}

final class OneDriveProvider implements CloudProvider {
  const OneDriveProvider();

  @override
  String get id => 'onedrive';
  @override
  String get displayName => 'OneDrive';
  @override
  List<String> get hosts => const [
    'login.microsoftonline.com',
    'graph.microsoft.com',
    '*.sharepoint.com',
    '*.1drv.com',
    '*.livefilestore.com',
  ];
  @override
  String get rootId => 'root';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    ),
    token: Uri.parse(
      'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    ),
    scopes: const ['Files.Read.All', 'offline_access'],
    clientId: clientId,
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final out = <CloudEntry>[];
    Uri? next = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/items/${folder.id}/children',
      {
        r'$select': 'id,name,size,folder,file,lastModifiedDateTime',
        r'$top': '1000',
      },
    );
    while (next != null) {
      final j = await api.json('GET', next);
      for (final f in _maps(j['value'])) {
        out.add(
          CloudEntry(
            id: f['id']! as String,
            name: f['name'] as String? ?? '',
            isFolder: f['folder'] != null,
            size: _int(f['size']),
            modified: _date(f['lastModifiedDateTime']),
          ),
        );
      }
      final link = j['@odata.nextLink'] as String?;
      // Follow paging only on Graph itself.
      next = link == null || Uri.parse(link).host != 'graph.microsoft.com'
          ? null
          : Uri.parse(link);
    }
    return out;
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async {
    final j = await api.json(
      'GET',
      Uri.https('graph.microsoft.com', '/v1.0/me/drive/items/${file.id}', {
        r'$select': 'id,@microsoft.graph.downloadUrl',
      }),
    );
    final url = j['@microsoft.graph.downloadUrl'] as String?;
    if (url == null) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        Uri.parse('cloud://onedrive/${file.id}'),
      );
    }
    // Pre-authenticated short-lived URL: no bearer.
    return (Uri.parse(url), const <String, String>{});
  }
}

final class DropboxProvider implements CloudProvider {
  const DropboxProvider();

  @override
  String get id => 'dropbox';
  @override
  String get displayName => 'Dropbox';
  @override
  List<String> get hosts => const [
    'www.dropbox.com',
    'api.dropboxapi.com',
    'content.dropboxapi.com',
    '*.dl.dropboxusercontent.com',
  ];
  @override
  String get rootId => '';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse('https://www.dropbox.com/oauth2/authorize'),
    token: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
    scopes: const ['files.metadata.read', 'files.content.read'],
    clientId: clientId,
    extraAuthParams: const {'token_access_type': 'offline'},
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final out = <CloudEntry>[];
    var j = await api.json(
      'POST',
      Uri.https('api.dropboxapi.com', '/2/files/list_folder'),
      body: {'path': folder.path ?? '', 'limit': 2000},
    );
    while (true) {
      for (final f in _maps(j['entries'])) {
        final tag = f['.tag'];
        if (tag != 'file' && tag != 'folder') continue;
        out.add(
          CloudEntry(
            id: f['id'] as String? ?? f['path_lower']! as String,
            name: f['name'] as String? ?? '',
            isFolder: tag == 'folder',
            size: _int(f['size']),
            modified: _date(f['server_modified']),
            path: f['path_lower'] as String?,
          ),
        );
      }
      if (j['has_more'] != true) break;
      j = await api.json(
        'POST',
        Uri.https('api.dropboxapi.com', '/2/files/list_folder/continue'),
        body: {'cursor': j['cursor']},
      );
    }
    return out;
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async {
    final j = await api.json(
      'POST',
      Uri.https('api.dropboxapi.com', '/2/files/get_temporary_link'),
      body: {'path': file.path ?? file.id},
    );
    return (Uri.parse(j['link']! as String), const <String, String>{});
  }
}

final class BoxProvider implements CloudProvider {
  const BoxProvider();

  @override
  String get id => 'box';
  @override
  String get displayName => 'Box';
  @override
  List<String> get hosts => const [
    'account.box.com',
    'api.box.com',
    '*.boxcloud.com',
  ];
  @override
  String get rootId => '0';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse('https://account.box.com/api/oauth2/authorize'),
    token: Uri.parse('https://api.box.com/oauth2/token'),
    scopes: const ['root_readonly'],
    clientId: clientId,
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final out = <CloudEntry>[];
    var offset = 0;
    while (true) {
      final j = await api.json(
        'GET',
        Uri.https('api.box.com', '/2.0/folders/${folder.id}/items', {
          'fields': 'id,type,name,size,modified_at',
          'limit': '1000',
          'offset': '$offset',
        }),
      );
      final entries = _maps(j['entries']).toList();
      for (final f in entries) {
        final type = f['type'];
        if (type != 'file' && type != 'folder') continue;
        out.add(
          CloudEntry(
            id: f['id']! as String,
            name: f['name'] as String? ?? '',
            isFolder: type == 'folder',
            size: _int(f['size']),
            modified: _date(f['modified_at']),
          ),
        );
      }
      offset += entries.length;
      final total = _int(j['total_count']) ?? 0;
      if (entries.isEmpty || offset >= total) break;
    }
    return out;
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async => (
    // 302 to dl.boxcloud.com; the gateway follows it (allowed host).
    Uri.https('api.box.com', '/2.0/files/${file.id}/content'),
    {'Authorization': 'Bearer ${await api.token()}'},
  );
}

final class PCloudProvider implements CloudProvider {
  const PCloudProvider({this.region = 'us'});

  /// `us` (api.pcloud.com) or `eu` (eapi.pcloud.com), from the OAuth reply.
  final String region;

  String get _api => region == 'eu' ? 'eapi.pcloud.com' : 'api.pcloud.com';

  @override
  String get id => 'pcloud';
  @override
  String get displayName => 'pCloud';
  @override
  List<String> get hosts => const [
    'my.pcloud.com',
    'api.pcloud.com',
    'eapi.pcloud.com',
    '*.pcloud.com',
  ];
  @override
  String get rootId => '0';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse('https://my.pcloud.com/oauth2/authorize'),
    token: Uri.https(_api, '/oauth2_token'),
    scopes: const [],
    clientId: clientId,
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final j = await api.json(
      'GET',
      Uri.https(_api, '/listfolder', {'folderid': folder.id}),
    );
    if ((j['result'] as int? ?? 0) != 0) {
      throw VirtualFileException(
        VirtualFileError.io,
        Uri.parse('cloud://pcloud/${folder.id}'),
        '${j['error']}',
      );
    }
    final meta = j['metadata'] as Map<String, Object?>? ?? const {};
    return [
      for (final f in _maps(meta['contents']))
        CloudEntry(
          id: f['isfolder'] == true ? '${f['folderid']}' : '${f['fileid']}',
          name: f['name'] as String? ?? '',
          isFolder: f['isfolder'] == true,
          size: _int(f['size']),
          modified: f['modified'] is String
              ? _rfc1123(f['modified']! as String)
              : null,
        ),
    ];
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async {
    final j = await api.json(
      'GET',
      Uri.https(_api, '/getfilelink', {'fileid': file.id}),
    );
    final hosts = (j['hosts'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    if (hosts.isEmpty) {
      throw VirtualFileException(
        VirtualFileError.notFound,
        Uri.parse('cloud://pcloud/${file.id}'),
      );
    }
    return (
      Uri.https(hosts.first, j['path']! as String),
      const <String, String>{},
    );
  }

  static DateTime? _rfc1123(String s) {
    try {
      return HttpDateLike.parse(s);
    } on FormatException {
      return null;
    }
  }
}

final class YandexDiskProvider implements CloudProvider {
  const YandexDiskProvider();

  @override
  String get id => 'yandex';
  @override
  String get displayName => 'Yandex Disk';
  @override
  List<String> get hosts => const [
    'oauth.yandex.com',
    'cloud-api.yandex.net',
    '*.disk.yandex.net',
    '*.disk.yandex.ru',
  ];
  @override
  String get rootId => 'disk:/';

  @override
  OAuthConfig oauth(String clientId) => OAuthConfig(
    authorize: Uri.parse('https://oauth.yandex.com/authorize'),
    token: Uri.parse('https://oauth.yandex.com/token'),
    scopes: const ['cloud_api:disk.read'],
    clientId: clientId,
  );

  @override
  Future<List<CloudEntry>> list(CloudCalls api, CloudEntry folder) async {
    final out = <CloudEntry>[];
    var offset = 0;
    while (true) {
      final j = await api.json(
        'GET',
        Uri.https('cloud-api.yandex.net', '/v1/disk/resources', {
          'path': folder.path ?? folder.id,
          'limit': '1000',
          'offset': '$offset',
          'fields': '_embedded.items.name,_embedded.items.path,_embedded.items.type,_embedded.items.size,_embedded.items.modified,_embedded.total',
        }),
      );
      final emb = j['_embedded'] as Map<String, Object?>? ?? const {};
      final items = _maps(emb['items']).toList();
      for (final f in items) {
        out.add(
          CloudEntry(
            id: f['path']! as String,
            name: f['name'] as String? ?? '',
            isFolder: f['type'] == 'dir',
            size: _int(f['size']),
            modified: _date(f['modified']),
            path: f['path'] as String?,
          ),
        );
      }
      offset += items.length;
      if (items.isEmpty || offset >= (_int(emb['total']) ?? 0)) break;
    }
    return out;
  }

  @override
  Future<(Uri, Map<String, String>)> download(
    CloudCalls api,
    CloudEntry file,
  ) async {
    final j = await api.json(
      'GET',
      Uri.https('cloud-api.yandex.net', '/v1/disk/resources/download', {
        'path': file.path ?? file.id,
      }),
    );
    return (Uri.parse(j['href']! as String), const <String, String>{});
  }
}

/// Providers with a public REST API (NET-007). MEGA uses a client-side
/// encrypted protocol without OAuth and Proton Drive has no public API;
/// both are tracked in STATUS.md.
const List<CloudProvider> cloudProviders = [
  GoogleDriveProvider(),
  OneDriveProvider(),
  DropboxProvider(),
  BoxProvider(),
  PCloudProvider(),
  YandexDiskProvider(),
];

CloudProvider? cloudProvider(String id) =>
    cloudProviders.where((p) => p.id == id).firstOrNull;

/// Whether [host] is one of [provider]'s hosts (exact or `*.suffix`).
bool cloudHostMatches(CloudProvider provider, String host) => provider.hosts
    .any((h) => h.startsWith('*.') ? host.endsWith(h.substring(1)) : host == h);

/// RFC 1123 dates as pCloud sends them.
abstract final class HttpDateLike {
  static DateTime parse(String s) {
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) throw FormatException('not an RFC 1123 date', s);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final mon = months.indexOf(m.group(2)!) + 1;
    if (mon == 0) throw FormatException('bad month', s);
    return DateTime.utc(
      int.parse(m.group(3)!),
      mon,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
