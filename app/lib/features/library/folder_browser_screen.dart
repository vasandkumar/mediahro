import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/batch.dart';
import 'package:mediahro/core/files/file_operations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/index/media_kind.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/library/widgets.dart';
import 'package:mediahro/features/sources/errors.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

enum BrowserSort { name, modified, size, fileType }

/// Opens a file from the browser (archives open as folders; media goes to
/// the player lanes via this hook).
final openFileActionProvider =
    Provider<void Function(BuildContext context, VirtualEntry entry)?>(
      (ref) => null,
    );

/// File browser over any source (FILE-001): breadcrumb, list/grid, sort,
/// multi-select with rename, move, copy, delete (trash + undo), new folder,
/// batch rename (FILE-002/003). Sidecars follow renames (FILE-006).
class FolderBrowserScreen extends ConsumerStatefulWidget {
  const FolderBrowserScreen({
    required this.fileSystem,
    required this.root,
    this.title,
    super.key,
  });

  final VirtualFileSystem fileSystem;
  final Uri root;
  final String? title;

  @override
  ConsumerState<FolderBrowserScreen> createState() =>
      _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends ConsumerState<FolderBrowserScreen> {
  late List<Uri> _stack = [widget.root];
  List<VirtualEntry>? _entries;
  VirtualFileError? _error;
  BrowserSort _sort = BrowserSort.name;
  bool _descending = false;
  bool _grid = false;
  final Set<Uri> _selected = {};

  Uri get _dir => _stack.last;
  bool get _mutable => widget.fileSystem is MutableFileSystem;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // Also runs from initState, so only the build method reads l10n.
    _entries = null;
    _error = null;
    if (mounted) setState(() {});
    try {
      final list = await widget.fileSystem
          .list(_dir)
          .where((e) => !e.name.startsWith('.'))
          .toList();
      if (mounted) setState(() => _entries = _sorted(list));
    } on VirtualFileException catch (e) {
      if (mounted) setState(() => _error = e.error);
    }
  }

  List<VirtualEntry> _sorted(List<VirtualEntry> l) {
    int cmp(VirtualEntry a, VirtualEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final r = switch (_sort) {
        BrowserSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        BrowserSort.modified => (a.modified ?? DateTime(0)).compareTo(
          b.modified ?? DateTime(0),
        ),
        BrowserSort.size => (a.size ?? 0).compareTo(b.size ?? 0),
        BrowserSort.fileType => MediaKinds.extensionOf(
          a.name,
        ).compareTo(MediaKinds.extensionOf(b.name)),
      };
      return _descending ? -r : r;
    }

    return [...l]..sort(cmp);
  }

  void _enter(VirtualEntry e) {
    if (_selected.isNotEmpty) return _toggle(e);
    if (e.isDirectory) {
      setState(() => _stack = [..._stack, e.uri]);
      unawaited(_load());
    } else {
      ref.read(openFileActionProvider)?.call(context, e);
    }
  }

  void _toggle(VirtualEntry e) => setState(
    () => _selected.contains(e.uri)
        ? _selected.remove(e.uri)
        : _selected.add(e.uri),
  );

