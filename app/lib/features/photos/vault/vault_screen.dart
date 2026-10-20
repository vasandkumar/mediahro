import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_keys.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/features/photos/vault/vault_store.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Decoded pictures of vault items, kept in memory only: the vault never
/// writes a readable thumbnail to disk.
final class VaultPictures {
  VaultPictures(this.pipeline, this.store);

  final MediahroImagePipeline pipeline;
  final VaultStore store;
  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();
  final Map<String, Future<ui.Image?>> _pending = {};
  bool _closed = false;

  /// [item] decoded to at most [edge] pixels on its long side.
  Future<ui.Image?> picture(VaultItem item, int edge) async {
    final key = '${item.id}@$edge';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final pending = _pending[key] ??= _load(item, edge, key);
    try {
      return await pending;
    } finally {
      await _pending.remove(key);
    }
  }

  Future<ui.Image?> _load(VaultItem item, int edge, String key) async {
    if (item.kind != 'image') return null;
    VaultFile? file;
    try {
      file = await store.openFile(item.id);
      final src = ImageSource(file);
      final info = await pipeline.info(src);
      final longest = math.max(info.width, info.height);
      final scale = longest <= edge ? 1.0 : edge / longest;
      final img = await uiImageFrom(await pipeline.decode(src, scale: scale));
      if (_closed) {
        img.dispose();
        return null;
      }
      _cache[key] = img;
      while (_cache.length > 80) {
        _cache.remove(_cache.keys.first)?.dispose();
      }
      return img;
    } on Object {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// Drops every picture (the vault was locked).
  void close() {
    _closed = true;
    for (final i in _cache.values) {
      i.dispose();
    }
    _cache.clear();
  }
}

String _mimeOf(VaultItem i) => switch (i.ext) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  'gif' => 'image/gif',
  'heic' || 'heif' => 'image/heic',
  'avif' => 'image/avif',
  'jxl' => 'image/jxl',
  'mp4' => 'video/mp4',
  'mkv' => 'video/x-matroska',
  'mov' => 'video/quicktime',
  _ => 'application/octet-stream',
};

/// The vault (IMG-011, PRIV-007): locked behind the device's biometric or
/// screen lock, closes when the app leaves the screen.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  VaultPictures? _pictures;
  VaultStore? _picturesFor;
  final Set<String> _chosen = {};
  String? _message;
  bool _busy = false;
  late final VaultSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(vaultSessionProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pictures?.close();
    // Leaving the screen locks the vault.
    _session.lock();
    super.dispose();
  }

  void _lock() {
    _pictures?.close();
    _pictures = null;
    _picturesFor = null;
    _chosen.clear();
    _session.lock();
    if (mounted) setState(() => _message = null);
  }

  VaultPictures _picturesOf(VaultStore store) {
    if (_picturesFor != store) {
      _pictures?.close();
      _pictures = VaultPictures(ref.read(imagePipelineProvider), store);
      _picturesFor = store;
    }
    return _pictures!;
  }

  String _text(AppLocalizations l10n, VaultUnlock r) => switch (r) {
    VaultUnlock.opened || VaultUnlock.needsSetup => '',
    VaultUnlock.cancelled => l10n.photosVaultCancelled,
    VaultUnlock.unavailable => l10n.photosVaultUnavailable,
    VaultUnlock.failed => l10n.photosVaultFailed,
    VaultUnlock.wrongPin => l10n.photosVaultWrongPin,
  };

