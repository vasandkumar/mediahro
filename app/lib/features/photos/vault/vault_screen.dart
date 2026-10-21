import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_gate.dart';
import 'package:mediahro/features/photos/vault/vault_import.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_player.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/images/pipeline/mediahro_image_pipeline.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The route name of the vault screen.
const String vaultRouteName = 'photos-vault';

/// Opens the vault screen.
Future<void> openVault(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: vaultRouteName),
        builder: (_) => const VaultScreen(),
      ),
    );

/// Pictures of vault items, decoded into memory only: the stored picture of
/// an item (sealed, small) for the grid, the file itself for the viewer. No
/// plaintext picture is written to disk.
final class VaultPictures {
  VaultPictures(this.pipeline, this.container);

  final MediahroImagePipeline pipeline;
  final VaultContainer container;
  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();
  final Map<String, Future<ui.Image?>> _pending = {};
  bool _closed = false;

  /// The picture of [item] for the grid (about 256 px). The caller owns the
  /// returned image and disposes it: it is a clone, so locking the vault (the
  /// cache is emptied) never pulls a picture from under a widget that is
  /// still drawing it.
  Future<ui.Image?> grid(VaultItem item) => _get(item, 256);

  /// The picture of [item] for the viewer, at most [edge] px (a clone, see
  /// [grid]).
  Future<ui.Image?> full(VaultItem item, int edge) => _get(item, edge);

  Future<ui.Image?> _get(VaultItem item, int edge) async {
    if (_closed || item.kind != 'image') return null;
    final key = '${item.id}@$edge';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit.clone();
    }
    final pending = _pending[key] ??= _load(item, edge, key);
    try {
      final img = await pending;
      return _closed ? null : img?.clone();
    } finally {
      await _pending.remove(key);
    }
  }

  Future<ui.Image?> _load(VaultItem item, int edge, String key) async {
    ui.Image? img;
    try {
      if (edge <= 384) img = await _fromStored(item, edge);
      img ??= await _decode(item, edge);
    } on Object {
      return null;
    }
    if (img == null) return null;
    if (_closed) {
      img.dispose();
      return null;
    }
    _cache[key] = img;
    while (_cache.length > 120) {
      _cache.remove(_cache.keys.first)?.dispose();
    }
    return img;
  }

  Future<ui.Image?> _fromStored(VaultItem item, int edge) async {
    final bytes = await container.thumbnail(item.id);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: edge);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<ui.Image?> _decode(VaultItem item, int edge) async {
    final file = await container.openFile(item.id);
    try {
      final src = ImageSource(file);
      final info = await pipeline.info(src);
      final longest = math.max(info.width, info.height);
      final scale = longest <= edge ? 1.0 : edge / longest;
      return await uiImageFrom(await pipeline.decode(src, scale: scale));
    } finally {
      await file.close();
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
  'webm' => 'video/webm',
  'avi' => 'video/x-msvideo',
  'm4v' => 'video/x-m4v',
  '3gp' => 'video/3gpp',
  'mp3' => 'audio/mpeg',
  'm4a' || 'm4b' => 'audio/mp4',
  'aac' => 'audio/aac',
  'flac' => 'audio/flac',
  'wav' => 'audio/wav',
  'ogg' || 'oga' => 'audio/ogg',
  'opus' => 'audio/opus',
  _ => 'application/octet-stream',
};

/// The vault (IMG-011, PRIV-007): a PIN pad before, the photos after. It
/// locks when the app leaves the screen and pops every vault screen when it
/// locks, and it keeps itself out of screenshots and the app switcher.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  late final VaultSession _session;
  late final SecureWindowScope _secure;
  ModalRoute<Object?>? _route;
  VaultPictures? _pictures;
  OpenVault? _picturesFor;
  final Set<String> _chosen = {};

  @override
  void initState() {
    super.initState();
    _session = ref.read(vaultSessionProvider.notifier);
    _secure = ref.read(secureWindowScopeProvider)..enter();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _session.lock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pictures?.close();
    // Leaving the screen locks the vault.
    _session.lockSoon();
    _secure.leave();
    super.dispose();
  }

  /// The vault locked: forget what was decoded and close everything that
  /// was opened over this screen, the viewer and dialogs included.
  void _locked() {
    final dropped = _pictures;
    _pictures = null;
    _picturesFor = null;
    _chosen.clear();
    final route = _route;
    if (mounted && route != null && route.isActive) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    // After the screens above have gone. What widgets still draw this frame
    // are clones; the cache is dropped once the frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) => dropped?.close());
  }

  VaultPictures _picturesOf(OpenVault v) {
    if (!identical(_picturesFor, v)) {
      _pictures?.close();
      _pictures = VaultPictures(ref.read(imagePipelineProvider), v.container);
      _picturesFor = v;
    }
    return _pictures!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<VaultState>(vaultSessionProvider, (prev, next) {
      if ((prev?.isOpen ?? false) && !next.isOpen) _locked();
    });
    final state = ref.watch(vaultSessionProvider);
    if (!state.isOpen) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.photosVault)),
        body: const VaultGate(),
      );
    }
    return _OpenVaultView(
      vault: state.vault!,
      pictures: _picturesOf(state.vault!),
      chosen: _chosen,
    );
  }
}

