import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/search/review_notation.dart';
import 'package:pdgapp/search/review_query.dart';

void main() {
  test('CG coefficients expands the acronym but keeps the phrase', () {
    final query = ReviewQuery.parse('CG coefficients');
    expect(query.expression, '("cg" OR "clebsch gordan") AND "coefficients"');
    expect(query.rankWords, containsAll(['clebsch', 'gordan', 'coefficients']));
  });

  test('quoted CG expands to two complete phrases', () {
    final query = ReviewQuery.parse('"CG coefficients"');
    expect(
      query.expression,
      '("cg coefficients" OR "clebsch gordan coefficients")',
    );
  });

  test('HVP stays a phrase, not four OR words', () {
    final query = ReviewQuery.parse('HVP');
    expect(query.expression, '("hvp" OR "hadronic vacuum polarization")');
  });

  test('g-2 is normalized before tokenization', () {
    final query = ReviewQuery.parse('muon g-2');
    expect(
      query.expression,
      '"muon" AND ("gminus2" OR "anomalous magnetic moment")',
    );
  });

  test('e+e- and W prime use canonical tokens', () {
    expect(
      ReviewQuery.parse('e+e-').expression,
      '("electronpositronpair" OR "electron positron")',
    );
    expect(
      ReviewQuery.parse('e⁺e⁻').expression,
      '("electronpositronpair" OR "electron positron")',
    );
    expect(ReviewQuery.parse("W'").expression, '"wprime"');
    expect(ReviewQuery.parse("w'").expression, '"wprime"');
    expect(ReviewQuery.parse('W’').expression, '"wprime"');
    expect(ReviewQuery.parse('Wʹ').expression, '"wprime"');
    expect(
      ReviewQuery.parse('E+E-').expression,
      '("electronpositronpair" OR "electron positron")',
    );
    expect(
      ReviewQuery.parse('E⁺E⁻').expression,
      '("electronpositronpair" OR "electron positron")',
    );
    expect(ReviewNotation.normalize('b⁰'), contains('bzero'));
    expect(ReviewNotation.normalize('g⁻²'), contains('gminus2'));
  });

  test('title keys preserve prime before lowercasing', () {
    expect(ReviewNotation.titleKey("W'-boson searches"), contains('wprime'));
  });

  test('boolean-looking input is ordinary words', () {
    expect(
      ReviewQuery.parse('electron OR muon').expression,
      '"electron" AND "muon"',
    );
    expect(
      ReviewQuery.parse('NEAR(electron muon)').expression,
      '"electron" AND "muon"',
    );
  });

  test('empty, punctuation and lone Greek letters are controlled', () {
    for (final raw in ['', '-', '""', 'μ', '中文']) {
      final query = ReviewQuery.parse(raw);
      expect(query.isEmpty, isTrue, reason: raw);
      expect(query.notice, isNotNull, reason: raw);
    }
  });

  test('explicit trailing star is the only prefix', () {
    final query = ReviewQuery.parse('hadronic cross sect*');
    expect(query.expression, '"hadronic" AND "cross" AND sect*');
    expect(query.prefixWord, 'sect');
  });

  test('a star binds only to a valid final token', () {
    expect(ReviewQuery.parse('cleb x*').prefixWord, isNull);
    expect(ReviewQuery.parse('cleb OR*').prefixWord, isNull);
    expect(ReviewQuery.parse('cleb*').prefixWord, 'cleb');
    final mixed = ReviewQuery.parse('cleb cleb*');
    expect(mixed.prefixWord, 'cleb');
    expect(mixed.exactWords, contains('cleb'));
    final quoted = ReviewQuery.parse('"cleb" cleb*');
    expect(quoted.prefixWord, 'cleb');
    expect(quoted.exactWords, contains('cleb'));
    for (final raw in [
      'cleb μ*',
      'cleb 中文*',
      'cleb "x"*',
      'cleb "HVP"*',
      'cleb “x”*',
    ]) {
      expect(ReviewQuery.parse(raw).prefixWord, isNull, reason: raw);
    }
    final alias = ReviewQuery.parse('CG gordan*');
    expect(alias.prefixWord, 'gordan');
    expect(alias.exactWords, contains('gordan'));
    expect(ReviewQuery.parse('HVP hadronic*').exactWords, contains('hadronic'));
    final curly = ReviewQuery.parse('“hadronic cross sect”');
    expect(curly.expression, '"hadronic cross sect"');
    expect(ReviewQuery.parse('cleb “sect*').notice, ReviewQuery.noticeQuote);
  });
}
