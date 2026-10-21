import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/format.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/dsd_output.dart';
import 'package:mediahro/features/music/player/music_dsp.dart';
import 'package:mediahro/features/music/player/sleep_timer.dart';
import 'package:mediahro/features/music/ui/now_playing.dart' show askName;
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

/// The Now Playing action row (MUS-006): sound/EQ, output, sleep timer,
/// favourite, rating, add to playlist and info.
class NowPlayingActions extends ConsumerWidget {
  const NowPlayingActions({required this.track, super.key});

  final MusicTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (rating, favourite) =
        ref.watch(ratingProvider(track.itemId)).value ?? (null, false);
    final sleep = ref.watch(sleepTimerStateProvider).value;
    final eqOn = ref.watch(musicSoundProvider).value?.eqEnabled ?? false;
    final ratings = ref.read(musicRatingsProvider);
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: favourite ? l10n.musicUnfavourite : l10n.musicFavourite,
          isSelected: favourite,
          icon: const Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite, color: theme.colorScheme.primary),
          onPressed: () => unawaited(
            ratings.setFavourite(track.itemId, favourite: !favourite),
          ),
        ),
        IconButton(
          tooltip: rating == null
              ? l10n.musicNotRated
              : l10n.musicRatingValue(_stars(rating)),
          isSelected: rating != null,
          icon: const Icon(Icons.star_border),
          selectedIcon: Icon(Icons.star, color: theme.colorScheme.primary),
          onPressed: () => showRatingSheet(context, track),
        ),
        IconButton(
          tooltip: l10n.musicSound,
          isSelected: eqOn,
          icon: const Icon(Icons.equalizer),
          selectedIcon: Icon(Icons.equalizer, color: theme.colorScheme.primary),
          onPressed: () => showSoundSheet(context),
        ),
        IconButton(
          tooltip: l10n.musicOutput,
          icon: const Icon(Icons.speaker_group_outlined),
          onPressed: () => showOutputSheet(context),
        ),
        IconButton(
          tooltip: sleep?.active ?? false
              ? sleepLabel(l10n, sleep!)
              : l10n.musicSleepTimer,
          isSelected: sleep?.active ?? false,
          icon: const Icon(Icons.bedtime_outlined),
          selectedIcon: Icon(Icons.bedtime, color: theme.colorScheme.primary),
          onPressed: () => showSleepSheet(context),
        ),
        IconButton(
          tooltip: l10n.musicAddToPlaylist,
          icon: const Icon(Icons.playlist_add),
          onPressed: () => unawaited(addToPlaylist(context, ref, [track])),
        ),
        IconButton(
          tooltip: l10n.musicInfo,
          icon: Icon(KIcon.info.resolve(theme.family)),
          onPressed: () => showInfoSheet(context, track),
        ),
      ],
    );
  }
}

String _stars(int value) =>
    value.isEven ? '${value ~/ 2}' : (value / 2).toStringAsFixed(1);

String sleepLabel(AppLocalizations l10n, SleepTimerState s) => switch (s.mode) {
  SleepMode.time => l10n.musicSleepRemaining(
    formatMediaDuration(s.remaining ?? Duration.zero),
  ),
  SleepMode.tracks ||
  SleepMode.endOfTrack => l10n.musicSleepTracksLeft(s.tracksLeft ?? 1),
  SleepMode.off => l10n.musicSleepTimer,
};

// ------------------------------------------------------------------ rating --

void showRatingSheet(BuildContext context, MusicTrack track) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _RatingSheet(track: track),
  ),
);