class _OpenVaultView extends ConsumerStatefulWidget {
  const _OpenVaultView({
    required this.vault,
    required this.pictures,
    required this.chosen,
  });

  final OpenVault vault;
  final VaultPictures pictures;
  final Set<String> chosen;

  @override
  ConsumerState<_OpenVaultView> createState() => _OpenVaultViewState();
}

class _OpenVaultViewState extends ConsumerState<_OpenVaultView> {
  VaultContainer get _c => widget.vault.container;
  Set<String> get _chosen => widget.chosen;
  bool _fingerprintOn = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readFingerprint());
  }

  Future<void> _readFingerprint() async {
    final m = await ref.read(vaultManagerProvider.future);
    final on = await m.fingerprintOn;
    if (mounted) setState(() => _fingerprintOn = on);
  }

  bool get _live => mounted && !_c.isClosed;

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photosVaultAdd),
        content: Text(l10n.photosVaultAddNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosVaultAddContinue),
          ),
        ],
      ),
    );
    if (go != true || !_live) return;
    final storage = ref.read(storageProvider);
    final picked = await storage.pickFiles(
      kinds: {PickKind.image, PickKind.video, PickKind.audio},
      multiple: true,
    );
    var added = 0;
    var skipped = 0;
    for (final f in picked) {
      if (!_live) return;
      try {
        final kind = vaultKindOf(f.name);
        if (kind == null) {
          skipped++;
          continue;
        }
        // In pieces: a film does not have to fit in memory.
        final source = await openPickedStream(storage, f.uri);
        if (!_live) return;
        await _c.add(
          name: f.name,
          kind: kind.name,
          content: source.content,
          size: source.size,
        );
        added++;
      } on VaultLocked {
        // Locked while adding.
        return;
      } on Object {
        skipped++;
      }
    }
    if (!_live) return;
    setState(() {});
    _toast(
      [
        if (added > 0) l10n.photosVaultAdded(added),
        if (skipped > 0) l10n.photosVaultSkipped(skipped),
      ].join(' '),
    );
  }

  Future<void> _takeOut(List<VaultItem> items) async {
    final l10n = AppLocalizations.of(context);
    final storage = ref.read(storageProvider);
    var n = 0;
    try {
      for (final i in items) {
        if (!_live) return;
        final uri = await storage.saveFile(
          suggestedName: i.name,
          mimeType: _mimeOf(i),
          content: restoredContent(_c, i),
        );
        if (uri == null) continue;
        if (!_live) return;
        await _c.remove(i.id);
        n++;
      }
    } on VaultLocked {
      return;
    }
    if (!_live) return;
    setState(_chosen.clear);
    if (n > 0) _toast(l10n.photosVaultTakenOut(n));
  }

  Future<void> _delete(List<VaultItem> items) async {
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
    try {
      for (final i in items) {
        if (!_live) return;
        await _c.remove(i.id);
      }
    } on VaultLocked {
      return;
    }
    if (_live) setState(_chosen.clear);
  }

  Future<void> _toggleFingerprint() async {
    final l10n = AppLocalizations.of(context);
    final want = !_fingerprintOn;
    if (want) {
      // The coercion warning comes before, not after.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.photosVaultMenuFingerprint),
          content: Text(l10n.photosVaultFingerprintWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.photosCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.photosVaultUseFingerprint),
            ),
          ],
        ),
      );
      if (ok != true || !_live) return;
    }
    final manager = await ref.read(vaultManagerProvider.future);
    final outcome = await manager.setFingerprint(widget.vault, enabled: want);
    if (!mounted) return;
    if (outcome == VaultOutcome.opened) {
      setState(() => _fingerprintOn = want);
      _toast(
        want ? l10n.photosVaultFingerprintOn : l10n.photosVaultFingerprintOff,
      );
    } else {
      _toast(vaultOutcomeText(l10n, VaultOpenResult(outcome)));
    }
  }

  Future<void> _changePin() async {
    final l10n = AppLocalizations.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _ChangePinDialog(),
    );
    if (pin == null || !_live) return;
    final manager = await ref.read(vaultManagerProvider.future);
    final VaultOutcome outcome;
    try {
      outcome = await manager.changePin(widget.vault, pin);
    } on Object {
      if (mounted) _toast(l10n.photosVaultUnavailable);
      return;
    }
    if (!mounted) return;
    if (outcome != VaultOutcome.opened) {
      final wait = outcome == VaultOutcome.waitToRetry
          ? await manager.waitLeft
          : null;
      if (!mounted) return;
      _toast(vaultOutcomeText(l10n, VaultOpenResult(outcome, wait: wait)));
      return;
    }
    _toast(l10n.photosVaultChangePinDone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _c.isClosed ? const <VaultItem>[] : _c.list();
    final chosen = [
      for (final i in items)
        if (_chosen.contains(i.id)) i,
    ];
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
              onPressed: () => unawaited(_takeOut(chosen)),
            ),
            IconButton(
              tooltip: l10n.photosVaultDeleteForever,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () => unawaited(_delete(chosen)),
            ),
          ] else ...[
            IconButton(
              tooltip: l10n.photosVaultAdd,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => unawaited(_add()),
            ),
            IconButton(
              tooltip: l10n.photosVaultLock,
              icon: const Icon(Icons.lock_outline),
              onPressed: ref.read(vaultSessionProvider.notifier).lock,
            ),
            PopupMenuButton<String>(
              tooltip: l10n.photosMore,
              onSelected: (v) {
                if (v == 'fingerprint') unawaited(_toggleFingerprint());
                if (v == 'pin') unawaited(_changePin());
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'fingerprint',
                  checked: _fingerprintOn,
                  child: Text(l10n.photosVaultMenuFingerprint),
                ),
                PopupMenuItem(
                  value: 'pin',
                  child: Text(l10n.photosVaultChangePin),
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
                  pictures: widget.pictures,
                  selected: selected,
                  onTap: () {
                    if (_chosen.isNotEmpty) {
                      toggle();
                    } else if (item.kind == 'video' || item.kind == 'audio') {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              VaultPlayerScreen(container: _c, item: item),
                        ),
                      );
                    } else if (item.kind == 'image') {
                      final images = [
                        for (final x in items)
                          if (x.kind == 'image') x,
                      ];
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => VaultViewerScreen(
                            pictures: widget.pictures,
                            items: images,
                            index: images.indexOf(item),
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
              _PictureHolder(
                key: ValueKey(item.id),
                load: () => pictures.grid(item),
                builder: (img) => RawImage(image: img, fit: BoxFit.cover),
                loading: (context) => const SizedBox.shrink(),
                failed: (context) => const Icon(Icons.broken_image_outlined),
              )
            else
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.kind == 'video'
                          ? Icons.movie_outlined
                          : Icons.audiotrack,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
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

/// A picture that this widget owns: it asks for a clone once, draws it, and
/// disposes it with itself (or at once if it arrives after the widget is
/// gone).
class _PictureHolder extends StatefulWidget {
  const _PictureHolder({
    required this.load,
    required this.builder,
    required this.loading,
    required this.failed,
    super.key,
  });

  final Future<ui.Image?> Function() load;
  final Widget Function(ui.Image image) builder;
  final WidgetBuilder loading;
  final WidgetBuilder failed;

  @override
  State<_PictureHolder> createState() => _PictureHolderState();
}

class _PictureHolderState extends State<_PictureHolder> {
  ui.Image? _image;
  bool _done = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    ui.Image? img;
    try {
      img = await widget.load();
    } on Object {
      img = null;
    }
    if (_gone) {
      img?.dispose();
      return;
    }
    setState(() {
      _image = img;
      _done = true;
    });
  }

  @override
  void dispose() {
    _gone = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img != null) return widget.builder(img);
    return _done ? widget.failed(context) : widget.loading(context);
  }
}

/// Asks for the vault's new PIN twice.
class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _go(AppLocalizations l10n) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(_a.text)) {
      setState(() => _error = l10n.photosVaultPinShort);
    } else if (_a.text != _b.text) {
      setState(() => _error = l10n.photosVaultPinMismatch);
    } else {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosVaultChangePin),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.photosVaultNewPin),
          ),
          TextField(
            controller: _b,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.photosVaultPinRepeat,
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
          onPressed: () => _go(l10n),
          child: Text(l10n.photosVaultChangePin),
        ),
      ],
    );
  }
}

/// Swipe through the vault's photos; pinch to zoom. No share, no edit, no
/// file on disk. Pops itself when the vault locks (the screen below does).
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
            itemBuilder: (context, i) => _PictureHolder(
              key: ValueKey(widget.items[i].id),
              load: () => widget.pictures.full(widget.items[i], 3072),
              builder: (img) => InteractiveViewer(
                maxScale: 8,
                child: RawImage(image: img, fit: BoxFit.contain),
              ),
              loading: (context) =>
                  const Center(child: CircularProgressIndicator()),
              failed: (context) => Center(
                child: Semantics(
                  label: l10n.photosVaultOpenFailed,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                  ),
                ),
              ),
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
