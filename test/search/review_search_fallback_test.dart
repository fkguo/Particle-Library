import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/review_index_store.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/search/review_search_repository.dart';
import 'package:pdgapp/search/review_search_service.dart';

class _FailingStore extends ReviewIndexStore {
  @override
  Future<SqlExecutor> open() async {
    throw StateError('index unavailable');
  }
}

class _FlakyStore extends ReviewIndexStore {
  int calls = 0;

  @override
  Future<SqlExecutor> open() async {
    calls++;
    if (calls == 1) throw StateError('temporary failure');
    return _TitleOnlyExecutor();
  }
}

class _TitleOnlyExecutor implements SqlExecutor {
  @override
  Future<List<RawRow>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    if (sql.contains('page_fts MATCH')) {
      throw StateError('fts unavailable');
    }
    if (sql.contains('FROM review')) {
      return [
        for (var i = 0; i < 5; i++)
          <String, Object?>{
            'file': 'review_$i.pdf',
            'title': 'Physics review $i',
            'title_norm': 'physics review $i',
            'full_title': 'Physics Review $i',
            'pages': 1,
          },
      ];
    }
    return const [];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('a failed index still answers title queries from the catalog', () async {
    final service = ReviewSearchService(store: _FailingStore());
    final result = await service.search('CG coefficients');
    expect(result.degraded, isTrue);
    expect(result.notice, 'unavailable');
    expect(result.hits, isNotEmpty);
    expect(result.hits.first.file, 'rpp2026-rev-clebsch-gordan-coefs.pdf');
    await service.dispose();
  });

  test('a temporary open failure is retried on the next search', () async {
    final store = _FlakyStore();
    final service = ReviewSearchService(store: store);
    final first = await service.search('physics');
    expect(first.degraded, isTrue);
    expect(store.calls, 1);
    final second = await service.search('physics');
    expect(store.calls, 2);
    expect(service.isReady, isTrue);
    expect(second.hits, isNotEmpty);
    await service.dispose();
  });

  test('title fallback respects the caller limit', () async {
    final repository = ReviewSearchRepository(_TitleOnlyExecutor());
    final result = await repository.search('physics', limit: 1);
    expect(result.hits, hasLength(1));
    expect(result.degraded, isTrue);
    await repository.dispose();
  });
}