class _RatingSheet extends ConsumerWidget {
  const _RatingSheet({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (rating, _) =
        ref.watch(ratingProvider(track.itemId)).value ?? (null, false);
    final r = ref.read(musicRatingsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.musicRating, style: theme.textTheme.titleMedium),
            const SizedBox(height: KSpacing.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    tooltip: l10n.musicSetRating('$star'),
                    iconSize: 36,
                    icon: Icon(
                      (rating ?? 0) >= star * 2
                          ? Icons.star
                          : (rating ?? 0) == star * 2 - 1
                          ? Icons.star_half
                          : Icons.star_border,
                      color: theme.colorScheme.primary,
                    ),
                    // Tapping the same full star again gives the half star.
                    onPressed: () => unawaited(
                      r.setRating(
                        track.itemId,
                        rating == star * 2 ? star * 2 - 1 : star * 2,
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              rating == null
                  ? l10n.musicNotRated
                  : l10n.musicRatingValue(_stars(rating)),
            ),
            TextButton(
              onPressed: rating == null
                  ? null
                  : () => unawaited(r.setRating(track.itemId, null)),
              child: Text(l10n.musicClearRating),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- sound --

void showSoundSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.85, child: SoundSheet()),
  ),
);

/// EQ quick access (MUS-006 over AUD-005), volume levelling (AUD-004) and
/// crossfade (AUD-003) for music.
class SoundSheet extends ConsumerStatefulWidget {
  const SoundSheet({super.key});

  @override
  ConsumerState<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends ConsumerState<SoundSheet> {
  List<CustomEqPreset> _custom = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadCustom());
  }

  Future<void> _loadCustom() async {
    final c = await ref.read(musicDspProvider).customPresets();
    if (mounted) setState(() => _custom = c);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dsp = ref.read(musicDspProvider);
    final s = ref.watch(musicSoundProvider).value ?? dsp.sound;
    void update(MusicSound n) => unawaited(dsp.update(n));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
      children: [
        Text(l10n.musicSound, style: theme.textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.musicEqOn),
          value: s.eqEnabled,
          onChanged: (v) => update(s.copyWith(eqEnabled: v)),
        ),
        Text(l10n.musicPresets, style: theme.textTheme.titleSmall),
        const SizedBox(height: KSpacing.s8),
        Wrap(
          spacing: KSpacing.s8,
          runSpacing: KSpacing.s8,
          children: [
            for (final id in builtInEqPresets.keys)
              ChoiceChip(
                label: Text(l10n.musicEqPreset(id)),
                selected: s.eqEnabled && s.preset == id,
                onSelected: (_) => unawaited(dsp.applyPreset(id)),
              ),
            for (final p in _custom)
              InputChip(
                label: Text(p.name),
                selected: s.eqEnabled && s.preset == 'custom:${p.id}',
                onSelected: (_) => unawaited(dsp.applyPreset('custom:${p.id}')),
                deleteButtonTooltipMessage: l10n.musicDeletePreset(p.name),
                onDeleted: () async {
                  await dsp.deletePreset(p.id);
                  await _loadCustom();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.musicSavePreset),
              onPressed: () async {
                final name = await askName(
                  context,
                  title: l10n.musicSavePreset,
                  label: l10n.musicPresetName,
                  action: l10n.musicSave,
                );
                if (name == null) return;
                await dsp.savePreset(name);
                await _loadCustom();
              },
            ),
          ],
        ),
        const SizedBox(height: KSpacing.s16),
        Text(l10n.musicEqualizer, style: theme.textTheme.titleSmall),
        for (var i = 0; i < eqBandsHz.length; i++)
          _BandSlider(
            label: l10n.musicEqBand(_hz(eqBandsHz[i])),
            value: s.gains[i],
            enabled: s.eqEnabled,
            onChanged: (v) {
              final g = [...s.gains]..[i] = v;
              update(s.copyWith(gains: g, preset: 'custom'));
            },
          ),
        _BandSlider(
          label: l10n.musicPreamp,
          value: s.preampDb,
          enabled: s.eqEnabled,
          onChanged: (v) => update(s.copyWith(preampDb: v)),
        ),
        const Divider(height: KSpacing.s32),
        Text(l10n.musicLoudness, style: theme.textTheme.titleSmall),
        RadioGroup<LoudnessMode>(
          groupValue: s.loudness,
          onChanged: (v) => update(s.copyWith(loudness: v)),
          child: Column(
            children: [
              for (final m in LoudnessMode.values)
                RadioListTile<LoudnessMode>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.musicLoudnessMode(m.name)),
                  value: m,
                ),
            ],
          ),
        ),
        const Divider(height: KSpacing.s32),
        Text(l10n.musicCrossfade, style: theme.textTheme.titleSmall),
        Slider(
          max: 12,
          divisions: 12,
          value: s.crossfade.inSeconds.toDouble(),
          label: l10n.musicCrossfadeValue(s.crossfade.inSeconds),
          semanticFormatterCallback: (v) => l10n.musicCrossfadeValue(v.round()),
          onChanged: (v) =>
              update(s.copyWith(crossfade: Duration(seconds: v.round()))),
        ),
        Text(l10n.musicCrossfadeValue(s.crossfade.inSeconds)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.musicCrossfadeOnSkip),
          value: s.crossfadeOnSkip,
          onChanged: s.crossfade == Duration.zero
              ? null
              : (v) => update(s.copyWith(crossfadeOnSkip: v)),
        ),
        const SizedBox(height: KSpacing.s32),
      ],
    );
  }

  static String _hz(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final db = value.toStringAsFixed(1);
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Slider(
            min: -12,
            max: 12,
            divisions: 48,
            value: value.clamp(-12, 12),
            label: db,
            semanticFormatterCallback: (v) =>
                l10n.musicEqBandValue(label, v.toStringAsFixed(1)),
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            db,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ output --

void showOutputSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _OutputSheet(),
  ),
);

