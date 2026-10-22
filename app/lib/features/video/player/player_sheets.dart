import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/video/player/languages.dart';
import 'package:mediahro/features/video/player/player_platform.dart';
import 'package:mediahro/features/video/player/sleep_sheet.dart';
import 'package:mediahro/features/video/player/sleep_timer.dart';
import 'package:mediahro/features/video/player/speed.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sheets.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/features/video/subtitles/subtitle_speech.dart';
import 'package:mediahro/features/video/subtitles/subtitle_text_source.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// "English · AC-3 · 5.1" style line for a track (VID-065).
String trackLabel(AppLocalizations l, Track t, int index) {
  final name = languageName(t.language);
  final title = t.title;
  final head = name.isEmpty
      ? (title ?? l.videoTrackNumber(index + 1))
      : (title == null || title == name
            ? name
            : l.videoTrackNamed(name, title));
  return head;
}

/// Subtitle formats by their usual names (SUB-010, SUB-011); format names
/// are not translated.
const _subtitleFormats = {
  'subrip': 'SRT',
  'srt': 'SRT',
  'ass': 'ASS',
  'ssa': 'SSA',
  'webvtt': 'WebVTT',
  'mov_text': 'MP4 Timed Text',
  'microdvd': 'MicroDVD',
  'sami': 'SAMI',
  'ttml': 'TTML',
  'text': 'Text',
  'eia_608': 'CEA-608',
  'hdmv_pgs_subtitle': 'PGS',
  'pgssub': 'PGS',
  'dvd_subtitle': 'VobSub',
  'dvdsub': 'VobSub',
  'dvb_subtitle': 'DVB',
  'dvbsub': 'DVB',
};

String formatName(Track t) {
  final codec = t.codec;
  if (codec == null) return '';
  return (t.type == TrackType.subtitle
          ? _subtitleFormats[codec.toLowerCase()]
          : null) ??
      codec.toUpperCase();
}

String trackDetail(AppLocalizations l, Track t) => [
  if (t.codec != null) formatName(t),
  if (t.channels case final c?)
    switch (c) {
      6 => l.videoTrackSurround51,
      8 => l.videoTrackSurround71,
      _ => l.videoTrackChannels(c),
    },
  if (t.isDefault) l.videoTrackDefault,
  if (t.isForced) l.videoTrackForced,
  if (t.isExternal) l.videoTrackExternal,
  if (t.isHearingImpaired) l.videoTrackHearingImpaired,
  if (t.isAudioDescription) l.videoTrackAudioDescription,
].join(' · ');

/// Rebuilds [builder] whenever the controller changes.
class _Live extends StatelessWidget {
  const _Live(this.controller, this.builder);

  final VideoPlayerController controller;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    // List tiles paint their ink on the nearest Material; the sheet's
    // surface is a coloured box.
    builder: (c, _) =>
        Material(type: MaterialType.transparency, child: builder(c)),
  );
}

Future<void> showSpeedSheet(BuildContext context, VideoPlayerController c) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoSpeedTitle,
    builder: (_) => _Live(c, (context) {
      final rate = c.rate;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.videoSpeedValue(rate),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          Slider(
            value: rate.clamp(PlaybackSpeed.min, PlaybackSpeed.max),
            min: PlaybackSpeed.min,
            max: PlaybackSpeed.max,
            divisions:
                ((PlaybackSpeed.max - PlaybackSpeed.min) / PlaybackSpeed.step)
                    .round(),
            label: l.videoSpeedValue(rate),
            semanticFormatterCallback: l.videoSpeedValue,
            onChanged: (v) => unawaited(c.setRate(v)),
          ),
          Wrap(
            spacing: KSpacing.s8,
            runSpacing: KSpacing.s8,
            alignment: WrapAlignment.center,
            children: [
              for (final p in PlaybackSpeed.presets)
                KChip(
                  label: l.videoSpeedValue(p),
                  selected: (rate - p).abs() < 0.001,
                  onSelected: (_) => unawaited(c.setRate(p)),
                ),
            ],
          ),
        ],
      );
    }),
  );
}

