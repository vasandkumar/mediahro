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
import 'package:mediahro/features/photos/compare/compare_screen.dart';
import 'package:mediahro/features/photos/compare/compare_tray.dart';
import 'package:mediahro/features/photos/edit/editor_screen.dart';
import 'package:mediahro/features/photos/info/info_sheet.dart';
import 'package:mediahro/features/photos/output/output_actions.dart';
import 'package:mediahro/features/photos/pano/pano_screen.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/photo_thumbnail.dart';
import 'package:mediahro/features/photos/timeline/thumbnail_controller.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/viewer/hdr_surface.dart';
import 'package:mediahro/features/photos/viewer/photo_page.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/features/photos/viewer/zoom_math.dart';
import 'package:mediahro/platform/imaging.dart' show ImagingSupport;
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
  late final ThumbnailController _thumbs;

  late int _index = widget.args.index;
  bool _chrome = true;
  bool _atFit = true;
  FitMode _mode = FitMode.fit;
  int _turns = 0;
  int _percent = 0;
  bool _animated = false;
  bool _playing = true;
  Timer? _hide;
  bool _started = false;
  bool _hdrOn = true;
  bool _paging = false;

  // Page of a multi-page file (a TIFF) and how many there are (IMG-001).
  int _page = 0;
  int _pageCount = 1;

  // The Live or Motion Photo clip is playing (IMG-001).
  bool _clip = false;

  // A panorama opens filling the height, so it can be panned along; the Fit
  // button still brings the whole picture back.
  bool _panorama = false;

  // The photo is a 360° sphere that can be looked around in (IMG-001).
  bool _sphere = false;

  // What each loaded photo said about itself, so a photo that was kept alive
  // beside the current one shows its page bar again when swiped back to.
  final Map<int, ({int pages, bool wide, bool sphere})> _facts = {};

  /// The system's HDR picture replaces the tone-mapped one while the photo is
  /// at rest at fit size on an HDR display (IMG-002).
  FitMode get _shownMode =>
      _mode == FitMode.fit && _panorama ? FitMode.fill : _mode;

  void _toggleMode() => setState(() {
    final next = _shownMode == FitMode.fit ? FitMode.fill : FitMode.fit;
    _panorama = false;
    _mode = next;
  });

  bool get _hdrVisible =>
      _hdrOn &&
      _entry.hdr &&
      _atFit &&
      _shownMode == FitMode.fit &&
      _turns == 0 &&
      !_paging &&
      (ref.watch(hdrDisplayProvider).value ?? false);

  List<PhotoEntry> get _entries => widget.args.entries;
  PhotoEntry get _entry => _entries[_index];

  @override
  void initState() {
    super.initState();
    _thumbs = ThumbnailController(ref.read(thumbnailSourceProvider(256)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Animations start paused when the system asks for reduced motion.
    _playing = !KAccessibility.reduceMotion(context);
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
      _animated = false;
      _page = 0;
      _clip = false;
      _pageCount = _facts[_entries[i].id]?.pages ?? 1;
      _panorama = _facts[_entries[i].id]?.wide ?? false;
      _sphere = _facts[_entries[i].id]?.sphere ?? false;
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

  void _toggleCompare() {
    final l10n = AppLocalizations.of(context);
    final tray = ref.read(compareTrayProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = switch (tray.toggle(_entry)) {
      TrayChange.added => l10n.photosCompareAdded(
        ref.read(compareTrayProvider).length,
        CompareTray.capacity,
      ),
      TrayChange.removed => null,
      TrayChange.full => l10n.photosCompareFull,
      TrayChange.notAPhoto => l10n.photosCompareNotAPhoto,
    };
    if (text == null) return;
    final ready = ref.read(compareTrayProvider);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: ready.length >= 2
              ? SnackBarAction(
                  label: l10n.photosCompareOpen,
                  onPressed: () {
                    final photos = ref.read(compareTrayProvider);
                    tray.clear();
                    unawaited(openCompare(context, photos));
                  },
                )
              : null,
        ),
      );
  }

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
          _toggleMode,
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
                  NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.depth != 0) return false;
                      if (n is ScrollStartNotification && !_paging) {
                        setState(() => _paging = true);
                      } else if (n is ScrollEndNotification && _paging) {
                        setState(() => _paging = false);
                      }
                      return false;
                    },
                    child: PageView.builder(
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
                        mode: i == _index ? _shownMode : _mode,
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
                        animationPlaying: _playing && i == _index,
                        page: i == _index ? _page : 0,
                        clipPlaying: i == _index && _clip,
                        onClipDone: () {
                          if (mounted && _clip) setState(() => _clip = false);
                        },
                        onLoaded: (img) {
                          final wide =
                              img.info.isPanorama &&
                              img.fullSize.width >= 2.2 * img.fullSize.height;
                          final sphere =
                              img.info.panorama?.isEquirectangular ?? false;
                          _facts[_entries[i].id] = (
                            pages: img.info.pages,
                            wide: wide,
                            sphere: sphere,
                          );
                          if (i != _index) return;
                          if ((img.animation != null) != _animated ||
                              img.info.pages != _pageCount ||
                              wide != _panorama ||
                              sphere != _sphere) {
                            setState(() {
                              _animated = img.animation != null;
                              _pageCount = img.info.pages;
                              _panorama = wide;
                              _sphere = sphere;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (_hdrVisible)
                    // Touches go through to the pages: swipe, pinch and tap
                    // work as on any photo.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: HdrImageSurface(
                          key: ValueKey(_entry.id),
                          entry: _entry,
                        ),
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
                              IconButton(
                                tooltip: l10n.photosEditPhoto,
                                color: Colors.white,
                                icon: const Icon(Icons.tune),
                                onPressed: () =>
                                    unawaited(openEditor(context, _entry)),
                              ),
                              IconButton(
                                tooltip:
                                    ref
                                        .watch(compareTrayProvider)
                                        .any((e) => e.id == _entry.id)
                                    ? l10n.photosCompareRemove
                                    : l10n.photosCompareAdd,
                                color: Colors.white,
                                icon: const Icon(Icons.compare),
                                onPressed: _toggleCompare,
                              ),
                              _OutputMenu(entry: _entry),
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
                              // A wrap: the tools wrap onto a second line on a
                              // narrow phone instead of running off the edge.
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
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
                                  if (_animated)
                                    IconButton(
                                      tooltip: _playing
                                          ? l10n.photosPauseAnimation
                                          : l10n.photosPlayAnimation,
                                      color: Colors.white,
                                      icon: Icon(
                                        _playing
                                            ? Icons.pause_circle_outline
                                            : Icons.play_circle_outline,
                                      ),
                                      onPressed: () =>
                                          setState(() => _playing = !_playing),
                                    ),
                                  if (_entry.hdr &&
                                      (ref.watch(hdrDisplayProvider).value ??
                                          false))
                                    IconButton(
                                      tooltip: _hdrOn
                                          ? l10n.photosHdrOff
                                          : l10n.photosHdrOn,
                                      color: Colors.white,
                                      icon: Icon(
                                        _hdrOn ? Icons.hdr_on : Icons.hdr_off,
                                      ),
                                      onPressed: () =>
                                          setState(() => _hdrOn = !_hdrOn),
                                    ),
                                  if (_entry.livePhoto || _entry.motionPhoto)
                                    IconButton(
                                      tooltip: _clip
                                          ? l10n.photosStopClip
                                          : (_entry.livePhoto
                                                ? l10n.photosPlayLive
                                                : l10n.photosPlayMotion),
                                      color: Colors.white,
                                      icon: Icon(
                                        _clip
                                            ? Icons.stop_circle_outlined
                                            : Icons.motion_photos_on_outlined,
                                      ),
                                      onPressed: () =>
                                          setState(() => _clip = !_clip),
                                    ),
                                  if (_sphere)
                                    IconButton(
                                      tooltip: l10n.photosPanoLookAround,
                                      color: Colors.white,
                                      icon: const Icon(Icons.threesixty),
                                      onPressed: () => unawaited(
                                        openPanorama(context, _entry),
                                      ),
                                    ),
                                  if (_pageCount > 1) ...[
                                    IconButton(
                                      tooltip: l10n.photosPagePrevious,
                                      color: Colors.white,
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: _page > 0
                                          ? () => setState(() => _page--)
                                          : null,
                                    ),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        l10n.photosPageOf(
                                          _page + 1,
                                          _pageCount,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l10n.photosPageNext,
                                      color: Colors.white,
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed: _page < _pageCount - 1
                                          ? () => setState(() => _page++)
                                          : null,
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: _shownMode == FitMode.fit
                                        ? l10n.photosFill
                                        : l10n.photosFit,
                                    color: Colors.white,
                                    icon: Icon(
                                      _shownMode == FitMode.fit
                                          ? Icons.fit_screen_outlined
                                          : Icons.crop_free,
                                    ),
                                    onPressed: _toggleMode,
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

/// Share, wallpaper, print and copy for the photo in front of the user.
class _OutputMenu extends ConsumerWidget {
  const _OutputMenu({required this.entry});

  final PhotoEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final support =
        ref.watch(photoOutputSupportProvider).value ?? const ImagingSupport();
    final actions = outputActionsFor(support);
    return PopupMenuButton<OutputAction>(
      tooltip: l10n.photosMore,
      iconColor: Colors.white,
      onSelected: (a) => unawaited(runOutputAction(context, ref, a, [entry])),
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem(value: a, child: Text(outputActionLabel(l10n, a))),
      ],
    );
  }
}
