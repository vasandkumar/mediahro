import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/features/photos/viewer/viewer_surface.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// One picture handed to Mediahro by another app (Open with, Share): a
/// `content://` URI or a `file://` URI inside a held folder. It has no library
/// entry, so the viewer reads it through the storage facade.
@immutable
final class ExternalImage {
  const ExternalImage(this.uri, this.name);

  final Uri uri;
  final String name;
}

/// The pictures of one hand-over and the one to start on.
@immutable
final class ExternalImageArgs {
  const ExternalImageArgs(this.images, [this.index = 0]);

  final List<ExternalImage> images;
  final int index;
}

abstract final class ExternalImageRoutes {
  /// Outside the shell, like the library viewer. Not a prefix of a shell path.
  static const String view = '/view-external';
}

/// The full-screen route of [ExternalImageViewer]; `main.dart` lists it in
/// `appRoutesProvider`.
final List<RouteBase> externalImageRoutes = [
  GoRoute(
    path: ExternalImageRoutes.view,
    builder: (context, state) => switch (state.extra) {
      final ExternalImageArgs a when a.images.isNotEmpty => ExternalImageViewer(
        args: a,
      ),
      // A restored route has no pictures: back to the app.
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Opens one external picture for the viewer; tests replace it.
typedef ExternalImageLoader = Future<ViewerImage> Function(Uri uri);

/// Reads the picture whole, up to 64 MB, and opens it in the image pipeline.
final Provider<ExternalImageLoader> externalImageLoaderProvider =
    Provider<ExternalImageLoader>((ref) {
      return (uri) async {
        final bytes = await readPickedFile(ref.read(storageProvider), uri);
        final file = _MemoryFile(uri, bytes);
        try {
          return await loadViewerImage(
            ref.read(imagePipelineProvider),
            ImageSource(file),
            onDispose: file.close,
          );
        } on Object {
          await file.close();
          rethrow;
        }
      };
    });

/// Swipe through pictures that other apps handed over, with the library
/// viewer's zoom and pan (IMG-004). There is no library, favourites, edit or
/// share here: the pictures are read once and never copied.
class ExternalImageViewer extends ConsumerStatefulWidget {
  const ExternalImageViewer({required this.args, super.key});

  final ExternalImageArgs args;

  @override
  ConsumerState<ExternalImageViewer> createState() =>
      _ExternalImageViewerState();
}

class _ExternalImageViewerState extends ConsumerState<ExternalImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.args.index.clamp(0, widget.args.images.length - 1),
  );
  late int _index = _pages.initialPage;
  bool _atFit = true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.args.images;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          images.length > 1
              ? '${images[_index].name} (${_index + 1}/${images.length})'
              : images[_index].name,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: images.length,
        // A zoomed picture pans; the page turns only at the fit zoom.
        physics: _atFit
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() {
          _index = i;
          _atFit = true;
        }),
        itemBuilder: (context, i) => _ExternalPage(
          key: ValueKey(images[i].uri),
          image: images[i],
          onAtFitChanged: (fit) {
            if (i == _index && fit != _atFit) setState(() => _atFit = fit);
          },
        ),
      ),
    );
  }
}

class _ExternalPage extends ConsumerStatefulWidget {
  const _ExternalPage({
    required this.image,
    required this.onAtFitChanged,
    super.key,
  });

  final ExternalImage image;
  final ValueChanged<bool> onAtFitChanged;

  @override
  ConsumerState<_ExternalPage> createState() => _ExternalPageState();
}

class _ExternalPageState extends ConsumerState<_ExternalPage> {
  ViewerImage? _loaded;
  Object? _error;
  var _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final image = await ref.read(externalImageLoaderProvider)(
        widget.image.uri,
      );
      if (_closed) {
        image.dispose();
        return;
      }
      setState(() => _loaded = image);
    } on Object catch (e) {
      if (!_closed) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _loaded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _loaded;
    if (image != null) {
      return Semantics(
        image: true,
        label: widget.image.name,
        child: ViewerSurface(
          base: image.base,
          fullSize: image.fullSize,
          tileLoader: image.tileLoader,
          onAtFitChanged: widget.onAtFitChanged,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context).appIncomingFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return const SizedBox.expand();
  }
}

/// A picture already read into memory, as a [VirtualFile] for the image
/// pipeline.
final class _MemoryFile implements VirtualFile {
  _MemoryFile(this.uri, this._bytes);

  @override
  final Uri uri;
  final Uint8List _bytes;
  var _closed = false;

  @override
  bool get isSeekable => true;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw VirtualFileException(VirtualFileError.closed, uri);
    if (length <= 0 || offset >= _bytes.length) return Uint8List(0);
    final end = offset + length > _bytes.length
        ? _bytes.length
        : offset + length;
    return Uint8List.sublistView(_bytes, offset, end);
  }

  @override
  Future<void> close() async => _closed = true;
}
