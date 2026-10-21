import 'package:mediahro_servers/mediahro_servers.dart';
import 'package:meta/meta.dart';

/// A connected Audiobookshelf server (POD-003, NET-016): the account and
/// the client for it.
@immutable
final class AbsAccount {
  const AbsAccount(this.account, this.library);

  final ServerAccount account;
  final ServerLibrary library;

  String get id => account.id;
  String get name => account.displayName;
}

/// What Audiobookshelf items say about themselves, as the client maps them
/// into [ServerItem.extra] (C4d's `ServerLibrary` implementation). Missing
/// keys just mean less is shown.
extension AbsItemInfo on ServerItem {
  String? get author => _nonEmpty(extra['author']);
  String? get narrator => _nonEmpty(extra['narrator']);
  String? get series => _nonEmpty(extra['series']);

  /// A book or a podcast episode: something that plays.
  bool get playable =>
      kind == ServerItemKind.book || kind == ServerItemKind.podcastEpisode;

  /// A podcast: its episodes are its children.
  bool get isPodcast => kind == ServerItemKind.podcast;
}

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
