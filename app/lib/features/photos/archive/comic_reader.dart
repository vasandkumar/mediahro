import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro/features/photos/archive/archive_providers.dart';
import 'package:mediahro/features/photos/archive/reader_layout.dart';
import 'package:mediahro/features/photos/archive/reader_settings.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// File endings the reader opens as archives.
const Set<String> archiveExtensions = {
  'zip', 'cbz', 'rar', 'cbr', '7z', 'cb7', 'tar', 'tgz', //
};

/// True when [name] looks like an archive the reader opens.
bool isArchiveName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return archiveExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Lets the user pick an archive and reads it (IMG-017).
Future<void> pickAndOpenArchive(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await ref.read(storageProvider).pickFiles();
  if (picked.isEmpty || !context.mounted) return;
  final f = picked.first;
  if (!isArchiveName(f.name)) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosReaderNotArchive)),
    );
    return;
  }
  await openArchive(context, ArchiveRef(uri: f.uri, name: f.name));
}

Future<void> openArchive(BuildContext context, ArchiveRef archive) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ComicReaderScreen(archive: archive)),
    );

/// The comic reading mode (IMG-017): the pictures of an archive in order,
/// left to right or right to left, one page or two side by side, fitted to the
/// page, the width or the height, with the place remembered.
class ComicReaderScreen extends ConsumerStatefulWidget {
  const ComicReaderScreen({required this.archive, super.key});

  final ArchiveRef archive;

  @override
  ConsumerState<ComicReaderScreen> createState() => _ComicReaderState();
}

class _ComicReaderState extends ConsumerState<ComicReaderScreen> {
  ArchiveBook? _book;
  ArchiveProblem? _problem;
  late ReaderSettings _s = ReaderPrefs.read(ref.read(settingsStoreProvider));
  List<Size?> _sizes = const [];
  List<Spread> _spreads = const [];
  final Map<int, Future<ViewerImage?>> _images = {};
  PageController _pages = PageController();
  int _at = 0;
  bool _chrome = true;
  bool _disposed = false;
  final FocusNode _focus = FocusNode(debugLabel: 'comic');

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open({String? passphrase}) async {
    try {
      final book = await ref
          .read(archiveBooksProvider)
          .open(widget.archive, passphrase: passphrase);
      if (_disposed) {
        await book.close();
        return;
      }
      final store = ref.read(settingsStoreProvider);
      final start = ReaderPrefs.page(store, widget.archive.key);
      _book?.close().ignore();
      _forgetImages();
      setState(() {
        _book = book;
        _problem = null;
        _sizes = List<Size?>.filled(book.pageCount, null);
        _layout(keep: start.clamp(0, book.pageCount - 1));
      });
    } on ArchiveBookException catch (e) {
      if (_disposed) return;
      if (e.problem == ArchiveProblem.needsPassphrase) {
        await _askPassphrase();
      } else {
        setState(() => _problem = e.problem);
      }
    } on Object {
      if (!_disposed && mounted) {
        setState(() => _problem = ArchiveProblem.unreadable);
      }
    }
  }

  Future<void> _askPassphrase() async {
    final pass = await showDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(),
    );
    if (!mounted || _disposed) return;
    if (pass == null || pass.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    await _open(passphrase: pass);
  }

  @override
  void dispose() {
    _disposed = true;
    _pages.dispose();
    _focus.dispose();
    _forgetImages();
    unawaited(_book?.close());
    super.dispose();
  }

  // ---- layout and pages --------------------------------------------------

  /// Works the spreads out again, keeping page [keep] (or the one on screen).
  void _layout({int? keep}) {
    final book = _book;
    if (book == null) return;
    final page = keep ?? (_spreads.isEmpty ? 0 : _spreads[_at].first);
    _spreads = buildSpreads(book.pageCount, _sizes, _s.mode);
    _at = spreadOf(_spreads, page);
    final old = _pages;
    _pages = PageController(initialPage: _at);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _wanted();
  }

  void _forgetImages() {
    for (final f in _images.values) {
      unawaited(f.then((i) => i?.dispose()));
    }
    _images.clear();
  }

  /// The pages near the one on screen stay loaded; the rest are let go.
  void _wanted() {
    if (_spreads.isEmpty) return;
    final keep = <int>{};
    for (
      var i = math.max(0, _at - 1);
      i <= math.min(_spreads.length - 1, _at + 1);
      i++
    ) {
      keep.addAll(_spreads[i].pages);
    }
    for (final p in _images.keys.toList()) {
      if (!keep.contains(p)) {
        unawaited(_images.remove(p)!.then((i) => i?.dispose()));
      }
    }
    keep.forEach(_image);
  }

  Future<ViewerImage?> _image(int page) => _images[page] ??= _load(page);

