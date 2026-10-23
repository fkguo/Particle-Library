import '../data/review_index_store.dart';
import '../features/reviews/review_index.dart';
import 'review_notation.dart';
import 'review_query.dart';
import 'review_ranker.dart';
import 'review_search_repository.dart';

/// Lazily installs and opens the bundled review index.  Creating this service
/// costs nothing; the first review search pays the one-time asset copy.
class ReviewSearchService {
  ReviewSearchService({
    ReviewIndexStore? store,
    ReviewSearchRepository? repository,
  }) : _store = store ?? ReviewIndexStore(),
       _repository = repository {
    if (repository != null) {
      _opening = Future<ReviewSearchRepository?>.value(repository);
      revision = 1;
    }
  }

  final ReviewIndexStore _store;
  Future<ReviewSearchRepository?>? _opening;
  ReviewSearchRepository? _repository;
  bool _disposed = false;

  bool get isReady => _repository != null;
  bool get isDisposed => _disposed;
  int revision = 0;

  Future<ReviewSearchResult> search(String raw, {int limit = 25}) async {
    if (_disposed) {
      return _catalogFallback(raw, limit);
    }
    final repository = await _ensure();
    if (repository == null) {
      return _catalogFallback(raw, limit);
    }
    try {
      return await repository.search(raw, limit: limit);
    } catch (_) {
      return _catalogFallback(raw, limit);
    }
  }

  Future<ReviewSearchRepository?> _ensure() {
    final repository = _repository;
    if (repository != null) {
      return Future<ReviewSearchRepository?>.value(repository);
    }
    final running = _opening;
    if (running != null) return running;
    final future = _open();
    _opening = future;
    future.whenComplete(() {
      if (identical(_opening, future)) _opening = null;
    });
    return future;
  }

  Future<ReviewSearchRepository?> _open() async {
    try {
      final executor = await _store.open();
      if (_disposed) {
        await executor.dispose();
        return null;
      }
      final repository = ReviewSearchRepository(executor);
      _repository = repository;
      revision++;
      return repository;
    } catch (_) {
      return null;
    }
  }

  /// The review directory is compiled into the app, so a failed index can
  /// still answer title queries.  This is deliberately title-only: no text
  /// claim is made when the full-text database did not open.
  ReviewSearchResult _catalogFallback(String raw, int limit) {
    final query = ReviewQuery.parse(raw);
    if (query.isEmpty) {
      return ReviewSearchResult(
        hits: const [],
        notice: query.notice,
        degraded: true,
      );
    }
    final hits = <ReviewRankedHit>[];
    for (final group in reviewGroups) {
      for (final entry in group.entries) {
        final title = entry.title;
        final all = ReviewNotation.titleMatches(
          title,
          query.rankWords,
          prefixWord: query.prefixWord,
          exactWords: query.exactWords,
        );
        if (!all && !ReviewNotation.titleHasPhrase(title, query.rankWords)) {
          continue;
        }
        hits.add(
          ReviewRankedHit(
            file: entry.file,
            title: entry.title,
            page: 1,
            heading: entry.title,
            caption: '',
            matchCount: 0,
            score: all ? 20 : 10,
            matchField: 'title',
          ),
        );
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return ReviewSearchResult(
      hits: hits.take(limit).toList(growable: false),
      notice: 'unavailable',
      degraded: true,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _repository?.dispose();
    _repository = null;
  }
}
