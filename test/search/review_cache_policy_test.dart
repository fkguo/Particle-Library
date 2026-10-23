import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/search/search_service.dart';

void main() {
  test('degraded and unavailable results are not cacheable', () {
    for (final notice in ['unavailable', 'degraded']) {
      final result = SearchResults(
        query: 'CG coefficients',
        groups: const [],
        notice: notice,
      );
      expect(SearchService.isCacheable(result), isFalse, reason: notice);
    }
  });

  test('successful zero-hit results remain cacheable', () {
    const result = SearchResults(query: 'nothing', groups: []);
    expect(SearchService.isCacheable(result), isTrue);
  });
}
