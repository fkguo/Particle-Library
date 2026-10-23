import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/search/review_notation.dart';
import 'package:pdgapp/search/review_query.dart';

void main() {
  final rules = jsonDecode(
    File('assets/review_search_rules_v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('Dart aliases match the generated rules asset', () {
    final aliases = <String, List<String>>{
      for (final entry in (rules['aliases'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as List).cast<String>(),
    };
    expect(ReviewNotation.aliases, equals(aliases));
  });

  test('every notation vector canonicalizes to its rule key', () {
    final notation = rules['notation'] as Map<String, dynamic>;
    for (final entry in notation.entries) {
      for (final raw in (entry.value as List).cast<String>()) {
        expect(
          ReviewNotation.normalize(raw),
          contains(entry.key),
          reason: '$raw -> ${entry.key}',
        );
      }
    }
  });

  test('every golden query parses to the expected canonical structure', () {
    for (final item in (rules['golden'] as List).cast<Map<String, dynamic>>()) {
      final raw = item['raw'] as String;
      final query = ReviewQuery.parse(raw);
      expect(query.isEmpty, isFalse, reason: raw);
      expect(query.rankWords, isNotEmpty, reason: raw);
      expect(query.expression, item['expression'] as String, reason: raw);
    }
  });
}