  Future<ViewerImage?> _load(int page) async {
    final book = _book;
    if (book == null) return null;
    try {
      final image = await ref.read(comicPageLoaderProvider)(book, page);
      if (_disposed || _book != book) {
        image.dispose();
        return null;
      }
      final known = _sizes[page];
      _sizes[page] = image.fullSize;
      if (mounted &&
          _s.mode != PageMode.single &&
          known == null &&
          isWidePage(image.fullSize)) {
        // A double-page picture: the spreads around it shift.
        setState(_layout);
      } else if (mounted) {
        setState(() {});
      }
      return image;
    } on ArchiveBookException catch (e) {
      if (e.problem == ArchiveProblem.needsPassphrase && mounted) {
        unawaited(_askPassphrase());
      }
      return null;
    } on Object {
      return null;
    }
  }

  void _go(int spread) {
    if (spread < 0 || spread >= _spreads.length) return;
    _pages.animateToPage(
      spread,
      duration: KMotion.resolve(
        KMotion.base,
        reduceMotion: KAccessibility.reduceMotion(context),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPage(int spread) {
    setState(() => _at = spread);
    _wanted();
    ReaderPrefs.savePage(
      ref.read(settingsStoreProvider),
      widget.archive.key,
      _spreads[spread].first,
    );
  }

  void _change(ReaderSettings next) {
    ReaderPrefs.write(ref.read(settingsStoreProvider), next);
    setState(() {
      final modeChanged = next.mode != _s.mode;
      _s = next;
      if (modeChanged) _layout();
    });
  }

  // ---- keys and taps -----------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ltr = _s.direction == ReadingDirection.leftToRight;
    if (k == LogicalKeyboardKey.arrowRight) {
      _go(_at + (ltr ? 1 : -1));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(_at + (ltr ? -1 : 1));
    } else if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.arrowDown) {
      _go(_at + 1);
    } else if (k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.arrowUp) {
      _go(_at - 1);
    } else if (k == LogicalKeyboardKey.home) {
      _go(0);
    } else if (k == LogicalKeyboardKey.end) {
      _go(_spreads.length - 1);
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onTap(TapUpDetails d, double width) {
    switch (tapAction(d.localPosition, width, _s.direction)) {
      case TapAction.next:
        _go(_at + 1);
      case TapAction.previous:
        _go(_at - 1);
      case TapAction.toggleControls:
        setState(() => _chrome = !_chrome);
    }
  }

  // ---- drawing -----------------------------------------------------------

  Widget _slot(int page) => FutureBuilder<ViewerImage?>(
    future: _image(page),
    builder: (context, snap) {
      final image = snap.data;
      if (snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (image == null) {
        return Center(
          child: Icon(
            Icons.broken_image_outlined,
            semanticLabel: AppLocalizations.of(context).photosReaderPageFailed,
            color: Colors.white54,
          ),
        );
      }
      return RawImage(image: image.base, fit: BoxFit.fill);
    },
  );

  Widget _spreadView(Spread spread, Size viewport) {
    final (left, right) = spread.sides(_s.direction);
    final pageL = left == null ? null : _sizes[left];
    final pageR = right == null ? null : _sizes[right];
    final knownL = left == null || pageL != null;
    final knownR = right == null || pageR != null;
    if (!knownL || !knownR) {
      // Not decoded yet (or failed): the slots show a spinner or an icon.
      return Row(
        children: [
          if (left != null) Expanded(child: _slot(left)),
          if (right != null) Expanded(child: _slot(right)),
        ],
      );
    }
    final Size natural;
    if (left != null && right != null) {
      natural = spreadSize(pageL!, pageR!);
    } else {
      natural = (pageL ?? pageR)!;
    }
    final shown = fitted(viewport, natural, _s.fit);
    Widget row() {
      final h = natural.height;
      return SizedBox(
        width: natural.width,
        height: h,
        child: Row(
          children: [
            for (final (page, size) in [(left, pageL), (right, pageR)])
              if (page != null)
                SizedBox(
                  width: size!.width * h / size.height,
                  height: h,
                  child: _slot(page),
                ),
          ],
        ),
      );
    }

    final content = SizedBox(
      width: shown.width,
      height: shown.height,
      child: FittedBox(fit: BoxFit.fill, child: row()),
    );
    return InteractiveViewer(
      constrained: false,
      maxScale: 5,
      child: SizedBox(
        width: math.max(viewport.width, shown.width),
        height: math.max(viewport.height, shown.height),
        child: Center(child: content),
      ),
    );
  }

  String _positionText(AppLocalizations l10n) {
    final book = _book!;
    final s = _spreads[_at];
    if (s.second == null) {
      return l10n.photosReaderPage(s.first + 1, book.pageCount);
    }
    final a = math.min(s.first, s.second!) + 1;
    final b = math.max(s.first, s.second!) + 1;
    return l10n.photosReaderPages(a, b, book.pageCount);
  }

  Future<void> _settings() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget group<T>(
            String title,
            T value,
            Map<T, String> options,
            void Function(T) onPick,
          ) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in options.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: e.key == value,
                        onSelected: (_) {
                          onPick(e.key);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  group<ReadingDirection>(
                    l10n.photosReaderDirection,
                    _s.direction,
                    {
                      ReadingDirection.leftToRight: l10n.photosReaderLtr,
                      ReadingDirection.rightToLeft: l10n.photosReaderRtl,
                    },
                    (v) => _change(_s.copyWith(direction: v)),
                  ),
                  group<PageMode>(l10n.photosReaderPagesMode, _s.mode, {
                    PageMode.single: l10n.photosReaderOnePage,
                    PageMode.double: l10n.photosReaderTwoPages,
                    PageMode.doubleCoverAlone: l10n.photosReaderTwoPagesCover,
                  }, (v) => _change(_s.copyWith(mode: v))),
                  group<PageFit>(l10n.photosReaderFit, _s.fit, {
                    PageFit.page: l10n.photosReaderFitPage,
                    PageFit.width: l10n.photosReaderFitWidth,
                    PageFit.height: l10n.photosReaderFitHeight,
                  }, (v) => _change(_s.copyWith(fit: v))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = _book;
    Widget body;
    if (_problem != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _problem == ArchiveProblem.noPages
                ? l10n.photosReaderNoPages
                : l10n.photosReaderUnreadable,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (book == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = LayoutBuilder(
        builder: (context, box) {
          final viewport = Size(box.maxWidth, box.maxHeight);
          return Semantics(
            container: true,
            liveRegion: true,
            label: _positionText(l10n),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) => _onTap(d, box.maxWidth),
              child: PageView.builder(
                controller: _pages,
                reverse: _s.direction == ReadingDirection.rightToLeft,
                itemCount: _spreads.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) => KeyedSubtree(
                  key: ValueKey('${_s.mode.name}-${_spreads[i]}'),
                  child: _spreadView(_spreads[i], viewport),
                ),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: KMotion.base,
                  child: ColoredBox(
                    color: Colors.black54,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            color: Colors.white,
                            icon: const BackButtonIcon(),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          Expanded(
                            child: Text(
                              widget.archive.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.photosReaderSettings,
                            color: Colors.white,
                            icon: const Icon(Icons.tune),
                            onPressed: book == null
                                ? null
                                : () => unawaited(_settings()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (book != null && _spreads.isNotEmpty)
              PositionedDirectional(
                bottom: 0,
                start: 0,
                end: 0,
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: AnimatedOpacity(
                    opacity: _chrome ? 1 : 0,
                    duration: KMotion.base,
                    child: ColoredBox(
                      color: Colors.black54,
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip:
                                  _s.direction == ReadingDirection.leftToRight
                                  ? l10n.photosPagePrevious
                                  : l10n.photosPageNext,
                              color: Colors.white,
                              icon: const Icon(Icons.chevron_left),
                              onPressed:
                                  _s.direction == ReadingDirection.leftToRight
                                  ? () => _go(_at - 1)
                                  : () => _go(_at + 1),
                            ),
                            Expanded(
                              child: Directionality(
                                textDirection:
                                    _s.direction == ReadingDirection.rightToLeft
                                    ? ui.TextDirection.rtl
                                    : ui.TextDirection.ltr,
                                child: Slider(
                                  value: _at.toDouble(),
                                  max: math
                                      .max(1, _spreads.length - 1)
                                      .toDouble(),
                                  divisions: _spreads.length > 1
                                      ? _spreads.length - 1
                                      : null,
                                  label: _positionText(l10n),
                                  semanticFormatterCallback: (_) =>
                                      _positionText(l10n),
                                  onChanged: _spreads.length > 1
                                      ? (v) => _pages.jumpToPage(v.round())
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  _s.direction == ReadingDirection.leftToRight
                                  ? l10n.photosPageNext
                                  : l10n.photosPagePrevious,
                              color: Colors.white,
                              icon: const Icon(Icons.chevron_right),
                              onPressed:
                                  _s.direction == ReadingDirection.leftToRight
                                  ? () => _go(_at + 1)
                                  : () => _go(_at - 1),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                _positionText(l10n),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the password of an archive. Owns its field, so the field lives
/// as long as the dialog does, including while it closes.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photosReaderPassphraseTitle),
      content: TextField(
        controller: _field,
        obscureText: true,
        autofocus: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: l10n.photosReaderPassphraseLabel,
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: Text(l10n.photosReaderPassphraseOpen),
        ),
      ],
    );
  }
}
