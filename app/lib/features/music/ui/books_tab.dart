import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/music/books/book.dart';
import 'package:mediahro/features/music/books/book_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/ui/music_widgets.dart';
import 'package:mediahro/features/music/ui/now_playing.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens [book] where the listener left it and shows the player (POD-001).
Future<void> playBook(BuildContext context, WidgetRef ref, Book book) async {
  await ref.read(bookPlayerProvider).open(book);
  if (context.mounted) openNowPlaying(context);
}

/// The Audiobooks tab (POD-001): books in progress first, then the rest,
/// finished ones last.
class BooksTab extends ConsumerWidget {
  const BooksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(bookEntriesProvider);
    final entries = async.value;
    if (entries == null) {
      return async.hasError
          ? KEmptyState(message: l10n.musicBooksEmpty)
          : const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return KEmptyState(
        title: l10n.musicTabBooks,
        message: l10n.musicBooksEmpty,
      );
    }
    final playing = ref.watch(
      bookPlayerStateProvider.select((s) => s.value?.book?.id),
    );
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(bookEntriesProvider),
      child: ListView.builder(
        itemCount: entries.length + 1,
        itemBuilder: (context, i) => i == entries.length
            ? const SizedBox(height: 96)
            : BookRow(
                entry: entries[i],
                playing: entries[i].book.id == playing,
              ),
      ),
    );
  }
}

class BookRow extends ConsumerWidget {
  const BookRow({required this.entry, required this.playing, super.key});

  final BookEntry entry;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = entry.book;
    final left = Duration(
      microseconds: (book.duration.inMicroseconds * (1 - entry.fraction))
          .round(),
    );
    final status = entry.finished
        ? l10n.musicBookFinished
        : entry.started
        ? l10n.musicBookLeft(formatDuration(left))
        : l10n.musicBookNotStarted;
    return Semantics(
      selected: playing,
      child: InkWell(
        onTap: () => unawaited(playBook(context, ref, book)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KSpacing.s16,
              vertical: KSpacing.s8,
            ),
            child: Row(
              children: [
                CoverArt(itemId: book.coverItemId, size: 56),
                const SizedBox(width: KSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: playing ? theme.colorScheme.primary : null,
                        ),
                      ),
                      if (book.author != null)
                        Text(
                          book.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: KSpacing.s4),
                      if (entry.started && !entry.finished)
                        ExcludeSemantics(
                          child: LinearProgressIndicator(value: entry.fraction),
                        ),
                      Text(status, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.musicMoreActions(book.title),
                  onSelected: (v) async {
                    final store = ref.read(bookStoreProvider);
                    switch (v) {
                      case 'start':
                        await store.saveProgress(
                          book.id,
                          (entry.progress ?? const BookProgress()).copyWith(
                            trackIndex: 0,
                            position: Duration.zero,
                            finished: false,
                          ),
                        );
                      case 'music':
                        await store.setMark(book.id, 'music');
                    }
                    ref.invalidate(bookEntriesProvider);
                  },
                  itemBuilder: (_) => [
                    if (entry.started || entry.finished)
                      PopupMenuItem(
                        value: 'start',
                        child: Text(l10n.musicBookStartOver),
                      ),
                    PopupMenuItem(
                      value: 'music',
                      child: Text(l10n.musicBookTreatAsMusic),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
