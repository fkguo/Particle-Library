import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/search/review_search_repository.dart';

void main() {
  late DirectSqlExecutor executor;
  late ReviewSearchRepository repository;

  setUpAll(() async {
    const path = 'assets/review_index_2026.sqlite';
    if (!File(path).existsSync()) {
      fail('Review index asset missing; run tool/build_review_index.py first.');
    }
    executor = await DirectSqlExecutor.open(path);
    repository = ReviewSearchRepository(executor);
  });

  tearDownAll(() async {
    await repository.dispose();
  });

  test('index has the expected review/page coverage', () async {
    final rows = await executor.select(
      'SELECT (SELECT COUNT(*) FROM review) AS reviews, '
      '(SELECT COUNT(*) FROM page) AS pages',
    );
    expect(rows.single['reviews'], 121);
    expect(rows.single['pages'], 2163);
  });

  test('U1: CG coefficients -> Clebsch-Gordan p1', () async {
    final result = await repository.search('CG coefficients');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.file, 'rpp2026-rev-clebsch-gordan-coefs.pdf');
    expect(result.hits.first.page, 1);
    expect(result.hits.first.sha256, isNotNull);
  });

  test('U2: hadronic cross sections -> Plots p5', () async {
    final result = await repository.search('hadronic cross sections');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.file, 'rpp2026-rev-cross-section-plots.pdf');
    expect(result.hits.first.page, 5);
  });

  test('U3: average hadron multiplicities -> Plots p2, not p4', () async {
    final result = await repository.search('average hadron multiplicities');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.file, 'rpp2026-rev-cross-section-plots.pdf');
    expect(result.hits.first.page, 2);
  });

  test("W' -> the dedicated W'-boson review", () async {
    final result = await repository.search("W'");
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.file, 'rpp2026-rev-wprime-searches.pdf');
  });

  test('title_norm carries the canonical W prime token', () async {
    final rows = await executor.select(
      'SELECT title_norm FROM review WHERE file = ?',
      ['rpp2026-rev-wprime-searches.pdf'],
    );
    expect(rows.single['title_norm'], contains('wprime'));
  });

  test('canonical title tokens are not substring matches', () async {
    final result = await repository.search('rime');
    expect(result.hits, isEmpty);
  });

  test('empty query is controlled and does not run SQL', () async {
    final result = await repository.search('""');
    expect(result.hits, isEmpty);
    expect(result.notice, isNotNull);
  });
}