Future<void> showAudioSheet(BuildContext context, VideoPlayerController c) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoAudioTitle,
    builder: (_) => _Live(c, (context) {
      final tracks = c.tracksOf(TrackType.audio);
      final delay = c.audioDelay;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VolumeRow(c),
          const Divider(),
          if (tracks.isEmpty) Text(l.videoNoAudioTracks),
          RadioGroup<int>(
            groupValue: c.state.audioTrackId,
            onChanged: (id) {
              final t = tracks.where((x) => x.id == id).firstOrNull;
              if (t != null) unawaited(c.selectAudio(t));
            },
            child: Column(
              children: [
                for (final (i, t) in tracks.indexed)
                  RadioListTile<int>(
                    value: t.id,
                    title: Text(trackLabel(l, t, i)),
                    subtitle: Text(trackDetail(l, t)),
                  ),
              ],
            ),
          ),
          const Divider(),
          _DelayRow(
            label: l.videoAudioDelay,
            value: l.videoDelayValue(delay.inMilliseconds),
            onMinus: () =>
                c.setAudioDelay(delay - const Duration(milliseconds: 10)),
            onPlus: () =>
                c.setAudioDelay(delay + const Duration(milliseconds: 10)),
            onReset: () => c.setAudioDelay(Duration.zero),
          ),
        ],
      );
    }),
  );
}

/// Subtitle tracks, files, encoding and delay (SUB-012, 013, 015).
/// [onAddFile] picks a subtitle file; null where there is no picker.
Future<void> showSubtitleSheet(
  BuildContext context,
  VideoPlayerController c, {
  Future<void> Function()? onAddFile,
  Future<void> Function()? onEdit,
  SubtitleSpeaker? speaker,
  SubtitleTextSource? textSource,
  Future<void> Function()? onTranslate,
  Future<void> Function()? onSync,
}) {
  final l = AppLocalizations.of(context);
  final player = context;
  return KSheet.show<void>(
    context,
    title: l.videoSubtitlesTitle,
    builder: (sheetContext) => _Live(c, (context) {
      final tracks = c.tracksOf(TrackType.subtitle);
      final delay = c.subtitleDelay;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<int>(
            // -1 stands for "Off" (RadioGroup values are non-null here).
            groupValue: c.state.subtitleTrackId ?? -1,
            onChanged: (id) => unawaited(
              c.selectSubtitle(tracks.where((x) => x.id == id).firstOrNull),
            ),
            child: Column(
              children: [
                RadioListTile<int>(value: -1, title: Text(l.videoSubtitlesOff)),
                for (final (i, t) in tracks.indexed)
                  RadioListTile<int>(
                    value: t.id,
                    title: Text(trackLabel(l, t, i)),
                    subtitle: Text(trackDetail(l, t)),
                  ),
              ],
            ),
          ),
          if (onAddFile != null)
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: Text(l.videoSubtitleAddFile),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(onAddFile());
              },
            ),
          if (speaker != null)
            StatefulBuilder(
              builder: (context, setState) => SwitchListTile(
                secondary: const Icon(Icons.record_voice_over_outlined),
                title: Text(l.videoReadAloud),
                subtitle: Text(
                  textSource?.available ?? false
                      ? l.videoReadAloudDetail
                      : l.videoTranslateOnlyFiles,
                ),
                value: speaker.enabled,
                onChanged: (v) => setState(() => speaker.enabled = v),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.graphic_eq_rounded),
            title: Text(l.videoSyncTitle),
            enabled: onSync != null && (textSource?.available ?? false),
            subtitle: Text(
              onSync == null
                  ? l.videoSyncNeedsEngine
                  : textSource?.available ?? false
                  ? l.videoSyncDetail
                  : l.videoTranslateOnlyFiles,
            ),
            onTap: onSync == null
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onSync());
                  },
          ),
          if (onTranslate != null)
            ListTile(
              leading: const Icon(Icons.g_translate_outlined),
              title: Text(l.videoTranslate),
              enabled: textSource?.available ?? false,
              subtitle: textSource?.available ?? false
                  ? null
                  : Text(l.videoTranslateOnlyFiles),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(onTranslate());
              },
            ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: Text(l.videoEditorOpen),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(onEdit());
              },
            ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(l.videoCharsetTitle),
            subtitle: Text(charsetLabel(l, c.subtitleCodepage)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(showCharsetSheet(player, c));
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: Text(l.videoSubSpeedTitle),
            subtitle: Text(subtitleSpeedLabel(l, c.subtitleSpeed)),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(showSubtitleSpeedSheet(player, c));
            },
          ),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: Text(l.videoSubSecondaryTitle),
            subtitle: Text(switch (c
                .tracksOf(TrackType.subtitle)
                .indexed
                .where((e) => e.$2.id == c.state.secondarySubtitleTrackId)
                .firstOrNull) {
              final (int, Track) e? => trackLabel(l, e.$2, e.$1),
              null => l.videoSubtitlesOff,
            }),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(
                showSecondarySubtitleSheet(
                  player,
                  c,
                  label: (t, i) => trackLabel(l, t, i),
                ),
              );
            },
          ),
          const Divider(),
          _DelayRow(
            label: l.videoSubtitleDelay,
            value: l.videoDelayValue(delay.inMilliseconds),
            onMinus: () =>
                c.setSubtitleDelay(delay - const Duration(milliseconds: 50)),
            onPlus: () =>
                c.setSubtitleDelay(delay + const Duration(milliseconds: 50)),
            onReset: () => c.setSubtitleDelay(Duration.zero),
          ),
        ],
      );
    }),
  );
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.onReset,
  });

  final String label;
  final String value;
  final Future<void> Function() onMinus;
  final Future<void> Function() onPlus;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          tooltip: l.videoDelayEarlier,
          icon: const Icon(Icons.remove_rounded),
          onPressed: () => unawaited(onMinus()),
        ),
        Semantics(liveRegion: true, child: Text(value)),
        IconButton(
          tooltip: l.videoDelayLater,
          icon: const Icon(Icons.add_rounded),
          onPressed: () => unawaited(onPlus()),
        ),
        KIconButton(
          icon: KIcon.reset,
          label: l.videoDelayReset,
          onPressed: () => unawaited(onReset()),
        ),
      ],
    );
  }
}

