import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/scanner/scan_model.dart';
import 'package:mediahro/core/sources/connection_health.dart';
import 'package:mediahro/features/library/folder_browser_screen.dart';
import 'package:mediahro/features/sources/errors.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Mounts [source]'s file system for browsing and file operations.
Future<(VirtualFileSystem, Uri)> mountSource(
  WidgetRef ref,
  SourceRow source,
) async {
  final access = await ref.read(sourceResolverProvider).resolve(source);
  final fs = access.fileSystem();
  ref.read(mountsProvider).mount(access.root, fs);
  return (fs, access.root);
}

/// One source: scan schedule, what modes it feeds, metadata, scan control,
/// connection health (NET-019), browse, remove (docs/06 §3.4).
class SourceDetailScreen extends ConsumerStatefulWidget {
  const SourceDetailScreen({required this.sourceId, super.key});

  final int sourceId;

  @override
  ConsumerState<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends ConsumerState<SourceDetailScreen> {
  ScanProgress? _progress;
  StreamSubscription<ScanProgress>? _sub;
  HealthReport? _health;
  String? _healthError;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(scanServiceProvider)
        .progress
        .where((p) => p.sourceId == widget.sourceId)
        .listen((p) {
          if (mounted) setState(() => _progress = p);
        });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<SourceRow?> _row() {
    final db = ref.read(libraryDatabaseProvider);
    return (db.select(
      db.sources,
    )..where((s) => s.id.equals(widget.sourceId))).getSingleOrNull();
  }

  Future<void> _testHealth(SourceRow s) async {
    setState(() {
      _testing = true;
      _healthError = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final (fs, root) = await mountSource(ref, s);
      final r = await ConnectionHealth().test(fs, root);
      setState(() => _health = r);
    } on VirtualFileException catch (e) {
      setState(() => _healthError = fileErrorMessage(l10n, e.error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(sourceRepositoryProvider);
    final scans = ref.watch(scanServiceProvider);
    return StreamBuilder<void>(
      stream: repo.watch(),
      builder: (context, _) => FutureBuilder<SourceRow?>(
        future: _row(),
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return Scaffold(appBar: AppBar());
          final p = _progress;
          final scanning = scans.isScanning(s.id);
          Future<void> set({
            ScanSchedule? schedule,
            bool? video,
            bool? music,
            bool? photos,
            bool? scrape,
            bool? enabled,
          }) => repo.update(
            s.id,
            schedule: schedule,
            includeVideo: video,
            includeMusic: music,
            includePhotos: photos,
            scrapeMetadata: scrape,
            enabled: enabled,
          );
          return Scaffold(
            appBar: AppBar(title: Text(s.name)),
            body: ListView(
              children: [
                ListTile(
                  title: Text(l10n.sourcesScan),
                  subtitle: Text(
                    scanning && p != null
                        ? l10n.sourcesScanProgress(
                            p.filesSeen,
                            p.directoriesSeen,
                          )
                        : l10n.sourcesScanIdle,
                  ),
                  trailing: Wrap(
                    spacing: KSpacing.s8,
                    children: [
                      if (!scanning)
                        FilledButton.tonal(
                          onPressed: () => unawaited(scans.scan(s.id)),
                          child: Text(l10n.sourcesScanNow),
                        )
                      else ...[
                        if (p?.state == ScanJobState.paused)
                          OutlinedButton(
                            onPressed: () => scans.resume(s.id),
                            child: Text(l10n.sourcesResume),
                          )
                        else
                          OutlinedButton(
                            onPressed: () => scans.pause(s.id),
                            child: Text(l10n.sourcesPause),
                          ),
                        TextButton(
                          onPressed: () => scans.cancel(s.id),
                          child: Text(l10n.sourcesCancel),
                        ),
                      ],
                    ],
                  ),
                ),
                if (scanning) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpacing.s16,
                    KSpacing.s16,
                    KSpacing.s16,
                    KSpacing.s8,
                  ),
                  child: Text(
                    l10n.sourcesSchedule,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
                  child: SegmentedButton<ScanSchedule>(
                    segments: [
                      for (final v in ScanSchedule.values)
                        ButtonSegment(
                          value: v,
                          label: Text(l10n.sourcesScheduleName(v.name)),
                        ),
                    ],
                    selected: {s.schedule},
                    onSelectionChanged: (v) => set(schedule: v.first),
                  ),
                ),
                SwitchListTile(
                  title: Text(l10n.sourcesIncludeVideo),
                  value: s.includeVideo,
                  onChanged: (v) => set(video: v),
                ),
                SwitchListTile(
                  title: Text(l10n.sourcesIncludeMusic),
                  value: s.includeMusic,
                  onChanged: (v) => set(music: v),
                ),
                SwitchListTile(
                  title: Text(l10n.sourcesIncludePhotos),
                  value: s.includePhotos,
                  onChanged: (v) => set(photos: v),
                ),
                SwitchListTile(
                  title: Text(l10n.sourcesScrape),
                  subtitle: Text(l10n.sourcesScrapeHint),
                  value: s.scrapeMetadata,
                  onChanged: (v) => set(scrape: v),
                ),
                SwitchListTile(
                  title: Text(l10n.sourcesEnabled),
                  value: s.enabled,
                  onChanged: (v) => set(enabled: v),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(l10n.sourcesBrowse),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final (fs, root) = await mountSource(ref, s);
                    await nav.push(
                      MaterialPageRoute<void>(
                        builder: (_) => FolderBrowserScreen(
                          fileSystem: fs,
                          root: root,
                          title: s.name,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: Text(l10n.sourcesHealthTest),
                  subtitle: Text(
                    _testing
                        ? l10n.sourcesHealthTesting
                        : _healthError ??
                              (_health == null
                                  ? l10n.sourcesHealthTestHint
                                  : l10n.sourcesHealthResult(
                                      _health!.latency.inMilliseconds,
                                      (_health!.throughputMbps ?? 0).round(),
                                      _health!.suggestedCacheMiB,
                                    )),
                  ),
                  onTap: _testing ? null : () => _testHealth(s),
                ),
                if (_health?.warnings case final w? when w.isNotEmpty)
                  for (final warning in w)
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(l10n.sourcesHealthWarning(warning.name)),
                    ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(l10n.sourcesRemove),
                  subtitle: Text(l10n.sourcesRemoveHint),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: Text(l10n.sourcesRemoveTitle(s.name)),
                        content: Text(l10n.sourcesRemoveHint),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(d).pop(false),
                            child: Text(l10n.sourcesCancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(d).pop(true),
                            child: Text(l10n.sourcesRemove),
                          ),
                        ],
                      ),
                    );
                    if (ok ?? false) {
                      await repo.remove(s.id);
                      nav.pop();
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
