import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';

/// The video played most recently, for "resume" shortcuts and the Assistant
/// (SYS-003). Hidden, vault and vanished items are never returned: a shortcut
/// must not reveal or open them. Its resume point is kept by the player.
Future<ItemRow?> lastPlayedVideo(LibraryDatabase db) =>
    (db.select(db.items)
          ..where(
            (i) =>
                i.kind.equalsValue(ItemKind.video) &
                i.lastPlayedAt.isNotNull() &
                i.missing.equals(false) &
                i.hidden.equals(false) &
                i.vault.equals(false),
          )
          ..orderBy([(i) => OrderingTerm.desc(i.lastPlayedAt)])
          ..limit(1))
        .getSingleOrNull();
