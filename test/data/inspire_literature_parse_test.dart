import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/inspire_literature_search.dart';

Map<String, Object?> _hit({
  List<Map<String, Object?>> authors = const [],
  List<Map<String, Object?>> collaborations = const [],
  Map<String, Object?>? firstAuthor,
  int authorCount = 0,
}) => {
  'metadata': {
    'control_number': 3161743,
    'titles': [
      {'title': 'Elliptic Flow of Multi-strange Hadrons', 'source': 'arXiv'},
    ],
    'authors': authors,
    'first_author': ?firstAuthor,
    'author_count': authorCount,
    'collaborations': collaborations,
  },
};

void main() {
  test('collaboration-only records use the collaboration as the byline', () {
    final hit = parseInspireLiteratureHit(
      _hit(
        collaborations: [
          {'value': 'STAR'},
        ],
      ),
    );
    expect(hit, isNotNull);
    expect(hit!.authors, isEmpty);
    expect(hit.byline, 'STAR Collaboration');
    expect(hit.bylineShort, 'STAR Collaboration');
  });

  test(
    'a collaboration value that already ends with Collaboration is kept',
    () {
      final hit = parseInspireLiteratureHit(
        _hit(
          collaborations: [
            {'value': 'STAR Collaboration'},
          ],
        ),
      );
      expect(hit!.byline, 'STAR Collaboration');
    },
  );

  test('individual authors win and long lists are shortened', () {
    final hit = parseInspireLiteratureHit(
      _hit(
        authors: [
          for (var i = 0; i < 7; i++) {'full_name': 'Author $i'},
        ],
        collaborations: [
          {'value': 'STAR'},
        ],
      ),
    );
    expect(hit!.byline, startsWith('Author 0, Author 1'));
    expect(hit.bylineShort, endsWith('et al.'));
    expect(hit.bylineShort, contains('Author 4'));
    expect(hit.bylineShort, isNot(contains('Author 5')));
  });

  test('a record without the author array falls back to first_author', () {
    final hit = parseInspireLiteratureHit(
      _hit(firstAuthor: {'full_name': 'Jia, Jiangyong'}, authorCount: 1664),
    );
    expect(hit!.authors, isEmpty);
    expect(hit.byline, 'Jia, Jiangyong et al.');
    expect(hit.bylineShort, 'Jia, Jiangyong et al.');
  });

  test('records without authors or collaborations have an empty byline', () {
    final hit = parseInspireLiteratureHit(_hit());
    expect(hit!.byline, isEmpty);
    expect(hit.bylineShort, isEmpty);
  });
}