/// Chapters and bookmarks (VID-063).
Future<void> showChaptersSheet(BuildContext context, VideoPlayerController c) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoChaptersTitle,
    builder: (sheetContext) => _Live(c, (context) {
      final chapters = c.chapters;
      final current = c.currentChapter;
      final dur = c.state.duration ?? Duration.zero;
      String t(Duration d) => formatMediaDuration(d, reference: dur);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chapters.isEmpty) Text(l.videoNoChapters),
          for (final (i, ch) in chapters.indexed)
            ListTile(
              selected: i == current,
              leading: Text(t(ch.start)),
              title: Text(ch.title ?? l.videoChapterNumber(i + 1)),
              onTap: () {
                unawaited(c.seekToChapter(ch));
                Navigator.of(sheetContext).pop();
              },
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.videoBookmarksTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              KButton(
                label: l.videoBookmarkAdd,
                icon: KIcon.add,
                onPressed: () => _addBookmark(context, c),
              ),
            ],
          ),
          if (c.bookmarks.isEmpty) Text(l.videoNoBookmarks),
          for (final b in c.bookmarks)
            ListTile(
              leading: Text(t(b.position)),
              title: Text(b.note.isEmpty ? l.videoBookmarkUntitled : b.note),
              onTap: () {
                unawaited(c.seekTo(b.position));
                Navigator.of(sheetContext).pop();
              },
              trailing: Wrap(
                children: [
                  KIconButton(
                    icon: KIcon.edit,
                    label: l.videoBookmarkEdit,
                    onPressed: () => _editBookmark(context, c, b),
                  ),
                  KIconButton(
                    icon: KIcon.delete,
                    label: l.videoBookmarkDelete,
                    onPressed: () => c.removeBookmark(b),
                  ),
                ],
              ),
            ),
        ],
      );
    }),
  );
}

Future<String?> _noteDialog(BuildContext context, String initial) {
  final l = AppLocalizations.of(context);
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.videoBookmarkNote),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(hintText: l.videoBookmarkNoteHint),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.videoCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(text.text),
          child: Text(l.videoSave),
        ),
      ],
    ),
  );
}

