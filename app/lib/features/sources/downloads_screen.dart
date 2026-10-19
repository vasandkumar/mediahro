import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/downloads.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/library/widgets.dart';

/// Offline downloads (NET-018): progress, pause/resume, remove, space used.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final m = ref.watch(downloadManagerProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourcesDownloads)),
      body: StreamBuilder<DownloadProgress>(
        stream: m.progress,
        builder: (context, _) => FutureBuilder<(List<DownloadRow>, int)>(
          future: (() async => (await m.all(), await m.usedBytes()))(),
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) return const SkeletonList();
            final (rows, used) = data;
            if (rows.isEmpty) {
              return EmptyState(message: l10n.sourcesDownloadsEmpty);
            }
            return ListView(
              children: [
                ListTile(
                  title: Text(
                    l10n.sourcesDownloadsUsed(
                      formatBytes(used, locale: locale),
                      formatBytes(m.quotaBytes, locale: locale),
                    ),
                  ),
                ),
                for (final d in rows)
                  ListTile(
                    title: Text(d.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.sourcesDownloadState(d.state.name)),
                        if (d.state == DownloadState.running ||
                            d.state == DownloadState.paused)
                          LinearProgressIndicator(
                            value: d.totalBytes == null
                                ? null
                                : d.receivedBytes / d.totalBytes!,
                          ),
                      ],
                    ),
                    trailing: Wrap(
                      children: [
                        if (d.state == DownloadState.running)
                          IconButton(
                            tooltip: l10n.sourcesPause,
                            icon: const Icon(Icons.pause),
                            onPressed: () => m.pause(d.id),
                          ),
                        if (d.state == DownloadState.paused ||
                            d.state == DownloadState.failed)
                          IconButton(
                            tooltip: l10n.sourcesResume,
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => m.resume(d.id),
                          ),
                        IconButton(
                          tooltip: l10n.sourcesRemove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => m.remove(d.id),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
