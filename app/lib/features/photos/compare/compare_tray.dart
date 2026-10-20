import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';

/// What happened when a photo was put into the compare tray.
enum TrayChange { added, removed, full, notAPhoto }

/// The photos waiting to be compared (IMG-008): up to four, picked one at a
/// time from the viewer, then opened side by side.
class CompareTray extends Notifier<List<PhotoEntry>> {
  static const int capacity = 4;

  @override
  List<PhotoEntry> build() => const [];

  bool contains(int id) => state.any((e) => e.id == id);

  /// Adds [entry], or takes it out when it is already there.
  TrayChange toggle(PhotoEntry entry) {
    if (contains(entry.id)) {
      state = [
        for (final e in state)
          if (e.id != entry.id) e,
      ];
      return TrayChange.removed;
    }
    if (entry.isVideo) return TrayChange.notAPhoto;
    if (state.length >= capacity) return TrayChange.full;
    state = [...state, entry];
    return TrayChange.added;
  }

  void clear() => state = const [];
}

final compareTrayProvider = NotifierProvider<CompareTray, List<PhotoEntry>>(
  CompareTray.new,
);
