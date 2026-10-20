import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/library/widgets.dart'
    show openItemActionProvider;
import 'package:mediahro/features/photos/info/info_sheet.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/photo_page.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';
import 'package:mediahro_design/mediahro_design.dart';

abstract final class PhotoRoutes {
  /// Full-screen viewer, outside the shell; carries [PhotoViewerArgs].
  static const String view = '/photos/view';
}

/// What the viewer shows: the entries of the list it was opened from and the
/// one to start on.
final class PhotoViewerArgs {
  const PhotoViewerArgs(this.entries, this.index);

  final List<PhotoEntry> entries;
  final int index;
}

/// Opens the viewer on [entries] at [index] (IMG-004). Falls back to a plain
/// route when there is no router (tests, previews).
Future<void> openPhotoViewer(
  BuildContext context,
  List<PhotoEntry> entries,
  int index,
) async {
  final args = PhotoViewerArgs(entries, index);
  try {
    await GoRouter.of(context).push<void>(PhotoRoutes.view, extra: args);
  } on Object {
    if (!context.mounted) return;
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => PhotoViewer(args: args)));
  }
}

/// Full-screen routes of the photos lane; the orchestrator lists them in
/// `appRoutesProvider`.
final List<RouteBase> photoRoutes = [
  GoRoute(
    path: PhotoRoutes.view,
    builder: (context, state) => switch (state.extra) {
      final PhotoViewerArgs a => PhotoViewer(args: a),
      // A restored route has no entries: back to the timeline.
      _ => const _Gone(),
    },
  ),
];

class _Gone extends StatefulWidget {
  const _Gone();

  @override
  State<_Gone> createState() => _GoneState();
}

class _GoneState extends State<_Gone> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/photos');
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

class PhotoViewer extends ConsumerStatefulWidget {
  const PhotoViewer({required this.args, super.key});

  final PhotoViewerArgs args;

