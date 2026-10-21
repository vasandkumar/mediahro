import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_player.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/extras.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The player while an audiobook is in play (POD-001): cover, chapter,
/// position and time left in the book, chapter and 30-second buttons,
/// speed, skip silence, sleep timer, chapters and bookmarks.
class BookPlayerScreen extends ConsumerStatefulWidget {
  const BookPlayerScreen({required this.state, super.key});

  final BookPlayerState state;

  @override
  ConsumerState<BookPlayerScreen> createState() => _BookPlayerScreenState();
}

class _BookPlayerScreenState extends ConsumerState<BookPlayerScreen> {
  /// Where the slider is while dragged, so the position doesn't jump back
  /// before the seek lands.
  double? _drag;

  static const _skip = Duration(seconds: 30);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = widget.state;
    final book = s.book!;
    final player = ref.read(bookPlayerProvider);
    final chapter = s.chapter;
    final index = s.chapterIndex;
    final total = s.duration.inMilliseconds;
    final value = _drag ?? s.position.inMilliseconds.toDouble();
    final shown = Duration(milliseconds: value.round());
    final sleeping = ref.watch(sleepTimerStateProvider).value?.active ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.musicClose,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.musicBookNowPlaying),
        actions: [
          IconButton(
            tooltip: l10n.musicBookChapters,
            icon: const Icon(Icons.list),
            onPressed: s.chapters.isEmpty
                ? null
                : () => showBookChaptersSheet(context),
          ),
          IconButton(
            tooltip: l10n.musicBookBookmarks,
            icon: Badge(
              isLabelVisible: s.bookmarks.isNotEmpty,
              label: Text(l10n.musicBookNumber(s.bookmarks.length)),
              child: const Icon(Icons.bookmarks_outlined),
            ),
            onPressed: () => showBookmarksSheet(context),
          ),
          IconButton(
            tooltip: l10n.musicSleepTimer,
            isSelected: sleeping || s.stopAtChapterEnd,
            icon: const Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime, color: theme.colorScheme.primary),
            onPressed: () => showSleepSheet(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: KSpacing.s16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 320,
                    maxHeight: c.maxHeight * 0.4,
                  ),
                  child: CoverArt(
                    itemId: book.coverItemId,
                    radius: 12,
                    semanticLabel: book.title,
                  ),
                ),
                const SizedBox(height: KSpacing.s16),
                Text(
                  book.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                if (book.author != null)
                  Text(
                    book.author!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: KSpacing.s8),
                if (chapter != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      bookChapterTitle(l10n, chapter, index),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                if (index >= 0)
                  Text(
                    l10n.musicBookChapterOf(index + 1, s.chapters.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: KSpacing.s16),
                Semantics(
                  label: l10n.musicBookPosition,
                  value: formatDuration(shown),
                  child: Slider(
                    max: total <= 0 ? 1 : total.toDouble(),
                    value: value.clamp(0, total <= 0 ? 1 : total.toDouble()),
                    onChanged: total <= 0
                        ? null
                        : (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      setState(() => _drag = null);
                      unawaited(player.seek(Duration(milliseconds: v.round())));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(shown)),
                    Text(
                      l10n.musicBookLeft(
                        formatDuration(
                          Duration(
                            microseconds:
                                ((s.duration - shown).inMicroseconds / s.speed)
                                    .round()
                                    .clamp(0, 1 << 62),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: l10n.musicBookPreviousChapter,
                      iconSize: 32,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: s.chapters.isEmpty
                          ? null
                          : () => unawaited(player.previousChapter()),
                    ),
                    IconButton(
                      tooltip: l10n.musicBookBack30,
                      iconSize: 36,
                      icon: const Icon(Icons.replay_30),
                      onPressed: () => unawaited(player.skip(-_skip)),
                    ),
                    IconButton.filled(
                      tooltip: s.playing
                          ? l10n.musicPauseLabel
                          : l10n.musicPlayLabel,
                      iconSize: 44,
                      icon: Icon(s.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () => unawaited(player.togglePlayPause()),
                    ),
                    IconButton(
                      tooltip: l10n.musicBookForward30,
                      iconSize: 36,
                      icon: const Icon(Icons.forward_30),
                      onPressed: () => unawaited(player.skip(_skip)),
                    ),
                    IconButton(
                      tooltip: l10n.musicBookNextChapter,
                      iconSize: 32,
                      icon: const Icon(Icons.skip_next),
                      onPressed: s.chapters.isEmpty
                          ? null
                          : () => unawaited(player.nextChapter()),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.s8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: KSpacing.s8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.speed, size: 18),
                      label: Text(l10n.musicBookSpeedValue(s.speed)),
                      tooltip: l10n.musicBookSpeed,
                      onPressed: () => showBookSpeedSheet(context),
                    ),
                    FilterChip(
                      label: Text(l10n.musicBookSkipSilence),
                      selected: s.skipSilence,
                      onSelected: (v) =>
                          unawaited(player.setSkipSilence(enabled: v)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(l10n.musicBookAddBookmark),
                      onPressed: () =>
                          unawaited(addBookmarkDialog(context, ref)),
                    ),
                  ],
                ),
                if (s.stopAtChapterEnd)
                  Padding(
                    padding: const EdgeInsets.only(top: KSpacing.s8),
                    child: Text(
                      l10n.musicBookSleepEndOfChapterOn,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: KSpacing.s24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chapter's name, or "Chapter n" when the file has none.
String bookChapterTitle(AppLocalizations l10n, BookChapter c, int index) =>
    c.title.isEmpty ? l10n.musicBookChapterUnnamed(index + 1) : c.title;

/// Asks for an optional note and marks the current place.
Future<void> addBookmarkDialog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final note = await _askNote(
    context,
    title: l10n.musicBookAddBookmark,
    action: l10n.musicSave,
  );
  if (note == null) return;
  await ref.read(bookPlayerProvider).addBookmark(note: note);
  messenger?.showSnackBar(SnackBar(content: Text(l10n.musicBookBookmarkAdded)));
}

Future<String?> _askNote(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NoteDialog(title: title, action: action, initial: initial),
);

/// Owns its text controller, so it is disposed only after the dialog has
/// finished animating away.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(labelText: l10n.musicBookNote),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

void showBookChaptersSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.8, child: _ChaptersList()),
  ),
);

class _ChaptersList extends ConsumerWidget {
  const _ChaptersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s =
        ref.watch(bookPlayerStateProvider).value ?? const BookPlayerState();
    final player = ref.read(bookPlayerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
          child: Text(
            l10n.musicBookChapters,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: s.chapters.length,
            itemBuilder: (context, i) {
              final c = s.chapters[i];
              return ListTile(
                selected: i == s.chapterIndex,
                leading: Text(l10n.musicBookNumber(i + 1)),
                title: Text(bookChapterTitle(l10n, c, i)),
                trailing: Text(formatDuration(c.start)),
                onTap: () {
                  unawaited(player.toChapter(i));
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

void showBookmarksSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.7, child: _BookmarksList()),
  ),
);

class _BookmarksList extends ConsumerWidget {
  const _BookmarksList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s =
        ref.watch(bookPlayerStateProvider).value ?? const BookPlayerState();
    final player = ref.read(bookPlayerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.musicBookBookmarks,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(l10n.musicBookAddBookmark),
                onPressed: () => unawaited(addBookmarkDialog(context, ref)),
              ),
            ],
          ),
        ),
        Expanded(
          child: s.bookmarks.isEmpty
              ? Center(child: Text(l10n.musicBookNoBookmarks))
              : ListView(
                  children: [
                    for (final b in s.bookmarks)
                      ListTile(
                        title: Text(formatDuration(b.at)),
                        subtitle: b.note.isEmpty ? null : Text(b.note),
                        onTap: () {
                          unawaited(player.goToBookmark(b));
                          Navigator.of(context).pop();
                        },
                        trailing: PopupMenuButton<String>(
                          tooltip: l10n.musicBookBookmarkActions,
                          onSelected: (v) async {
                            if (v == 'edit') {
                              final note = await _askNote(
                                context,
                                title: l10n.musicBookEditNote,
                                action: l10n.musicSave,
                                initial: b.note,
                              );
                              if (note != null) {
                                await player.editBookmark(b.id, note);
                              }
                            } else {
                              await player.removeBookmark(b.id);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(l10n.musicBookEditNote),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(l10n.musicBookDeleteBookmark),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

const bookSpeedPresets = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

void showBookSpeedSheet(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SpeedSheet(),
  ),
);

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s =
        ref.watch(bookPlayerStateProvider).value ?? const BookPlayerState();
    final player = ref.read(bookPlayerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.musicBookSpeed,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: KSpacing.s8),
            Text(l10n.musicBookSpeedValue(s.speed)),
            Semantics(
              label: l10n.musicBookSpeed,
              child: Slider(
                min: 0.5,
                max: 3,
                divisions: 50,
                value: s.speed.clamp(0.5, 3.0),
                label: l10n.musicBookSpeedValue(s.speed),
                onChanged: (v) =>
                    unawaited(player.setSpeed((v * 20).round() / 20)),
              ),
            ),
            Wrap(
              spacing: KSpacing.s8,
              children: [
                for (final p in bookSpeedPresets)
                  ChoiceChip(
                    label: Text(l10n.musicBookSpeedValue(p)),
                    selected: (s.speed - p).abs() < 0.001,
                    onSelected: (_) => unawaited(player.setSpeed(p)),
                  ),
              ],
            ),
            Text(
              l10n.musicBookSpeedRemembered,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
