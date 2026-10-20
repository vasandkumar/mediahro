import 'dart:async';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Opens the compare screen on 2–4 photos (IMG-008).
Future<void> openCompare(BuildContext context, List<PhotoEntry> photos) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CompareScreen(photos: photos)),
    );

enum _Verdict { undecided, keep, reject }

/// Two to four photos side by side with shared pan and zoom, or two of them
/// as a swipe, an overlay or a difference; a keep / reject bar writes the
/// decision to the library as it is made, so leaving never loses it.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({required this.photos, super.key})
    : assert(photos.length >= 2 && photos.length <= 4, '2–4 photos');

  final List<PhotoEntry> photos;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final TransformationController _zoom = TransformationController();
  late final List<ViewerImage?> _images = List.filled(
    widget.photos.length,
    null,
  );
  late final Set<int> _failed = {};
  late final Map<int, _Verdict> _verdicts = {
    for (final p in widget.photos)
      p.id: p.rejected
          ? _Verdict.reject
          : p.favourite
          ? _Verdict.keep
          : _Verdict.undecided,
  };
  KCompareMode _mode = KCompareMode.sideBySide;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final load = ref.read(viewerImageLoaderProvider);
    for (var i = 0; i < widget.photos.length; i++) {
      unawaited(_load(load, i));
    }
  }

  Future<void> _load(ViewerImageLoader load, int i) async {
    try {
      final img = await load(widget.photos[i]);
      if (_disposed) {
        img.dispose();
        return;
      }
      setState(() => _images[i] = img);
    } on Object {
      if (!_disposed) setState(() => _failed.add(widget.photos[i].id));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _images) {
      i?.dispose();
    }
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _decide(PhotoEntry p, _Verdict v) async {
    final org = ref.read(photoOrganiserProvider);
    final write = ref.read(organisationWriteBackProvider);
    final previous = _verdicts[p.id];
    final next = previous == v ? _Verdict.undecided : v;
    setState(() => _verdicts[p.id] = next);
    switch (next) {
      case _Verdict.keep:
        final back = await org.keep([p.id]);
        if (previous == _Verdict.reject) {
          unawaited(write.unreject([p], back));
        }
      case _Verdict.reject:
        await org.setRejected([p.id], value: true);
        unawaited(write.rating([p], -1));
      case _Verdict.undecided:
        if (previous == _Verdict.keep) {
          await org.setFavourite([p.id], value: false);
        } else {
          final back = await org.setRejected([p.id], value: false);
          unawaited(write.unreject([p], back));
        }
    }
  }

  Future<void> _keepOnly(PhotoEntry keeper) async {
    final others = [
      for (final p in widget.photos)
        if (p.id != keeper.id) p,
    ];
    final wasRejected = _verdicts[keeper.id] == _Verdict.reject;
    setState(() {
      _verdicts[keeper.id] = _Verdict.keep;
      for (final o in others) {
        _verdicts[o.id] = _Verdict.reject;
      }
    });
    final org = ref.read(photoOrganiserProvider);
    final write = ref.read(organisationWriteBackProvider);
    final back = await org.keep([keeper.id]);
    if (wasRejected) unawaited(write.unreject([keeper], back));
    await org.setRejected([for (final o in others) o.id], value: true);
    unawaited(write.rating(others, -1));
  }

  String _modeLabel(AppLocalizations l10n, KCompareMode m) => switch (m) {
    KCompareMode.sideBySide => l10n.photosCompareSideBySide,
    KCompareMode.swipe => l10n.photosCompareSwipe,
    KCompareMode.overlay => l10n.photosCompareOverlay,
    KCompareMode.difference => l10n.photosCompareDifference,
  };

  Widget _panel(int i) {
    final p = widget.photos[i];
    final img = _images[i];
    if (_failed.contains(p.id)) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          semanticLabel: AppLocalizations.of(context).photosCompareLoadFailed,
        ),
      );
    }
    if (img == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RawImage(image: img.base, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final n = widget.photos.length;
    // Swipe, overlay and difference are about two photos.
    final modes = n == 2
        ? KCompareMode.values
        : const [KCompareMode.sideBySide];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.photosCompare),
        actions: [
          IconButton(
            tooltip: l10n.photosCompareResetZoom,
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: () => _zoom.value = Matrix4.identity(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (modes.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final m in modes)
                    ChoiceChip(
                      label: Text(_modeLabel(l10n, m)),
                      selected: _mode == m,
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                ],
              ),
            ),
          Expanded(
            child: KCompareView(
              key: ValueKey(_mode),
              mode: _mode,
              controller: _zoom,
              children: [for (var i = 0; i < n; i++) _panel(i)],
            ),
          ),
          _DecisionBar(
            photos: widget.photos,
            verdicts: _verdicts,
            onKeep: (p) => unawaited(_decide(p, _Verdict.keep)),
            onReject: (p) => unawaited(_decide(p, _Verdict.reject)),
            onKeepOnly: (p) => unawaited(_keepOnly(p)),
          ),
        ],
      ),
    );
  }
}

/// One card per photo: its number and name, keep, reject, keep only this.
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({
    required this.photos,
    required this.verdicts,
    required this.onKeep,
    required this.onReject,
    required this.onKeepOnly,
  });

  final List<PhotoEntry> photos;
  final Map<int, _Verdict> verdicts;
  final void Function(PhotoEntry) onKeep;
  final void Function(PhotoEntry) onReject;
  final void Function(PhotoEntry) onKeepOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = photos[i];
              final v = verdicts[p.id] ?? _Verdict.undecided;
              return Container(
                width: 190,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: switch (v) {
                      _Verdict.keep => Colors.green,
                      _Verdict.reject => scheme.error,
                      _Verdict.undecided => scheme.outlineVariant,
                    },
                    width: v == _Verdict.undecided ? 1 : 2,
                  ),
                  borderRadius: BorderRadius.circular(KRadius.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.photosCompareItem(i + 1, p.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: l10n.photosCompareKeep(p.name),
                          isSelected: v == _Verdict.keep,
                          color: Colors.green,
                          icon: const Icon(Icons.check_circle_outline),
                          selectedIcon: const Icon(Icons.check_circle),
                          onPressed: () => onKeep(p),
                        ),
                        IconButton(
                          tooltip: l10n.photosCompareReject(p.name),
                          isSelected: v == _Verdict.reject,
                          color: scheme.error,
                          icon: const Icon(Icons.block_outlined),
                          selectedIcon: const Icon(Icons.block),
                          onPressed: () => onReject(p),
                        ),
                        IconButton(
                          tooltip: l10n.photosCompareKeepOnly(p.name),
                          icon: const Icon(Icons.filter_1_outlined),
                          onPressed: () => onKeepOnly(p),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
