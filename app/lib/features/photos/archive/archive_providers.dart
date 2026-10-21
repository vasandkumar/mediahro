import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/photos/archive/archive_book.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/viewer/viewer_image.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// How archives are opened as books (IMG-017); tests replace it.
final archiveBooksProvider = Provider<ArchiveBooks>(
  (ref) => FfiArchiveBooks(ref.watch(storageProvider)),
);

/// Decodes page [index] of a book for the reader; tests replace it. The
/// returned image closes the page file when disposed.
typedef ComicPageLoader = Future<ViewerImage> Function(
  ArchiveBook book,
  int index,
);

final comicPageLoaderProvider = Provider<ComicPageLoader>((ref) {
  final pipeline = ref.watch(imagePipelineProvider);
  return (book, index) async {
    final file = await book.openPage(index);
    try {
      return await loadViewerImage(
        pipeline,
        ImageSource(file),
        onDispose: file.close,
      );
    } on Object {
      await file.close();
      rethrow;
    }
  };
});