  Future<void> _unlock(VaultKeys keys) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final r = keys.exists
          ? await _session.unlock(l10n.photosVaultUnlockReason)
          : await _session.setUp();
      if (mounted) setState(() => _message = _text(l10n, r));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pin() async {
    final l10n = AppLocalizations.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(),
    );
    if (pin == null || pin.isEmpty) return;
    final r = await _session.unlockWithPin(pin);
    if (mounted) setState(() => _message = _text(l10n, r));
  }

  Future<void> _add(VaultStore store) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final storage = ref.read(storageProvider);
    final picked = await storage.pickFiles(
      kinds: {PickKind.image},
      multiple: true,
    );
    var added = 0;
    for (final f in picked) {
      try {
        final bytes = await readPickedFile(storage, f.uri);
        await store.add(
          name: f.name,
          kind: 'image',
          content: Stream.value(bytes),
          size: bytes.length,
        );
        added++;
      } on Object {
        // Left out; the count says how many went in.
      }
    }
    if (mounted) setState(() {});
    if (added > 0) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosVaultAdded(added))),
      );
    }
  }

  Future<void> _takeOut(VaultStore store, List<VaultItem> items) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final storage = ref.read(storageProvider);
    var n = 0;
    for (final i in items) {
      final uri = await storage.saveFile(
        suggestedName: i.name,
        mimeType: _mimeOf(i),
        content: vaultContent(store, i),
      );
      if (uri == null) continue;
      await store.remove(i.id);
      n++;
    }
    if (!mounted) return;
    setState(_chosen.clear);
    if (n > 0) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.photosVaultTakenOut(n))),
      );
    }
  }

  Future<void> _delete(VaultStore store, List<VaultItem> items) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.photosVaultDeleteConfirm(items.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosVaultDeleteForever),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final i in items) {
      await store.remove(i.id);
    }
    if (mounted) setState(_chosen.clear);
  }

  Future<void> _decoy(VaultKeys keys) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (keys.decoyExists) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.photosVaultDecoy),
          content: Text(l10n.photosVaultDecoyRemoveConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.photosCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.photosVaultDecoyRemove),
            ),
          ],
        ),
      );
      if (ok == true) await keys.removeDecoy();
      if (mounted) setState(() {});
      return;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _DecoyDialog(),
    );
    if (pin == null) return;
    await keys.createDecoy(pin);
    if (mounted) setState(() {});
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosVaultDecoyReady)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(vaultSessionProvider);
    final keysAsync = ref.watch(vaultKeysProvider);
    final store = state.store;
    if (store == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.photosVault)),
        body: keysAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => KEmptyState(message: l10n.photosVaultNotSupported),
          data: (keys) => _locked(context, keys),
        ),
      );
    }
    final items = store.list();
    final chosen = [
      for (final i in items)
        if (_chosen.contains(i.id)) i,
    ];
    final keys = keysAsync.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _chosen.isEmpty
              ? l10n.photosVault
              : l10n.photosSelectedCount(_chosen.length),
        ),
        actions: [
          if (_chosen.isNotEmpty) ...[
            IconButton(
              tooltip: l10n.photosVaultTakeOut,
              icon: const Icon(Icons.output),
              onPressed: () => unawaited(_takeOut(store, chosen)),
            ),
            IconButton(
              tooltip: l10n.photosVaultDeleteForever,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () => unawaited(_delete(store, chosen)),
            ),
          ] else ...[
            IconButton(
              tooltip: l10n.photosVaultAdd,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => unawaited(_add(store)),
            ),
            IconButton(
              tooltip: l10n.photosVaultLock,
              icon: const Icon(Icons.lock_outline),
              onPressed: _lock,
            ),
            if (!state.decoy && keys != null)
              PopupMenuButton<String>(
                tooltip: l10n.photosMore,
                onSelected: (_) => unawaited(_decoy(keys)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'decoy',
                    child: Text(
                      keys.decoyExists
                          ? l10n.photosVaultDecoyRemove
                          : l10n.photosVaultDecoy,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
      body: items.isEmpty
          ? KEmptyState(
              title: l10n.photosVaultEmptyTitle,
              message: l10n.photosVaultEmptyMessage,
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final selected = _chosen.contains(item.id);
                void toggle() => setState(
                  () =>
                      selected ? _chosen.remove(item.id) : _chosen.add(item.id),
                );
                return _VaultTile(
                  item: item,
                  pictures: _picturesOf(store),
                  selected: selected,
                  onTap: () {
                    if (_chosen.isNotEmpty) {
                      toggle();
                    } else if (item.kind == 'image') {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => VaultViewerScreen(
                            pictures: _picturesOf(store),
                            items: [
                              for (final x in items)
                                if (x.kind == 'image') x,
                            ],
                            index: items
                                .where((x) => x.kind == 'image')
                                .toList()
                                .indexOf(item),
                          ),
                        ),
                      );
                    }
                  },
                  onLongPress: toggle,
                );
              },
            ),
    );
  }

  Widget _locked(BuildContext context, VaultKeys keys) {
    final l10n = AppLocalizations.of(context);
    final needsSetup = !keys.exists;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                l10n.photosVaultIntro,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (needsSetup) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.photosVaultSetUpNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.fingerprint),
                onPressed: _busy ? null : () => unawaited(_unlock(keys)),
                label: Text(
                  needsSetup ? l10n.photosVaultSetUp : l10n.photosVaultUnlock,
                ),
              ),
              if (keys.decoyExists)
                TextButton(
                  onPressed: _busy ? null : () => unawaited(_pin()),
                  child: Text(l10n.photosVaultUsePin),
                ),
              if (_message != null && _message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultTile extends StatelessWidget {
  const _VaultTile({
    required this.item,
    required this.pictures,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final VaultItem item;
  final VaultPictures pictures;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: item.name,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHighest),
            if (item.kind == 'image')
              FutureBuilder<ui.Image?>(
                future: pictures.picture(item, 256),
                builder: (context, snap) {
                  final img = snap.data;
                  if (img == null) {
                    return snap.connectionState == ConnectionState.done
                        ? const Icon(Icons.broken_image_outlined)
                        : const SizedBox.shrink();
                  }
                  return RawImage(image: img, fit: BoxFit.cover);
                },
              )
            else
              Icon(
                item.kind == 'video' ? Icons.movie_outlined : Icons.audiotrack,
              ),
            if (selected)
              ColoredBox(
                color: scheme.primary.withValues(alpha: 0.35),
                child: const Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check_circle, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Swipe through the vault's photos; pinch to zoom. No share, no edit, no
/// file on disk.
class VaultViewerScreen extends StatefulWidget {
  const VaultViewerScreen({
    required this.pictures,
    required this.items,
    required this.index,
    super.key,
  });

  final VaultPictures pictures;
  final List<VaultItem> items;
  final int index;

  @override
  State<VaultViewerScreen> createState() => _VaultViewerScreenState();
}

class _VaultViewerScreenState extends State<VaultViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _at = widget.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final item = widget.items[_at];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.name, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (context, i) => FutureBuilder<ui.Image?>(
              future: widget.pictures.picture(widget.items[i], 3072),
              builder: (context, snap) {
                final img = snap.data;
                if (img == null) {
                  return Center(
                    child: snap.connectionState == ConnectionState.done
                        ? Semantics(
                            label: l10n.photosVaultOpenFailed,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                            ),
                          )
                        : const CircularProgressIndicator(),
                  );
                }
                return InteractiveViewer(
                  maxScale: 8,
                  child: RawImage(image: img, fit: BoxFit.contain),
                );
              },
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(8),
                child: Text(
                  [
                    DateFormat.yMMMd(locale).format(item.date),
                    formatBytes(item.size, locale: locale),
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks, then moves [photos] into the vault (IMG-011): unlocks it first,
/// sets it up if there is none. Returns true when something moved.
Future<bool> moveToVaultFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context);
  final images = photos.where((p) => !p.isVideo).toList();
  if (images.isEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosVaultNoVideos)));
    return false;
  }
  final VaultKeys keys;
  try {
    keys = await container.read(vaultKeysProvider.future);
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosVaultNotSupported)),
    );
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.photosVaultMoveTitle(images.length)),
      content: Text(l10n.photosVaultMoveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.photosVaultMoveConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final session = container.read(vaultSessionProvider.notifier);
  var store = container.read(vaultSessionProvider).store;
  if (store == null || container.read(vaultSessionProvider).decoy) {
    final r = keys.exists
        ? await session.unlock(l10n.photosVaultUnlockReason)
        : await session.setUp();
    store = container.read(vaultSessionProvider).store;
    if (r != VaultUnlock.opened || store == null) {
      final text = switch (r) {
        VaultUnlock.unavailable => l10n.photosVaultUnavailable,
        VaultUnlock.failed => l10n.photosVaultFailed,
        _ => l10n.photosVaultCancelled,
      };
      messenger?.showSnackBar(SnackBar(content: Text(text)));
      return false;
    }
  }
  final report = await container.read(vaultMoverProvider).moveIn(store, images);
  // The vault is closed again once the photos are in.
  session.lock();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        [
          if (report.moved > 0) l10n.photosVaultMoved(report.moved),
          if (report.failed.isNotEmpty)
            l10n.photosVaultMoveFailed(report.failed.length),
        ].join(' '),
      ),
    ),
  );
  return report.moved > 0;
}

/// Asks for the decoy vault's PIN.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosVaultPinTitle),
      content: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pin.text),
          child: Text(l10n.photosVaultUnlock),
        ),
      ],
    );
  }
}

/// Sets the decoy vault's PIN (twice).
class _DecoyDialog extends StatefulWidget {
  const _DecoyDialog();

  @override
  State<_DecoyDialog> createState() => _DecoyDialogState();
}

class _DecoyDialogState extends State<_DecoyDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _create(AppLocalizations l10n) {
    if (!RegExp(r'^\d{4,12}$').hasMatch(_a.text)) {
      setState(() => _error = l10n.photosVaultDecoyShort);
    } else if (_a.text != _b.text) {
      setState(() => _error = l10n.photosVaultDecoyMismatch);
    } else {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosVaultDecoy),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.photosVaultDecoyBody),
          const SizedBox(height: 12),
          TextField(
            controller: _a,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.photosVaultDecoyPin),
          ),
          TextField(
            controller: _b,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.photosVaultDecoyPinRepeat,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => _create(l10n),
          child: Text(l10n.photosVaultDecoyCreate),
        ),
      ],
    );
  }
}
