import 'package:flutter/foundation.dart';

/// The photos selected in a grid (IMG-005): tap toggles once selecting,
/// a long press starts, and dragging across tiles selects or deselects a
/// range from the tile where the drag began.
class PhotoSelection extends ChangeNotifier {
  final Set<int> _ids = {};

  // Drag state.
  int? _anchor;
  bool _dragAdds = true;
  Set<int> _before = {};

  /// Selected item ids.
  Set<int> get ids => Set.unmodifiable(_ids);

  int get length => _ids.length;

  bool get active => _ids.isNotEmpty;

  bool get dragging => _anchor != null;

  bool contains(int id) => _ids.contains(id);

  void toggle(int id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void add(int id) {
    if (_ids.add(id)) notifyListeners();
  }

  void selectAll(Iterable<int> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty && _anchor == null) return;
    _ids.clear();
    _anchor = null;
    notifyListeners();
  }

  /// A long press on [index] (of [idsInOrder]) starts a drag selection: the
  /// press selects the tile, or deselects it if it was selected.
  void beginDrag(int index, List<int> idsInOrder) {
    final id = idsInOrder[index];
    _dragAdds = !_ids.contains(id);
    _anchor = index;
    _before = {..._ids};
    if (_dragAdds) {
      _ids.add(id);
    } else {
      _ids.remove(id);
    }
    notifyListeners();
  }

  /// The finger is over tile [index]: the range from the anchor to it is
  /// selected (or deselected), on top of what was selected before.
  void dragTo(int index, List<int> idsInOrder) {
    final a = _anchor;
    if (a == null) return;
    final lo = a < index ? a : index;
    final hi = a < index ? index : a;
    final next = {..._before};
    for (var i = lo; i <= hi; i++) {
      if (_dragAdds) {
        next.add(idsInOrder[i]);
      } else {
        next.remove(idsInOrder[i]);
      }
    }
    if (setEquals(next, _ids)) return;
    _ids
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void endDrag() {
    _anchor = null;
    _before = {};
  }
}
