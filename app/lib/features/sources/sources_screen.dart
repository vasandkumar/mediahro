import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/library/library_hub_screen.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro/features/sources/add_share_screen.dart';
import 'package:mediahro/features/sources/backup_screen.dart';
import 'package:mediahro/features/sources/downloads_screen.dart';
import 'package:mediahro/features/sources/open_url_dialog.dart';
import 'package:mediahro/features/sources/source_detail_screen.dart';
import 'package:mediahro/features/sources/wifi_transfer_screen.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens the media-server add flow (lane C4: Jellyfin, Emby, Plex, ...).
final addServerActionProvider = Provider<void Function(BuildContext context)?>(
  (ref) => null,
);

/// Starts cloud-drive sign-in (needs C4's AuthBrowser; null until then).
final addCloudActionProvider = Provider<void Function(BuildContext context)?>(
  (ref) => null,
);

/// Sources (docs/06 §3.4): every source with its health, last scan and
/// item count; add local folders, network shares, servers, cloud drives,
/// DLNA servers and URLs.
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summaries = ref.watch(sourceSummariesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appNavSources),
        actions: [
          IconButton(
            tooltip: l10n.sourcesOpenUrl,
            icon: const Icon(Icons.link),
            onPressed: () => showOpenUrlDialog(context),
          ),
          PopupMenuButton<_Menu>(
            tooltip: l10n.sourcesMore,
            onSelected: (m) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => switch (m) {
                  _Menu.downloads => const DownloadsScreen(),
                  _Menu.transfer => const WifiTransferScreen(),
                  _Menu.backup => const BackupScreen(),
                  _Menu.library => const LibraryHubScreen(),
                },
              ),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _Menu.downloads,
                child: Text(l10n.sourcesDownloads),
              ),
              PopupMenuItem(
                value: _Menu.transfer,
                child: Text(l10n.sourcesWifiTransfer),
              ),
              PopupMenuItem(
                value: _Menu.backup,
                child: Text(l10n.sourcesBackup),
              ),
              PopupMenuItem(
                value: _Menu.library,
                child: Text(l10n.libraryTools),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddSourceSheet(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.sourcesAdd),
      ),
      body: summaries.when(
        loading: () => const SkeletonList(),
        error: (e, _) => EmptyState(message: l10n.sourcesLoadError),
        data: (list) => list.isEmpty
            ? EmptyState(
                message: l10n.sourcesEmpty,
                actions: [
                  FilledButton.tonal(
                    onPressed: () => _addFolder(context, ref),
                    child: Text(l10n.sourcesAddFolder),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _addShare(context),
                    child: Text(l10n.sourcesAddShare),
                  ),
                  if (ref.watch(addServerActionProvider) case final add?)
                    FilledButton.tonal(
                      onPressed: () => add(context),
                      child: Text(l10n.sourcesAddServer),
                    ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: KSpacing.s48 * 2),
                itemCount: list.length,
                itemBuilder: (context, i) => SourceTile(summary: list[i]),
              ),
      ),
    );
  }
}

enum _Menu { downloads, transfer, backup, library }

Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await ref.read(sourceRepositoryProvider).addLocalFolder();
    if (id != null) unawaited(ref.read(scanServiceProvider).scan(id));
  } on PlatformCapabilityUnavailable {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.sourcesFolderPickerUnavailable)),
    );
  }
}

void _addShare(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AddShareScreen()));

/// The add flow (docs/06 §3.4): local folder · network share · media
/// server · cloud drive · DLNA · URL.
Future<void> showAddSourceSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final l10n = AppLocalizations.of(sheet);
        void go(void Function() f) {
          Navigator.of(sheet).pop();
          f();
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.sourcesAddFolder),
                subtitle: Text(l10n.sourcesAddFolderHint),
                onTap: () => go(() => _addFolder(context, ref)),
              ),
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: Text(l10n.sourcesAddShare),
                subtitle: Text(l10n.sourcesAddShareHint),
                onTap: () => go(() => _addShare(context)),
              ),
              if (ref.read(addServerActionProvider) case final add?)
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(l10n.sourcesAddServer),
                  subtitle: Text(l10n.sourcesAddServerHint),
                  onTap: () => go(() => add(context)),
                ),
              if (ref.read(addCloudActionProvider) case final add?)
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(l10n.sourcesAddCloud),
                  subtitle: Text(l10n.sourcesAddCloudHint),
                  onTap: () => go(() => add(context)),
                ),
              ListTile(
                leading: const Icon(Icons.cast_outlined),
                title: Text(l10n.sourcesAddDlna),
                subtitle: Text(l10n.sourcesAddDlnaHint),
                onTap: () => go(
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddShareScreen(dlna: true),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(l10n.sourcesOpenUrl),
                subtitle: Text(l10n.sourcesOpenUrlHint),
                onTap: () => go(() => showOpenUrlDialog(context)),
              ),
            ],
          ),
        );
      },
    );

/// A source row: health dot, name, item count and last scan.
class SourceTile extends ConsumerWidget {
  const SourceTile({required this.summary, super.key});

  final SourceSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = summary.source;
    final scheme = Theme.of(context).colorScheme;
    final health = summary.health;
    final color = switch (health) {
      SourceHealth.ok => KBrand.tertiary,
      SourceHealth.unreachable => scheme.error,
      SourceHealth.unknown || SourceHealth.disabled => scheme.outline,
    };
    final last = s.lastScanAt;
    final subtitle = [
      l10n.sourcesItemCount(summary.items),
      if (last != null)
        l10n.sourcesLastScan(
          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .add_jm()
              .format(last.toLocal()),
        ),
      if (health == SourceHealth.unreachable && s.lastSeenAt != null)
        l10n.sourcesUnavailableSince(
          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .format(s.lastSeenAt!.toLocal()),
        ),
    ].join(' · ');
    return Opacity(
      // docs/06 §9: offline sources dimmed; cached items still play.
      opacity:
          health == SourceHealth.unreachable || health == SourceHealth.disabled
          ? 0.6
          : 1,
      child: ListTile(
        minTileHeight: KTarget.min + KSpacing.s16,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(_icon(s.kind)),
            Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                label: l10n.sourcesHealth(health.name),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(s.name),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SourceDetailScreen(sourceId: s.id),
          ),
        ),
      ),
    );
  }

  static IconData _icon(SourceKind k) => switch (k) {
    SourceKind.local => Icons.folder_outlined,
    SourceKind.smb ||
    SourceKind.nfs ||
    SourceKind.ftp ||
    SourceKind.sftp => Icons.lan_outlined,
    SourceKind.webdav || SourceKind.cloud => Icons.cloud_outlined,
    SourceKind.dlna => Icons.cast_outlined,
    SourceKind.url => Icons.link,
    SourceKind.server => Icons.dns_outlined,
    SourceKind.archive => Icons.folder_zip_outlined,
  };
}
