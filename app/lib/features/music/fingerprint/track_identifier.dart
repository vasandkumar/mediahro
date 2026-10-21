import 'package:mediahro/features/music/fingerprint/acoustid_client.dart';
import 'package:mediahro/features/music/fingerprint/fingerprint_service.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/tag_editor.dart';

/// Identifies an untagged or mistagged song (MUS-010): fingerprint on the
/// device, one AcoustID lookup, and, only when the user picks a match,
/// the safe tag write of MUS-003 (verified temp file, undoable). Nothing is
/// ever written without that choice.
final class TrackIdentifier {
  TrackIdentifier({
    required this.fingerprinter,
    required this.client,
    required this.editor,
  });

  final TrackFingerprinter fingerprinter;
  final AcoustIdClient client;
  final TagEditor editor;

  /// False in a build without the AcoustID application key.
  bool get available => client.available;

  /// Possible identities of [t], best first. [onFingerprinted] fires when
  /// the on-device part is done and the lookup starts. Throws
  /// `NetworkBlocked` while the AcoustID endpoint is off.
  Future<List<SongMatch>> identify(
    MusicTrack t, {
    void Function()? onFingerprinted,
  }) async {
    final fp = await fingerprinter.of(t);
    onFingerprinted?.call();
    return await client.lookup(fp);
  }

  /// Writes [match] into [t]'s file: title, artist, album and year; fields
  /// the match does not have are left as they are.
  Future<TagEditResult> apply(MusicTrack t, SongMatch match) => editor.apply(
    [t],
    (_, _) => TagEdit(
      fields: {
        TagField.title: [match.title],
        if (match.artist != null) TagField.artist: [match.artist!],
        if (match.album != null) TagField.album: [match.album!],
        if (match.year != null) TagField.date: ['${match.year}'],
      },
    ),
  );
}