  Future<void> _run(Future<void> Function(FileOperations ops) op) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await op(ref.read(fileOperationsProvider));
    } on VirtualFileException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(fileErrorMessage(l10n, e.error))),
      );
    }
    setState(_selected.clear);
    await _load();
  }

  Future<String?> _ask(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(d).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(l10n.sourcesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(c.text),
            child: Text(l10n.libraryOk),
          ),
        ],
      ),
    );
  }

  StorageFacade? get _storage {
    try {
      return ref.read(storageProvider);
    } on Object {
      return null;
    }
  }

  /// FILE-002 share / open in: hands the OS a URI other apps can read.
  Future<void> _handOver({required bool openWith}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final storage = _storage;
    final uris = <Uri>[];
    for (final u in _selected) {
      if (await shareableUri(widget.fileSystem, u) case final s?) uris.add(s);
    }
    if (storage == null || uris.isEmpty || uris.length < _selected.length) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryShareUnavailable)),
      );
      return;
    }
    try {
      if (openWith) {
        if (!await storage.openWith(uris.single)) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.libraryOpenWithNone)),
          );
        }
      } else {
        await storage.share(uris);
      }
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(l10n.sourcesErrorIo)));
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final uris = _selected.toList();
    // Local files and device media go to the OS trash (undoable).
    final local = uris.every(
      (u) => u.scheme == 'file' || u.scheme == 'mediastore',
    );
    var permanent = false;
    if (!local) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.libraryDeletePermanentTitle(uris.length)),
          content: Text(l10n.libraryDeletePermanentHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.sourcesCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.libraryDelete),
            ),
          ],
        ),
      );
      if (!(ok ?? false)) return;
      permanent = true;
    }
    await _run((ops) async {
      final r = await ops.delete(uris, allowPermanent: permanent);
      if (r.canUndo) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.libraryMovedToTrash(r.trashed.length)),
            action: SnackBarAction(
              label: l10n.libraryUndo,
              onPressed: () async {
                await ops.undoDelete(r);
                await _load();
              },
            ),
          ),
        );
      }
    });
  }

  Future<void> _batchRename() async {
    final l10n = AppLocalizations.of(context);
    final entries = (_entries ?? const <VirtualEntry>[])
        .where((e) => _selected.contains(e.uri))
        .toList();
    final pattern = await _ask(
      l10n.libraryBatchRenameTitle,
      initial: '{name} {n:2}',
    );
    if (pattern == null || pattern.isEmpty) return;
    final facts = [
      for (final e in entries) RenameFacts(name: e.name, modified: e.modified),
    ];
    final List<RenamePlan> plan;
    try {
      plan = planRename(facts, pattern);
    } on PatternError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.libraryPatternError(e.token))),
        );
      }
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.libraryBatchRenamePreview),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in plan)
                ListTile(
                  dense: true,
                  title: Text(p.to),
                  subtitle: Text(p.from),
                  trailing: p.conflict
                      ? Icon(
                          Icons.error_outline,
                          color: Theme.of(d).colorScheme.error,
                          semanticLabel: l10n.libraryConflict,
                        )
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.sourcesCancel),
          ),
          FilledButton(
            onPressed: plan.any((p) => p.conflict)
                ? null
                : () => Navigator.of(d).pop(true),
            child: Text(l10n.libraryRename),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _run(
        (ops) => applyRename(ops, [for (final e in entries) e.uri], plan),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries;
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          selecting
              ? l10n.librarySelected(_selected.length)
              : (widget.title ?? ''),
        ),
        leading: selecting
            ? IconButton(
                tooltip: l10n.sourcesCancel,
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        actions: [
          if (selecting) ...[
            IconButton(
              tooltip: l10n.libraryShare,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _handOver(openWith: false),
            ),
            if (_selected.length == 1)
              IconButton(
                tooltip: l10n.libraryOpenWith,
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _handOver(openWith: true),
              ),
          ],
          if (selecting && _mutable) ...[
            if (_selected.length == 1)
              IconButton(
                tooltip: l10n.libraryRename,
                icon: const Icon(Icons.drive_file_rename_outline),
                onPressed: () async {
                  final uri = _selected.first;
                  final name = await _ask(
                    l10n.libraryRename,
                    initial: uri.pathSegments.where((s) => s.isNotEmpty).last,
                  );
                  if (name != null && name.isNotEmpty) {
                    await _run((ops) => ops.rename(uri, name));
                  }
                },
              )
            else
              IconButton(
                tooltip: l10n.libraryBatchRenameTitle,
                icon: const Icon(Icons.edit_note),
                onPressed: _batchRename,
              ),
            IconButton(
              tooltip: l10n.libraryDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ] else ...[
            IconButton(
              tooltip: _grid ? l10n.libraryListView : l10n.libraryGridView,
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
              onPressed: () => setState(() => _grid = !_grid),
            ),
            PopupMenuButton<BrowserSort>(
              tooltip: l10n.librarySort,
              icon: const Icon(Icons.sort),
              onSelected: (s) => setState(() {
                _descending = s == _sort && !_descending;
                _sort = s;
                _entries = _entries == null ? null : _sorted(_entries!);
              }),
              itemBuilder: (_) => [
                for (final s in BrowserSort.values)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == _sort,
                    child: Text(l10n.librarySortBy(s.name)),
                  ),
              ],
            ),
            if (_mutable)
              IconButton(
                tooltip: l10n.libraryNewFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: () async {
                  final name = await _ask(l10n.libraryNewFolder);
                  if (name != null && name.isNotEmpty) {
                    await _run((ops) => ops.newFolder(_dir, name));
                  }
                },
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: KTarget.min,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.s8),
              children: [
                for (var i = 0; i < _stack.length; i++) ...[
                  if (i > 0) const Icon(Icons.chevron_right, size: 18),
                  TextButton(
                    onPressed: () {
                      setState(() => _stack = _stack.sublist(0, i + 1));
                      unawaited(_load());
                    },
                    child: Text(
                      i == 0
                          ? (widget.title ?? '/')
                          : Uri.decodeComponent(
                              _stack[i].pathSegments
                                  .where((s) => s.isNotEmpty)
                                  .last,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? EmptyState(
                    message: fileErrorMessage(l10n, _error!),
                    actions: [
                      FilledButton.tonal(
                        onPressed: _load,
                        child: Text(l10n.libraryTryAgain),
                      ),
                    ],
                  )
                : entries == null
                ? const SkeletonList()
                : entries.isEmpty
                ? EmptyState(message: l10n.libraryFolderEmpty)
                : _grid
                ? GridView.builder(
                    padding: const EdgeInsets.all(KSpacing.s8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          childAspectRatio: 0.9,
                        ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _GridCell(
                      entry: entries[i],
                      selected: _selected.contains(entries[i].uri),
                      onTap: () => _enter(entries[i]),
                      onLongPress: () => _toggle(entries[i]),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return ListTile(
                        minTileHeight: KTarget.min + KSpacing.s8,
                        selected: _selected.contains(e.uri),
                        leading: Icon(
                          e.isDirectory
                              ? Icons.folder_outlined
                              : kindIcon(MediaKinds.classify(e.name)),
                        ),
                        title: Text(
                          e.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: e.isDirectory || e.size == null
                            ? null
                            : Text(
                                formatBytes(
                                  e.size!,
                                  locale: Localizations.localeOf(context)
                                      .toLanguageTag(),
                                ),
                              ),
                        onTap: () => _enter(e),
                        onLongPress: () => _toggle(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final VirtualEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(KSpacing.s8),
        child: Column(
          children: [
            Expanded(
              child: Icon(
                entry.isDirectory
                    ? Icons.folder
                    : kindIcon(MediaKinds.classify(entry.name)),
                size: 48,
              ),
            ),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
