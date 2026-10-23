import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/search/review_ranker.dart';

ReviewPageRow row({
  required int page,
  required double rank,
  int? sectionStart,
  int isReference = 0,
  String caption = '',
}) {
  return ReviewPageRow(
    file: 'rpp2026-rev-cross-section-plots.pdf',
    title: 'Plots of cross sections and related quantities',
    titleNorm: 'plots of cross sections and related quantities',
    fullTitle: 'Plots of Cross Sections and Related Quantities',
    page: page,
    heading:
        'Average Hadron Multiplicities in Hadronic e+ e- Annihilation Events',
    sectionStartPage: sectionStart,
    isReference: isReference,
    caption: caption,
    rank: rank,
  );
}

void main() {
  test('adjusted page score prefers the table page over references', () {
    final hits = ReviewRanker.rank(
      [
        row(
          page: 2,
          rank: -9.18,
          sectionStart: 2,
          caption: 'Table 53.1: Average hadron multiplicities',
        ),
        row(page: 3, rank: -8.93, sectionStart: 2),
        row(page: 4, rank: -9.34, sectionStart: 2, isReference: 1),
      ],
      ['average', 'hadron', 'multiplicities'],
      limit: 5,
    );
    expect(hits, hasLength(1));
    expect(hits.first.page, 2);
    expect(hits.first.matchCount, 3);
    expect(hits.first.matchField, 'caption');
  });

  test('title match adds a small but visible boost', () {
    final hits = ReviewRanker.rank(
      [
        ReviewPageRow(
          file: 'a.pdf',
          title: 'Plots of cross sections and related quantities',
          titleNorm: 'plots of cross sections and related quantities',
          fullTitle: 'Plots of Cross Sections and Related Quantities',
          page: 5,
          heading: 'Annihilation Cross Section Near MZ',
          sectionStartPage: 5,
          isReference: 0,
          caption: 'Figure 53.2: Combined data ...',
          rank: -8,
        ),
      ],
      ['cross', 'sections'],
    );
    expect(hits, hasLength(1));
    expect(hits.first.page, 5);
    expect(hits.first.score, greaterThan(0));
  });
}