  @override
  ConsumerState<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.args.index,
  );
  final ViewerController _viewer = ViewerController();
  final ScrollController _strip = ScrollController();
  late final ThumbnailController _thumbs = ThumbnailController(
    ref.read(thumbnailSourceProvider(256)),
  );

  late int _index = widget.args.index;
  bool _chrome = true;
  bool _atFit = true;
  FitMode _mode = FitMode.fit;
  int _turns = 0;
  int _percent = 0;
  Timer? _hide;
  bool _started = false;

  List<PhotoEntry> get _entries => widget.args.entries;
  PhotoEntry get _entry => _entries[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _pages.dispose();
    _strip.dispose();
    _viewer.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!KPlayerChrome.shouldAutoHide(context)) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  void _goTo(int i) {
    if (i < 0 || i >= _entries.length) return;
    _pages.animateToPage(
      i,
      duration: KMotion.resolve(
        KMotion.base,
        reduceMotion: KAccessibility.reduceMotion(context),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPage(int i) {
    setState(() {
      _index = i;
      _atFit = true;
      _turns = 0;
      _percent = 0;
    });
    _centreStrip(i);
    _scheduleHide();
  }

  void _centreStrip(int i) {
    if (!_strip.hasClients) return;
    final target =
        i * _stripItem - (_strip.position.viewportDimension - _stripItem) / 2;
    _strip.animateTo(
      target.clamp(0.0, _strip.position.maxScrollExtent),
      duration: KMotion.base,
      curve: Curves.easeOut,
    );
  }

  static const double _stripItem = 60;

  void _info() {
    final l10n = AppLocalizations.of(context);
    unawaited(
      KSheet.show<void>(
        context,
        title: l10n.photosInfoTitle,
        builder: (_) => PhotoInfoSheet(entry: _entry),
      ),
    );
  }

  void _play() {
    // Videos open in the player; the viewer only pages through photos.
    final db = ref.read(libraryDatabaseProvider);
    final open = ref.read(openItemActionProvider);
    if (open == null) return;
    unawaited(
      (db.select(
        db.items,
      )..where((i) => i.id.equals(_entry.id))).getSingleOrNull().then((row) {
        if (row != null && mounted) open(context, row);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final reduce = KAccessibility.reduceMotion(context);
    final scrim = Colors.black.withValues(alpha: 0.55);
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            VoidCallbackIntent(() => _goTo(_index + 1)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): VoidCallbackIntent(
          () => _goTo(_index - 1),
        ),
        const SingleActivator(LogicalKeyboardKey.equal): VoidCallbackIntent(
          _viewer.zoomIn,
        ),
        const SingleActivator(LogicalKeyboardKey.add): VoidCallbackIntent(
          _viewer.zoomIn,
        ),
        const SingleActivator(LogicalKeyboardKey.minus): VoidCallbackIntent(
          _viewer.zoomOut,
        ),
        const SingleActivator(LogicalKeyboardKey.digit0): VoidCallbackIntent(
          _viewer.reset,
        ),
        const SingleActivator(LogicalKeyboardKey.digit1): VoidCallbackIntent(
          _viewer.oneToOne,
        ),
        const SingleActivator(LogicalKeyboardKey.keyI): VoidCallbackIntent(
          _info,
        ),
        const SingleActivator(LogicalKeyboardKey.keyF): VoidCallbackIntent(
          () => setState(
            () => _mode = _mode == FitMode.fit ? FitMode.fill : FitMode.fit,
          ),
        ),
        const SingleActivator(LogicalKeyboardKey.keyR): VoidCallbackIntent(
          () => setState(() => _turns = (_turns + 1) % 4),
        ),
        const SingleActivator(LogicalKeyboardKey.escape): VoidCallbackIntent(
          () => Navigator.of(context).maybePop(),
        ),
      },
      child: Actions(
        actions: {VoidCallbackIntent: VoidCallbackAction()},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Semantics(
              label: l10n.photosPosition(_index + 1, _entries.length),
              container: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pages,
                    physics: _atFit
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    allowImplicitScrolling: true,
                    itemCount: _entries.length,
                    onPageChanged: _onPage,
                    itemBuilder: (context, i) => PhotoPage(
                      key: ValueKey(_entries[i].id),
                      entry: _entries[i],
                      index: i,
                      thumbs: _thumbs,
                      active: i == _index,
                      mode: _mode,
                      quarterTurns: i == _index ? _turns : 0,
                      controller: _viewer,
                      onAtFitChanged: (v) {
                        if (v != _atFit) setState(() => _atFit = v);
                      },
                      onZoomChanged: (z, p) {
                        if (p != _percent) setState(() => _percent = p);
                      },
                      onTap: _toggleChrome,
                      onPlayVideo: _play,
                    ),
                  ),
                  // Top bar.
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: _Fade(
                      visible: _chrome,
                      reduceMotion: reduce,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [scrim, Colors.transparent],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              KIconButton(
                                icon: KIcon.back,
                                label: l10n.photosBack,
                                color: Colors.white,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _entry.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    Text(
                                      DateFormat.yMMMEd(locale)
                                          .add_jm()
                                          .format(_entry.date),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                              KIconButton(
                                icon: KIcon.info,
                                label: l10n.photosInfo,
                                color: Colors.white,
                                onPressed: _info,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom: readout, tools, filmstrip.
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    child: _Fade(
                      visible: _chrome,
                      reduceMotion: reduce,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [scrim, Colors.transparent],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!_atFit && _percent > 0)
                                    Semantics(
                                      liveRegion: true,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: KSpacing.s8,
                                        ),
                                        child: Text(
                                          l10n.photosZoomPercent(_percent),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: _mode == FitMode.fit
                                        ? l10n.photosFill
                                        : l10n.photosFit,
                                    color: Colors.white,
                                    icon: Icon(
                                      _mode == FitMode.fit
                                          ? Icons.fit_screen_outlined
                                          : Icons.crop_free,
                                    ),
                                    onPressed: () => setState(
                                      () => _mode = _mode == FitMode.fit
                                          ? FitMode.fill
                                          : FitMode.fit,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.photosRotate,
                                    color: Colors.white,
                                    icon: const Icon(
                                      Icons.rotate_90_degrees_cw_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () => _turns = (_turns + 1) % 4,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: 64,
                                child: Semantics(
                                  label: l10n.photosFilmstrip,
                                  container: true,
                                  child: ListView.builder(
                                    controller: _strip,
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _entries.length,
                                    itemExtent: _stripItem,
                                    itemBuilder: (context, i) => _StripItem(
                                      entry: _entries[i],
                                      index: i,
                                      selected: i == _index,
                                      thumbs: _thumbs,
                                      label: l10n.photosFilmstripItem(i + 1),
                                      onTap: () => _goTo(i),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({
    required this.visible,
    required this.reduceMotion,
    required this.child,
  });

  final bool visible;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: reduceMotion ? Duration.zero : KMotion.base,
      child: child,
    ),
  );
}

class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.entry,
    required this.index,
    required this.selected,
    required this.thumbs,
    required this.label,
    required this.onTap,
  });

  final PhotoEntry entry;
  final int index;
  final bool selected;
  final ThumbnailController thumbs;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    selected: selected,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: PhotoThumbnail(entry: entry, index: index, controller: thumbs),
        ),
      ),
    ),
  );
}