Future<void> _addBookmark(BuildContext context, VideoPlayerController c) async {
  final at = c.state.position;
  final note = await _noteDialog(context, '');
  if (note == null) return;
  c.addBookmark(note: note.trim(), at: at);
}

Future<void> _editBookmark(
  BuildContext context,
  VideoPlayerController c,
  VideoBookmark b,
) async {
  final note = await _noteDialog(context, b.note);
  if (note != null) c.editBookmark(b, note.trim());
}

/// The overflow sheet: chapters and bookmarks, picture-in-picture, playing
/// on in the background for this video, and sound only (VID-063, 067, 068).
Future<void> showMoreSheet(
  BuildContext context,
  VideoPlayerController c,
  PlayerPlatform platform,
  SleepTimer sleep,
) {
  final l = AppLocalizations.of(context);
  // Follow-up sheets open from the player, after this one has closed.
  final player = context;
  void then(BuildContext sheetContext, void Function() next) {
    Navigator.of(sheetContext).pop();
    next();
  }

  return KSheet.show<void>(
    context,
    title: l.videoMoreTitle,
    builder: (sheetContext) => _Live(
      c,
      (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.bookmarks_outlined),
            title: Text(l.videoChaptersTitle),
            onTap: () => then(
              sheetContext,
              () => unawaited(showChaptersSheet(player, c)),
            ),
          ),
          if (platform.pipSupported)
            ListTile(
              leading: const Icon(Icons.picture_in_picture_alt_outlined),
              title: Text(l.videoPip),
              onTap: () =>
                  then(sheetContext, () => unawaited(platform.enterPip())),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: platform.backgroundThisSession,
            builder: (context, on, _) => SwitchListTile(
              secondary: const Icon(Icons.headphones_outlined),
              title: Text(l.videoKeepPlayingInBackground),
              subtitle: Text(l.videoKeepPlayingInBackgroundDetail),
              value: on || platform.backgroundAllowed,
              onChanged: (v) => platform.backgroundThisSession.value = v,
            ),
          ),
          // Turning the phone rotates the player instead of staying locked to the
          // video's shape (VID-070); off goes back to following the video.
          ListenableBuilder(
            listenable: platform.settings,
            builder: (_, _) => SwitchListTile(
              secondary: const Icon(Icons.screen_rotation_outlined),
              title: Text(l.videoRotationAllow),
              subtitle: Text(l.videoRotationAllowDetail),
              value:
                  platform.settings.get(VideoSettings.orientation) ==
                  VideoOrientation.auto,
              onChanged: (v) => platform.settings.set(
                VideoSettings.orientation,
                v ? VideoOrientation.auto : VideoOrientation.followVideo,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.videocam_off_outlined),
            title: Text(l.videoAudioOnly),
            subtitle: Text(l.videoAudioOnlyDetail),
            value: c.videoOff,
            onChanged: (v) => unawaited(c.setVideoOff(off: v)),
          ),
          ListenableBuilder(
            listenable: sleep,
            builder: (_, _) => ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(l.videoSleepTitle),
              subtitle: Text(sleepLabel(l, sleep, c.state.duration)),
              onTap: () => then(
                sheetContext,
                () => unawaited(showSleepSheet(player, sleep)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Manual subtitle character set (SUB-013): automatic detection, or one of
/// [subtitleCharsets].
Future<void> showCharsetSheet(BuildContext context, VideoPlayerController c) {
  final l = AppLocalizations.of(context);
  return KSheet.show<void>(
    context,
    title: l.videoCharsetTitle,
    builder: (sheetContext) {
      final current = c.subtitleCodepage;
      Widget option(String? iconv) => ListTile(
        title: Text(charsetLabel(l, iconv)),
        selected: current == iconv,
        trailing: current == iconv ? const Icon(Icons.check_rounded) : null,
        onTap: () {
          unawaited(c.setSubtitleCodepage(iconv));
          Navigator.of(sheetContext).pop();
        },
      );
      return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(null),
            for (final (iconv, _) in subtitleCharsets) option(iconv),
          ],
        ),
      );
    },
  );
}
