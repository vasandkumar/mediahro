import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/features/photos/organise/photo_selection.dart';

void main() {
  final order = [10, 11, 12, 13, 14, 15];

  test('IMG-005 toggling selects and deselects, and notifies', () {
    final s = PhotoSelection();
    var n = 0;
    s.addListener(() => n++);
    expect(s.active, isFalse);
    s.toggle(11);
    s.toggle(13);
    expect(s.ids, {11, 13});
    expect(s.active, isTrue);
    s.toggle(11);
    expect(s.ids, {13});
    expect(n, 3);
    s.clear();
    expect(s.active, isFalse);
  });

  test(
    'IMG-005 a drag selects the range between the first tile and the finger',
    () {
      final s = PhotoSelection()..toggle(10);
      s
        ..beginDrag(2, order)
        ..dragTo(4, order);
      expect(s.ids, {10, 12, 13, 14});
      s.dragTo(3, order);
      expect(s.ids, {10, 12, 13}, reason: 'shrinking the drag deselects again');
      s.dragTo(0, order);
      expect(s.ids, {10, 11, 12});
      s.endDrag();
      expect(s.dragging, isFalse);
    },
  );

  test('IMG-005 dragging from a selected tile deselects the range', () {
    final s = PhotoSelection()..selectAll(order);
    s
      ..beginDrag(1, order)
      ..dragTo(3, order);
    expect(s.ids, {10, 14, 15});
    s.dragTo(1, order);
    expect(s.ids, {10, 12, 13, 14, 15});
  });

  test('IMG-005 selectAll replaces the selection', () {
    final s = PhotoSelection()..toggle(99);
    s.selectAll([1, 2]);
    expect(s.ids, {1, 2});
    expect(s.length, 2);
  });
}
