import 'package:mediahro/features/music/tags/ape.dart';
import 'package:mediahro/features/music/tags/audio_tags.dart';
import 'package:mediahro/features/music/tags/byte_reader.dart';
import 'package:mediahro/features/music/tags/id3.dart';
import 'package:mediahro/features/music/tags/tag_reader.dart';
import 'package:mediahro/features/music/tags/writer/id3_writer.dart';
import 'package:mediahro/features/music/tags/writer/mp4_writer.dart';
import 'package:mediahro/features/music/tags/writer/other_writers.dart';
import 'package:mediahro/features/music/tags/writer/tag_edit.dart';
import 'package:mediahro/features/music/tags/writer/vorbis_writer.dart';

/// Plans the rewrite of a file for an edit (MUS-003) in the file's own tag
/// format: ID3v2.4 for MPEG and DSF, Vorbis comments for FLAC and Ogg,
/// `ilst` for MP4, APEv2 for Monkey's Audio/WavPack/Musepack (and MP3s that
/// already have one), ASF objects for WMA, chunks for WAV/AIFF.
abstract final class TagWriter {
  static WritePlan plan(ByteReader r, AudioTags before, TagEdit edit) {
    final after = edit.applyTo(before);
    return switch (TagReader.detect(r)) {
      AudioContainer.flac => planFlac(r, after, edit),
      AudioContainer.ogg => planOgg(r, after, edit),
      AudioContainer.mp4 => planMp4(r, after, edit),
      AudioContainer.asf => planAsf(r, after, edit),
      AudioContainer.wav => planWav(r, after, edit),
      AudioContainer.aiff => planAiff(r, after, edit),
      AudioContainer.dsf => planDsf(r, after, edit),
      AudioContainer.apeFamily => planApe(r, after, edit),
      AudioContainer.mpeg => _mpeg(r, after, edit),
    };
  }

  /// MP3: ID3v2.4 at the start; an existing APE tag (and ID3v1) at the
  /// end is kept in step.
  static WritePlan _mpeg(ByteReader r, AudioTags after, TagEdit edit) {
    final v1 = hasId3v1(r);
    final ape = findApeTag(r, v1 ? r.length - 128 : r.length);
    if (ape == null) return planId3File(r, after, edit);
    final oldSize = id3v2Size(r, 0) ?? 0;
    final tag = buildId3v2(
      oldSize > 0 ? r : null,
      0,
      after,
      edit,
      minSize: oldSize,
    );
    // planApe: [audio before the APE tag, new APE tag, refreshed ID3v1].
    final apePlan = planApe(r, after, edit);
    return WritePlan([
      BytesPart(tag),
      RangePart(oldSize, ape.start - oldSize),
      ...apePlan.parts.skip(1),
    ]);
  }
}
