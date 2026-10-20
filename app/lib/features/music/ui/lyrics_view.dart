import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/lyrics/lrc.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Lyrics in Now Playing (MUS-005): synced lines follow playback (karaoke
/// scroll, word highlight for enhanced LRC), tap a line to seek, text size,
/// edit/create, and the opt-in online lookup.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({required this.track, super.key});

  final MusicTrack track;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  double _scale = 1;
  int _shown = -2;
  final _keys = <int, GlobalKey>{};
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadScale());
  }

  Future<void> _loadScale() async {
    final v = await ref.read(musicPrefsProvider).read('lyricsScale');
    if (v is num && mounted) {
      setState(() => _scale = v.toDouble().clamp(0.7, 2.0));
    }
  }

  void _setScale(double s) {
    setState(() => _scale = s.clamp(0.7, 2.0));
    unawaited(ref.read(musicPrefsProvider).write('lyricsScale', _scale));
  }

  void _follow(int line) {
    if (line == _shown || line < 0) return;
    _shown = line;
    final ctx = _keys[line]?.currentContext;
    if (ctx == null) return;
    final reduce = KAccessibility.reduceMotion(context);
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _searchOnline() async {
    final l10n = AppLocalizations.of(context);
    final store = ref.read(settingsStoreProvider);
    final key = CoreSettings.endpoint(Endpoints.lrclib.id);
    if (!store.get(key)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.musicLyricsSearchOnline),
          content: Text(l10n.musicLyricsOnlineOff),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.musicCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.musicLyricsTurnOnOnline),
            ),
          ],
        ),
      );
      if (ok != true) return;
      store.set(key, true);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _searching = true);
    try {
      final found = await ref
          .read(lyricsServiceProvider)
          .lookupOnline(widget.track);
      if (found == null) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.musicLyricsNotFound)),
        );
      }
      ref.invalidate(lyricsProvider(widget.track));
    } on Exception {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.musicLyricsError)));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(lyricsProvider(widget.track));
    final lyrics = async.value;
    final position = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.position),
    );
    final player = ref.read(musicPlayerProvider);
    if (async.isLoading && lyrics == null || _searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final toolbar = Row(
      children: [
        if (lyrics != null)
          Expanded(
            child: Text(
              l10n.musicLyricsOrigin(lyrics.origin.name),
              style: theme.textTheme.labelMedium,
            ),
          )
        else
          const Spacer(),
        IconButton(
          tooltip: l10n.musicLyricsSmaller,
          icon: const Icon(Icons.text_decrease),
          onPressed: () => _setScale(_scale - 0.1),
        ),
        IconButton(
          tooltip: l10n.musicLyricsBigger,
          icon: const Icon(Icons.text_increase),
          onPressed: () => _setScale(_scale + 0.1),
        ),
        IconButton(
          tooltip: lyrics?.synced ?? false
              ? l10n.musicLyricsEdit
              : l10n.musicLyricsCreate,
          icon: Icon(KIcon.edit.resolve(theme.family)),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  LrcEditorScreen(track: widget.track, initial: lyrics),
            ),
          ),
        ),
      ],
    );
    if (lyrics == null || lyrics.isEmpty) {
      return Column(
        children: [
          toolbar,
          Expanded(
            child: KEmptyState(
              message: l10n.musicNoLyrics,
              actions: [
                FilledButton(
                  onPressed: () => unawaited(_searchOnline()),
                  child: Text(l10n.musicLyricsSearchOnline),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final current = lyrics.synced
        ? lyrics.lineAt(position ?? Duration.zero)
        : -1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(current));
    final base = theme.textTheme.titleLarge!.copyWith(
      fontSize: (theme.textTheme.titleLarge!.fontSize ?? 22) * _scale,
      height: 1.4,
    );
    return Column(
      children: [
        toolbar,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: KSpacing.s48),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, i) {
              final line = lyrics.lines[i];
              final active = i == current;
              final past = lyrics.synced && i < current;
              final style = base.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(
                        alpha: past ? 0.45 : 0.6,
                      ),
              );
              final t = line.time;
              Widget text = active && line.words.isNotEmpty
                  ? _WordLine(line: line, position: position!, style: style)
                  : Text(line.text, style: style);
              if (t != null) {
                text = Semantics(
                  button: true,
                  label: l10n.musicLyricsLineAt(
                    formatMediaDuration(t),
                    line.text,
                  ),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => unawaited(player.seek(t)),
                    child: text,
                  ),
                );
              }
              return Padding(
                key: _keys.putIfAbsent(i, GlobalKey.new),
                padding: const EdgeInsets.symmetric(
                  horizontal: KSpacing.s8,
                  vertical: KSpacing.s4,
                ),
                child: text,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The active line of enhanced LRC: words light up as they are sung.
class _WordLine extends StatelessWidget {
  const _WordLine({
    required this.line,
    required this.position,
    required this.style,
  });

  final LyricLine line;
  final Duration position;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final dim = style.copyWith(color: style.color?.withValues(alpha: 0.5));
    final hot = style.copyWith(color: Theme.of(context).colorScheme.primary);
    return Text.rich(
      TextSpan(
        children: [
          for (final w in line.words)
            TextSpan(text: w.text, style: w.time <= position ? hot : dim),
        ],
      ),
    );
  }
}

/// Creates or edits synced lyrics by tapping along (MUS-005).
class LrcEditorScreen extends ConsumerStatefulWidget {
  const LrcEditorScreen({required this.track, this.initial, super.key});

  final MusicTrack track;
  final Lyrics? initial;

  @override
  ConsumerState<LrcEditorScreen> createState() => _LrcEditorScreenState();
}

class _LrcEditorScreenState extends ConsumerState<LrcEditorScreen> {
  LrcEditorModel? _model;
  int? _selected;
  late final _text = TextEditingController(
    text: widget.initial?.toPlainText() ?? '',
  );

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null && !i.isEmpty) {
      _model = LrcEditorModel(i);
      if (i.synced) _model!.cursor = i.lines.length;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final m = _model;
    if (m == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    await ref.read(lyricsServiceProvider).saveEdited(widget.track, m.result());
    ref.invalidate(lyricsProvider(widget.track));
    messenger?.showSnackBar(SnackBar(content: Text(l10n.musicLyricsSaved)));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(musicPlayerStateProvider).value;
    final player = ref.read(musicPlayerProvider);
    final position = s?.position ?? Duration.zero;
    final m = _model;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial?.synced ?? false
              ? l10n.musicLyricsEdit
              : l10n.musicLyricsCreate,
        ),
        actions: [
          if (widget.initial?.origin == LyricsOrigin.edited)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await ref
                    .read(lyricsServiceProvider)
                    .deleteEdited(widget.track);
                ref.invalidate(lyricsProvider(widget.track));
                nav.pop();
              },
              child: Text(l10n.musicLyricsRevert),
            ),
          TextButton(
            onPressed: m == null ? null : () => unawaited(_save()),
            child: Text(l10n.musicSave),
          ),
        ],
      ),
      body: m == null
          ? ListView(
              padding: const EdgeInsets.all(KSpacing.s16),
              children: [
                Text(l10n.musicLyricsEditorHint),
                const SizedBox(height: KSpacing.s16),
                TextField(
                  controller: _text,
                  minLines: 8,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: l10n.musicLyricsText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: KSpacing.s16),
                FilledButton(
                  onPressed: () {
                    final parsed = parseLyrics(_text.text);
                    if (parsed.isEmpty) return;
                    setState(() => _model = LrcEditorModel(parsed));
                  },
                  child: Text(l10n.musicLyricsApplyText),
                ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(KSpacing.s16),
                  child: Text(l10n.musicLyricsEditorHint),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: m.lines.length,
                    itemBuilder: (context, i) {
                      final line = m.lines[i];
                      final t = line.time;
                      return ListTile(
                        selected: i == _selected || i == m.cursor,
                        leading: SizedBox(
                          width: 64,
                          child: Text(
                            t == null ? '—' : formatMediaDuration(t),
                            style: const TextStyle(
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        title: Text(line.text),
                        onTap: () => setState(() => _selected = i),
                        trailing: i == _selected && t != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: l10n.musicLyricsEarlier,
                                    icon: const Icon(Icons.remove),
                                    onPressed: () => setState(
                                      () => m.nudge(
                                        i,
                                        const Duration(milliseconds: -100),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.musicLyricsLater,
                                    icon: const Icon(Icons.add),
                                    onPressed: () => setState(
                                      () => m.nudge(
                                        i,
                                        const Duration(milliseconds: 100),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(KSpacing.s16),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: s?.playing ?? false
                              ? l10n.musicPauseLabel
                              : l10n.musicPlayLabel,
                          icon: Icon(
                            (s?.playing ?? false ? KIcon.pause : KIcon.play)
                                .resolve(theme.family),
                          ),
                          onPressed: () => unawaited(player.togglePlayPause()),
                        ),
                        IconButton(
                          tooltip: l10n.musicLyricsUndo,
                          icon: const Icon(Icons.undo),
                          onPressed: m.cursor == 0
                              ? null
                              : () => setState(m.back),
                        ),
                        Text(formatMediaDuration(position)),
                        const SizedBox(width: KSpacing.s16),
                        Expanded(
                          child: FilledButton(
                            onPressed: m.done
                                ? null
                                : () => setState(() => m.tap(position)),
                            child: Text(l10n.musicLyricsStamp),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