class _OutputSheet extends ConsumerStatefulWidget {
  const _OutputSheet();

  @override
  ConsumerState<_OutputSheet> createState() => _OutputSheetState();
}

class _OutputSheetState extends ConsumerState<_OutputSheet> {
  List<EngineAudioDevice> _devices = const [];
  String? _selected;

  /// Native DSD (AUD-043): offered only once the OS has granted a
  /// bit-perfect path at the DoP rate on the selected DAC.
  bool _dsdOffered = false;
  bool _dsdOn = false;
  int _probe = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final d = await ref
        .read(playbackEngineProvider(EngineRole.music))
        .audioDevices();
    final saved = await ref.read(dsdOutputGateProvider)?.savedDevice();
    if (!mounted) return;
    setState(() {
      _devices = d;
      if (saved != null) {
        _selected = saved;
        _dsdOffered = true;
        _dsdOn = true;
      }
    });
  }

  /// Applies the selection. A plain device switches native DSD off; the
  /// offer for the new device waits for the OS grant.
  Future<void> _select(String? device) async {
    final probe = ++_probe;
    final gate = ref.read(dsdOutputGateProvider);
    setState(() {
      _selected = device;
      _dsdOffered = false;
      _dsdOn = false;
    });
    await ref
        .read(playbackEngineProvider(EngineRole.music))
        .setAudioOutput(DsdOutputGate.config(device, nativeDsd: false));
    await gate?.save(null);
    if (gate == null || device == null) return;
    final dac = _devices.where((d) => d.id == device).firstOrNull;
    final offered = dac != null && await gate.offerFor(dac) != null;
    if (mounted && probe == _probe && offered) {
      setState(() => _dsdOffered = true);
    }
  }

  Future<void> _setDsd({required bool on}) async {
    final device = _selected;
    if (device == null) return;
    setState(() => _dsdOn = on);
    await ref
        .read(playbackEngineProvider(EngineRole.music))
        .setAudioOutput(DsdOutputGate.config(device, nativeDsd: on));
    await ref.read(dsdOutputGateProvider)?.save(on ? device : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info =
        ref.watch(musicPlayerStateProvider).value?.playback.audio ??
        const AudioOutputInfo();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
        children: [
          Text(l10n.musicOutput, style: theme.textTheme.titleLarge),
          const SizedBox(height: KSpacing.s8),
          if (info.device != null) Text(info.device!),
          if (info.sampleRate != null)
            Text(
              l10n.musicOutputFormat(
                (info.sampleRate! / 1000).toStringAsFixed(1),
                info.bitDepth ?? 16,
                info.channels ?? 2,
              ),
            ),
          Text(l10n.musicOutputPath(info.path.name)),
          if (info.bluetoothCodec != null)
            Text(l10n.musicBluetoothCodec(info.bluetoothCodec!)),
          const Divider(height: KSpacing.s24),
          Text(l10n.musicOutputDevice, style: theme.textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: _selected ?? '',
            onChanged: (id) =>
                unawaited(_select(id == null || id.isEmpty ? null : id)),
            child: Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.musicOutputSystemDefault),
                  value: '',
                ),
                for (final d in _devices.where((d) => !d.isDefault))
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d.name),
                    value: d.id,
                  ),
              ],
            ),
          ),
          if (_dsdOffered)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.musicDsdNative),
              subtitle: Text(l10n.musicDsdNativeHint),
              value: _dsdOn,
              onChanged: (on) => unawaited(_setDsd(on: on)),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- sleep --

void showSleepSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _SleepSheet(),
  ),
);

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final timer = ref.read(sleepTimerProvider);
    final s = ref.watch(sleepTimerStateProvider).value ?? SleepTimerState.off;
    final book = ref.watch(bookPlayerStateProvider).value;
    void close() => Navigator.of(context).pop();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              l10n.musicSleepTimer,
              style: theme.textTheme.titleLarge,
            ),
            subtitle: s.active ? Text(sleepLabel(l10n, s)) : null,
          ),
          // A running timer's controls come first.
          if (s.active || (book?.stopAtChapterEnd ?? false))
            ListTile(
              title: Text(l10n.musicSleepOff),
              onTap: () {
                timer.cancel();
                unawaited(
                  ref
                      .read(bookPlayerProvider)
                      .setStopAtChapterEnd(enabled: false),
                );
                close();
              },
            ),
          if (s.mode == SleepMode.time)
            ListTile(
              title: Text(l10n.musicSleepExtend),
              onTap: () => timer.extend(const Duration(minutes: 5)),
            ),
          for (final m in const [5, 10, 15, 30, 45, 60, 90])
            ListTile(
              title: Text(l10n.musicSleepMinutes(m)),
              onTap: () {
                timer.startTime(Duration(minutes: m));
                close();
              },
            ),
          if (book?.active ?? false)
            ListTile(
              title: Text(l10n.musicBookSleepEndOfChapter),
              selected: book!.stopAtChapterEnd,
              onTap: () {
                unawaited(
                  ref
                      .read(bookPlayerProvider)
                      .setStopAtChapterEnd(enabled: true),
                );
                close();
              },
            ),
          ListTile(
            title: Text(l10n.musicSleepEndOfTrack),
            onTap: () {
              timer.startEndOfTrack();
              close();
            },
          ),
          for (final n in const [2, 3, 5])
            ListTile(
              title: Text(l10n.musicSleepTracks(n)),
              onTap: () {
                timer.startTracks(n);
                close();
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- playlist --

/// Adds [tracks] to a manual playlist, or a new one (MUS-006 "add to").
Future<void> addToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<MusicTrack> tracks,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(playlistRepositoryProvider);
  final db = ref.read(libraryDatabaseProvider);
  final manual = await (db.select(
    db.playlists,
  )..where((p) => p.rule.isNull())).get();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await showDialog<(int?, String)>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(l10n.musicAddToPlaylist),
      children: [
        for (final p in manual)
          SimpleDialogOption(
            onPressed: () => Navigator.of(d).pop((p.id, p.name)),
            child: Text(p.name),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(d).pop((null, '')),
          child: Text(l10n.musicNewPlaylist),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  var (id, name) = picked;
  if (id == null) {
    final typed = await askName(
      context,
      title: l10n.musicNewPlaylist,
      label: l10n.musicPlaylistName,
      action: l10n.musicCreate,
    );
    if (typed == null) return;
    name = typed;
    id = await repo.createManual(typed, mode: 'audio');
  }
  await repo.addItems(id, [for (final t in tracks) t.itemId]);
  messenger?.showSnackBar(
    SnackBar(content: Text(l10n.musicAddedToPlaylist(name))),
  );
}

// -------------------------------------------------------------------- info --

void showInfoSheet(BuildContext context, MusicTrack track) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _InfoSheet(track: track),
  ),
);

class _InfoSheet extends ConsumerWidget {
  const _InfoSheet({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final db = ref.read(libraryDatabaseProvider);
    return FutureBuilder(
      future: (db.select(
        db.items,
      )..where((i) => i.id.equals(track.itemId))).getSingleOrNull(),
      builder: (context, snap) {
        final item = snap.data;
        String? gain() {
          final t = track.trackGainDb;
          final a = track.albumGainDb;
          if (t == null && a == null) return null;
          return [
            if (t != null) '${t.toStringAsFixed(2)} dB',
            if (a != null) '${a.toStringAsFixed(2)} dB',
          ].join(' · ');
        }

        final rows = <(String, String?)>[
          (l10n.musicInfoPath, track.relPath),
          (
            l10n.musicInfoFormat,
            item == null
                ? null
                : [item.ext.toUpperCase(), ?item.audioCodec].join(' · '),
          ),
          (
            l10n.musicInfoSize,
            item == null ? null : formatBytes(item.size, l10n),
          ),
          (
            l10n.musicInfoDuration,
            track.duration == null
                ? null
                : formatMediaDuration(track.duration!),
          ),
          (l10n.musicInfoPlays, '${track.playCount}'),
          (l10n.musicInfoGain, gain()),
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(KSpacing.s16),
            children: [
              Text(track.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: KSpacing.s8),
              for (final (k, v) in rows)
                if (v != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: KSpacing.s4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(k, style: theme.textTheme.labelLarge),
                        ),
                        Expanded(child: SelectableText(v)),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
