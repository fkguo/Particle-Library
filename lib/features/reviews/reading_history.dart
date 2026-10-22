import 'dart:ui';

/// One remembered reading position inside a review PDF.
class ReadingPosition {
  const ReadingPosition({
    required this.page,
    required this.offset,
    required this.zoom,
  });

  final int page;
  final Offset offset;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.page == page &&
      other.offset == offset &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(page, offset, zoom);
}

/// Small back stack for jumps inside a review (outline, highlights, page
/// dialog). Bounded and duplicate-suppressed; the most recent position is the
/// last element.
class ReadingHistory {
  ReadingHistory({this.capacity = 20}) : assert(capacity > 0);

  final int capacity;
  final List<ReadingPosition> _positions = <ReadingPosition>[];

  bool get canGoBack => _positions.isNotEmpty;
  int get length => _positions.length;
  ReadingPosition? get last => _positions.isEmpty ? null : _positions.last;

  void push(ReadingPosition position) {
    if (_positions.isNotEmpty && _positions.last == position) return;
    _positions.add(position);
    while (_positions.length > capacity) {
      _positions.removeAt(0);
    }
  }

  ReadingPosition? pop() => _positions.isEmpty ? null : _positions.removeLast();

  void clear() => _positions.clear();
}
