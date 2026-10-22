import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reviews/reading_history.dart';

ReadingPosition position(int page, double y) =>
    ReadingPosition(page: page, offset: Offset(0, y), zoom: 1.5);

void main() {
  test('pops positions in reverse order', () {
    final history = ReadingHistory();
    expect(history.canGoBack, isFalse);
    history.push(position(2, 100));
    history.push(position(5, 800));
    expect(history.canGoBack, isTrue);
    expect(history.pop(), position(5, 800));
    expect(history.pop(), position(2, 100));
    expect(history.pop(), isNull);
  });

  test('repeated identical positions are not stacked twice', () {
    final history = ReadingHistory();
    history.push(position(3, 400));
    history.push(position(3, 400));
    expect(history.length, 1);
  });

  test('the stack is bounded', () {
    final history = ReadingHistory(capacity: 3);
    for (var i = 1; i <= 5; i++) {
      history.push(position(i, i * 10));
    }
    expect(history.length, 3);
    expect(history.pop(), position(5, 50));
    expect(history.pop(), position(4, 40));
    expect(history.pop(), position(3, 30));
  });
}
