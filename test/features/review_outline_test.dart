import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reviews/review_viewer_page.dart';

void main() {
  test('the outline row covering a page is the last entry at or before it', () {
    const pages = <int?>[1, 3, null, 5, 7];
    expect(currentOutlineRowIndex(pages, 1), 0);
    expect(currentOutlineRowIndex(pages, 2), 0);
    // A null destination row is skipped, not selected.
    expect(currentOutlineRowIndex(pages, 4), 1);
    expect(currentOutlineRowIndex(pages, 5), 3);
    expect(currentOutlineRowIndex(pages, 9), 4);
    // Before the first entry there is no current section.
    expect(currentOutlineRowIndex(pages, 0), isNull);
    expect(currentOutlineRowIndex(const <int?>[], 3), isNull);
  });

  test('entries without a destination never become current', () {
    const pages = <int?>[null, null];
    expect(currentOutlineRowIndex(pages, 12), isNull);
  });
}
