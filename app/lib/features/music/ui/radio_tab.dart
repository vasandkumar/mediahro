import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/parsers/playlist_parser.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/radio/radio_stations.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Internet radio (MUS-014): the user's stations, added by stream address
/// or imported from a station list; no directory.
class RadioTab extends ConsumerStatefulWidget {
  const RadioTab({super.key});

  @override
  ConsumerState<RadioTab> createState() => _RadioTabState();
}

class _RadioTabState extends ConsumerState<RadioTab> {
  List<RadioStation>? _stations;
  StreamSubscription<List<RadioStation>>? _sub;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(radioStationsProvider);
    _sub = repo.changes.listen((l) {
      if (mounted) setState(() => _stations = l);
    });
    unawaited(
      repo.all().then((l) {
        if (mounted) setState(() => _stations = l);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _edit([RadioStation? s]) async {
    final repo = ref.read(radioStationsProvider);
    final result = await showDialog<RadioStation>(
      context: context,
      builder: (_) => _StationDialog(
        station: s ?? RadioStation(id: repo.newId(), name: '', url: Uri()),
        isNew: s == null,
      ),
    );
    if (result != null) await repo.save(result);
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final storage = ref.read(storageProvider);
    final picked = await storage.pickFiles(kinds: const {PickKind.playlist});
    if (picked.isEmpty) return;
    final file = picked.first;
    final format = playlistFormatFor(file.name) ?? PlaylistFormat.m3u;
    try {
      final bytes = await readPickedFile(storage, file.uri, maxBytes: 4 << 20);
      final parsed = await parsePlaylistIsolated(bytes, format);
      final n = await ref.read(radioStationsProvider).importPlaylist(parsed);
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.musicStationsImported(n))),
      );
    } on Exception {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.musicStationsImported(0))),
      );
    }
  }

  Future<void> _export() async {
    final m3u = await ref.read(radioStationsProvider).exportM3u();
    await ref
        .read(storageProvider)
        .saveFile(
          suggestedName: 'Radio.m3u',
          mimeType: 'audio/x-mpegurl',
          content: Stream.value(utf8.encode(m3u)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stations = _stations;
    final playing = ref.watch(
      musicPlayerStateProvider.select((s) => s.value?.station?.id),
    );
    if (stations == null) return const KSkeletonRows();
    final sorted = [...stations]
      ..sort((a, b) {
        if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(KSpacing.s8),
          child: Wrap(
            spacing: KSpacing.s8,
            children: [
              ActionChip(
                avatar: Icon(KIcon.add.resolve(theme.family), size: 18),
                label: Text(l10n.musicAddStation),
                onPressed: () => unawaited(_edit()),
              ),
              ActionChip(
                avatar: Icon(KIcon.importFile.resolve(theme.family), size: 18),
                label: Text(l10n.musicImportStations),
                onPressed: () => unawaited(_import()),
              ),
              if (stations.isNotEmpty)
                ActionChip(
                  avatar: Icon(
                    KIcon.exportFile.resolve(theme.family),
                    size: 18,
                  ),
                  label: Text(l10n.musicExportStations),
                  onPressed: () => unawaited(_export()),
                ),
            ],
          ),
        ),
        if (stations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(KSpacing.s24),
            child: Text(l10n.musicRadioEmpty),
          ),
        for (final s in sorted)
          KRow(
            title: s.name,
            subtitle: s.url.host,
            selected: s.id == playing,
            semanticLabel: l10n.musicPlayStation(s.name),
            leading: Icon(
              s.favourite ? Icons.star : Icons.radio,
              color: s.favourite ? theme.colorScheme.primary : null,
            ),
            trailing: PopupMenuButton<String>(
              tooltip: l10n.musicMoreActions(s.name),
              onSelected: (v) async {
                final repo = ref.read(radioStationsProvider);
                switch (v) {
                  case 'fav':
                    await repo.save(s.copyWith(favourite: !s.favourite));
                  case 'edit':
                    await _edit(s);
                  case 'delete':
                    await repo.delete(s.id);
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'fav',
                  checked: s.favourite,
                  child: Text(l10n.musicStationFavourite),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Text(l10n.musicEditStation),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l10n.musicDeleteStation),
                ),
              ],
            ),
            onTap: () =>
                unawaited(ref.read(musicPlayerProvider).playStation(s)),
          ),
      ],
    );
  }
}

class _StationDialog extends StatefulWidget {
  const _StationDialog({required this.station, required this.isNew});

  final RadioStation station;
  final bool isNew;

  @override
  State<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<_StationDialog> {
  late final _name = TextEditingController(text: widget.station.name);
  late final _url = TextEditingController(
    text: widget.isNew ? '' : widget.station.url.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    var text = _url.text.trim();
    if (!text.contains('://')) text = 'http://$text';
    final url = Uri.tryParse(text);
    if (url == null || !isStreamUrl(url)) {
      setState(() => _error = l10n.musicStationUrlInvalid);
      return;
    }
    final name = _name.text.trim().isEmpty ? url.host : _name.text.trim();
    Navigator.of(context).pop(widget.station.copyWith(name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.isNew ? l10n.musicAddStation : l10n.musicEditStation),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l10n.musicStationUrl,
              errorText: _error,
            ),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.musicStationName),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.musicSave)),
      ],
    );
  }
}
