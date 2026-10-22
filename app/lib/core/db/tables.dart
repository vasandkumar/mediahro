// Index schema (docs/05 §6, LIB-001). One database per profile; every table
// listed in docs/05 §6 exists here so feature lanes share one model.
//
// Secrets never live in these tables: credential columns hold only the key
// name used with SecureStorageFacade (PRIV-006).
import 'package:drift/drift.dart';

/// What an indexed file is.
enum ItemKind { video, audio, image, playlist, subtitle, archive, other }

/// Where a source lives.
enum SourceKind {
  local,
  smb,
  nfs,
  webdav,
  ftp,
  sftp,
  dlna,
  url,
  server,
  archive,
}

/// When a source is rescanned (LIB-003).
enum ScanSchedule { manual, onOpen, watch }

/// Colour labels (LIB-009).
enum LabelColor { red, orange, yellow, green, blue, purple, grey }

enum ScanJobState { queued, running, paused, done, failed, cancelled }

enum DownloadState { queued, running, paused, done, failed, expired }

mixin _Id on Table {
  IntColumn get id => integer().autoIncrement()();
}

@DataClassName('SourceRow')
class Sources extends Table with _Id {
  @override
  String get tableName => 'source';

  TextColumn get kind => textEnum<SourceKind>()();
  TextColumn get name => text()();

  /// Root URI (file:, smb:, nfs:, davs:, ftp:, sftp:, dlna:, ...).
  TextColumn get rootUri => text()();

  /// StorageFacade grant id for SAF trees / bookmarks (LIB-002).
  TextColumn get grantId => text().nullable()();

  /// SecureStorageFacade key name; never the secret itself.
  TextColumn get credentialKey => text().nullable()();

  /// Protocol options (JSON object of strings): share, domain, version, ...
  TextColumn get options => text().withDefault(const Constant('{}'))();
  TextColumn get schedule =>
      textEnum<ScanSchedule>().withDefault(const Constant('manual'))();
  BoolColumn get includeVideo => boolean().withDefault(const Constant(true))();
  BoolColumn get includeMusic => boolean().withDefault(const Constant(true))();
  BoolColumn get includePhotos => boolean().withDefault(const Constant(true))();

  /// Per-source metadata scraping opt-in (LIB-011).
  BoolColumn get scrapeMetadata =>
      boolean().withDefault(const Constant(false))();

