import 'dart:convert';
import 'dart:io';

import 'package:mediahro/images/edit/edit_recipe.dart';

/// Keeps the unsaved edit of each photo, so closing the editor does not lose
/// it and the original file stays untouched until the user saves (IMG-009,
/// non-destructive). One small JSON file per photo under the app's data
/// folder.
final class EditStore {
  EditStore(this.directory);

  final Directory directory;

  File _file(int itemId) =>
      File('${directory.path}${Platform.pathSeparator}$itemId.json');

  /// The saved recipe of [itemId], or none; unreadable files count as none.
  Future<EditRecipe> load(int itemId) async {
    try {
      final f = _file(itemId);
      if (!f.existsSync()) return EditRecipe.none;
      return EditRecipe.fromJson(jsonDecode(await f.readAsString()));
    } on Object {
      return EditRecipe.none;
    }
  }

  /// Saves [recipe]; an identity recipe removes the file.
  Future<void> save(int itemId, EditRecipe recipe) async {
    if (recipe.isIdentity) {
      await delete(itemId);
      return;
    }
    try {
      await directory.create(recursive: true);
      final f = _file(itemId);
      final part = File('${f.path}.part');
      await part.writeAsString(jsonEncode(recipe.toJson()), flush: true);
      await part.rename(f.path);
    } on FileSystemException {
      // The edit is lost on close, not the photo.
    }
  }

  Future<void> delete(int itemId) async {
    try {
      final f = _file(itemId);
      if (f.existsSync()) await f.delete();
    } on FileSystemException {
      // Nothing to clean up.
    }
  }
}
