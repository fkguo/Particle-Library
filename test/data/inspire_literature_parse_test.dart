import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/inspire_literature_search.dart';

Map<String, Object?> _hit({
  List<Map<String, Object?>> authors = const [],
  List<Map<String, Object?>> collaborations = const [],
}) => {
  'metadata': {
    'control_number': 3161743,
    'titles': [
      {'title': 'Elliptic Flow of Multi-strange Hadrons', 'source': 'arXiv'},
    ],
    'authors': authors,
    'collaborations': collaborations,
  },
};

void main() {
  test('collaboration-only records use the collaboration as the byline', () {
    final hit = parseInspireLiteratureHit(
      _hit(collaborations: [
        {'value': 'STAR'},
      ]),
    );
    expect(hit, isNotNull);
    expect(hit!.authors, isEmpty);
    expect(hit.byline, 'STAR Collaboration');
    expect(hit.bylineShort, 'STAR Collaboration');
  });

  test('a collaboration value that already ends with Collaboration is kept', () {
    final hit = parseInspireLiteratureHit(
      _hit(collaborations: [
        {'value': 'STAR Collaboration'},
      ]),
    );
    expect(hit!.byline, 'STAR Collaboration');
  });

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

  test('records without authors or collaborations have an empty byline', () {
    final hit = parseInspireLiteratureHit(_hit());
    expect(hit!.byline, isEmpty);
    expect(hit.bylineShort, isEmpty);
  });
}