  /// Behind the parental PIN gate (LIB-013).
  BoolColumn get locked => boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastScanAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('ItemRow')
@TableIndex(
  name: 'item_source_path',
  columns: {#sourceId, #relPath},
  unique: true,
)
@TableIndex(name: 'item_parent', columns: {#sourceId, #parentPath})
@TableIndex(name: 'item_kind_added', columns: {#kind, #addedAt})
@TableIndex(name: 'item_hash', columns: {#contentHash})
class Items extends Table with _Id {
  @override
  String get tableName => 'item';

  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();

  /// Path relative to the source root, `/`-separated, no leading slash.
  TextColumn get relPath => text()();

  /// Parent folder of [relPath] (`''` for the root) for folder mode (LIB-004).
  TextColumn get parentPath => text()();
  TextColumn get name => text()();
  TextColumn get ext => text()();
  TextColumn get kind => textEnum<ItemKind>()();
  IntColumn get size => integer()();
  DateTimeColumn get mtime => dateTime()();

  /// xxh3-64 of the first and last MiB plus size, hex (move detection).
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get scannedAt => dateTime()();

  /// File vanished on the last scan; kept so a move can be re-linked.
  BoolColumn get missing => boolean().withDefault(const Constant(false))();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  BoolColumn get vault => boolean().withDefault(const Constant(false))();

  /// Display title (metadata title, scraped title or cleaned file name).
  TextColumn get title => text()();
  TextColumn get sortTitle => text()();

  // Media facts shared by every kind (LIB-001); filled by the prober.
  IntColumn get durationMs => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get videoCodec => text().nullable()();
  TextColumn get audioCodec => text().nullable()();

  /// none / hdr10 / hdr10plus / hlg / dolbyVision.
  TextColumn get hdrType => text().nullable()();

  /// e.g. `stereo`, `5.1`, `7.1.4`.
  TextColumn get audioLayout => text().nullable()();
  IntColumn get subtitleTracks => integer().withDefault(const Constant(0))();
  IntColumn get audioTracks => integer().withDefault(const Constant(0))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  /// Probe finished (metadata facts are valid).
  BoolColumn get probed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get takenAt => dateTime().nullable()();
}

@DataClassName('VideoMetaRow')
class VideoMeta extends Table {
  @override
  String get tableName => 'video_meta';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get parsedTitle => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get seasonNumber => integer().nullable()();
  IntColumn get episodeNumber => integer().nullable()();
  IntColumn get seriesId => integer().nullable().references(SeriesTable, #id)();
  IntColumn get seasonId => integer().nullable().references(Seasons, #id)();
  IntColumn get collectionId =>
      integer().nullable().references(Collections, #id)();
  TextColumn get imdbId => text().nullable()();
  TextColumn get overview => text().nullable()();
  TextColumn get episodeTitle => text().nullable()();
  RealColumn get communityRating => real().nullable()();

  /// User pinned a manual match or unmatch (LIB-011).
  BoolColumn get matchLocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get scrapedAt => dateTime().nullable()();
  RealColumn get frameRate => real().nullable()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('AudioMetaRow')
@TableIndex(name: 'audio_album', columns: {#albumId})
@TableIndex(name: 'audio_artist', columns: {#artistId})
class AudioMeta extends Table {
  @override
  String get tableName => 'audio_meta';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get artist => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get genre => text().nullable()();
  TextColumn get composer => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get albumId => integer().nullable().references(Albums, #id)();
  IntColumn get artistId => integer().nullable().references(Artists, #id)();
  IntColumn get sampleRate => integer().nullable()();
  IntColumn get bitDepth => integer().nullable()();
  IntColumn get bitrate => integer().nullable()();
  RealColumn get trackGainDb => real().nullable()();
  RealColumn get albumGainDb => real().nullable()();
  RealColumn get loudnessLufs => real().nullable()();

  /// Chromaprint fingerprint, base64 (LIB-014, MUS fingerprinting).
  TextColumn get fingerprint => text().nullable()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('ImageMetaRow')
class ImageMeta extends Table {
  @override
  String get tableName => 'image_meta';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get camera => text().nullable()();
  TextColumn get lens => text().nullable()();
  IntColumn get orientation => integer().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get placeId => integer().nullable().references(Places, #id)();

  /// 64-bit perceptual hash, hex (LIB-014).
  TextColumn get phash => text().nullable()();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();
  TextColumn get pairedVideoPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('TrackRow')
class Tracks extends Table with _Id {
  @override
  String get tableName => 'track';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();

  /// video / audio / subtitle.
  TextColumn get type => text()();
  IntColumn get streamIndex => integer()();
  TextColumn get codec => text().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get title => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isForced => boolean().withDefault(const Constant(false))();

  /// Sidecar file path relative to the source root (FILE-006).
  TextColumn get externalPath => text().nullable()();
}

@DataClassName('ChapterRow')
class Chapters extends Table with _Id {
  @override
  String get tableName => 'chapter';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get startMs => integer()();
  TextColumn get title => text().nullable()();
}

@DataClassName('ArtworkRow')
class Artworks extends Table with _Id {
  @override
  String get tableName => 'artwork';

  /// item / album / artist / series / season / collection / person / folder.
  TextColumn get ownerType => text()();
  IntColumn get ownerId => integer()();

  /// poster / backdrop / cover / thumb / folder.
  TextColumn get role => text()();
  TextColumn get uri => text()();
  TextColumn get cachePath => text().nullable()();
}

@DataClassName('TagRow')
class Tags extends Table with _Id {
  @override
  String get tableName => 'tag';

  TextColumn get name => text().unique()();
}

@DataClassName('ItemTagRow')
class ItemTags extends Table {
  @override
  String get tableName => 'item_tag';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {itemId, tagId};
}

@DataClassName('LabelRow')
class Labels extends Table {
  @override
  String get tableName => 'label';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get color => textEnum<LabelColor>()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('PlaylistRow')
class Playlists extends Table with _Id {
  @override
  String get tableName => 'playlist';

  TextColumn get name => text()();

  /// Serialised smart rule (LIB-007); null for manual playlists.
  TextColumn get rule => text().nullable()();

  /// video / audio / image / mixed.
  TextColumn get mode => text().withDefault(const Constant('mixed'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('PlaylistItemRow')
class PlaylistItems extends Table with _Id {
  @override
  String get tableName => 'playlist_item';

  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  /// Indexed item, or null for an external URI entry (cross-source).
  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get uri => text().nullable()();
  TextColumn get title => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
}

@DataClassName('QueueRow')
class Queues extends Table with _Id {
  @override
  String get tableName => 'queue';

  TextColumn get name => text()();

  /// audio / video (LIB-008: named queues for audio, one for video).
  TextColumn get mode => text()();
  IntColumn get currentIndex => integer().withDefault(const Constant(0))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  BoolColumn get shuffle => boolean().withDefault(const Constant(false))();

  /// off / one / all.
  TextColumn get repeat => text().withDefault(const Constant('off'))();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('QueueItemRow')
class QueueItems extends Table with _Id {
  @override
  String get tableName => 'queue_item';

  IntColumn get queueId =>
      integer().references(Queues, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get uri => text().nullable()();
  TextColumn get title => text().nullable()();
}

@DataClassName('ProgressRow')
class Progress extends Table {
  @override
  String get tableName => 'progress';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer().nullable()();
  BoolColumn get watched => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  /// Pending push to a connected server (LIB-010).
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('RatingRow')
class Ratings extends Table {
  @override
  String get tableName => 'rating';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();

  /// 0…10 (half stars).
  IntColumn get value => integer()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DataClassName('PlayEventRow')
@TableIndex(name: 'play_event_at', columns: {#at})
class PlayEvents extends Table with _Id {
  @override
  String get tableName => 'play_event';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get at => dateTime()();
  IntColumn get listenedMs => integer()();
}

@DataClassName('PersonRow')
class People extends Table with _Id {
  @override
  String get tableName => 'person';

  TextColumn get name => text()();
  BoolColumn get isFaceCluster =>
      boolean().withDefault(const Constant(false))();
}

@DataClassName('ItemPersonRow')
class ItemPeople extends Table {
  @override
  String get tableName => 'item_person';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(People, #id, onDelete: KeyAction.cascade)();

  /// actor / director / writer / face.
  TextColumn get role => text()();
  TextColumn get character => text().nullable()();

  @override
  Set<Column> get primaryKey => {itemId, personId, role};
}

@DataClassName('PlaceRow')
class Places extends Table with _Id {
  @override
  String get tableName => 'place';

  TextColumn get name => text()();
  TextColumn get country => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
}

@DataClassName('AlbumRow')
class Albums extends Table with _Id {
  @override
  String get tableName => 'album';

  TextColumn get title => text()();
  TextColumn get albumArtist => text().nullable()();
  IntColumn get year => integer().nullable()();

  /// music / photo.
  TextColumn get type => text().withDefault(const Constant('music'))();
}

@DataClassName('ArtistRow')
class Artists extends Table with _Id {
  @override
  String get tableName => 'artist';

  TextColumn get name => text().unique()();
  TextColumn get sortName => text()();
}

@DataClassName('SeriesRow')
class SeriesTable extends Table with _Id {
  @override
  String get tableName => 'series';

  TextColumn get title => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get overview => text().nullable()();
}

@DataClassName('SeasonRow')
class Seasons extends Table with _Id {
  @override
  String get tableName => 'season';

  IntColumn get seriesId =>
      integer().references(SeriesTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get number => integer()();
  TextColumn get title => text().nullable()();
}

@DataClassName('CollectionRow')
class Collections extends Table with _Id {
  @override
  String get tableName => 'collection';

  TextColumn get name => text()();

  /// user / photoAlbum (a collection of films from an online database is
  /// not offered: ADR-048).
  TextColumn get type => text()();
  TextColumn get externalId => text().nullable()();
}

@DataClassName('ServerAccountRow')
class ServerAccounts extends Table with _Id {
  @override
  String get tableName => 'server_account';

  /// jellyfin / emby / plex / subsonic / immich / nextcloud / audiobookshelf.
  TextColumn get type => text()();
  TextColumn get baseUrl => text()();
  TextColumn get userName => text().nullable()();
  TextColumn get credentialKey => text().nullable()();
  BoolColumn get syncProgress => boolean().withDefault(const Constant(false))();
}

@DataClassName('ServerItemMapRow')
class ServerItemMap extends Table {
  @override
  String get tableName => 'server_item_map';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId =>
      integer().references(ServerAccounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get remoteId => text()();

  @override
  Set<Column> get primaryKey => {itemId, accountId};
}

@DataClassName('DownloadRow')
class Downloads extends Table with _Id {
  @override
  String get tableName => 'download';

  /// Remote URI being mirrored (NET-018).
  TextColumn get remoteUri => text()();
  IntColumn get sourceId => integer().nullable().references(
    Sources,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get title => text()();
  TextColumn get localPath => text()();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  TextColumn get state =>
      textEnum<DownloadState>().withDefault(const Constant('queued'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get error => text().nullable()();
}

@DataClassName('ScanJobRow')
class ScanJobs extends Table with _Id {
  @override
  String get tableName => 'scan_job';

  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get state =>
      textEnum<ScanJobState>().withDefault(const Constant('queued'))();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get filesSeen => integer().withDefault(const Constant(0))();
  IntColumn get added => integer().withDefault(const Constant(0))();
  IntColumn get updated => integer().withDefault(const Constant(0))();
  IntColumn get removed => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
}

@DataClassName('ThumbCacheRow')
class ThumbCache extends Table {
  @override
  String get tableName => 'thumb_cache';

  TextColumn get key => text()();
  TextColumn get path => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('SettingRow')
class SettingsTable extends Table {
  @override
  String get tableName => 'setting';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ShaderPresetRow')
class ShaderPresets extends Table with _Id {
  @override
  String get tableName => 'shader_preset';

  TextColumn get name => text()();
  TextColumn get definition => text()();
}

@DataClassName('EqPresetRow')
class EqPresets extends Table with _Id {
  @override
  String get tableName => 'eq_preset';

  TextColumn get name => text()();
  TextColumn get definition => text()();
}

@DataClassName('SubtitleCacheRow')
class SubtitleCache extends Table with _Id {
  @override
  String get tableName => 'subtitle_cache';

  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get provider => text()();
  TextColumn get language => text()();
  TextColumn get path => text()();
  DateTimeColumn get fetchedAt => dateTime()();
}

@DataClassName('ScrobbleRow')
class ScrobbleQueue extends Table with _Id {
  @override
  String get tableName => 'scrobble_queue';

  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get service => text()();
  TextColumn get payload => text()();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// URL/stream history, newest first, capped at 50 (CORE-005).
@DataClassName('UrlHistoryRow')
class UrlHistory extends Table with _Id {
  @override
  String get tableName => 'url_history';

  TextColumn get url => text().unique()();

  /// JSON map of custom headers (NET-006); values never include secrets.
  TextColumn get headers => text().withDefault(const Constant('{}'))();
  TextColumn get userAgent => text().nullable()();
  DateTimeColumn get openedAt => dateTime()();
}

/// Folders behind the parental PIN gate (LIB-013); a whole source is gated
/// by `sources.locked`.
@DataClassName('LockedFolderRow')
class LockedFolders extends Table {
  @override
  String get tableName => 'locked_folder';

  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get relPath => text()();

  @override
  Set<Column> get primaryKey => {sourceId, relPath};
}
