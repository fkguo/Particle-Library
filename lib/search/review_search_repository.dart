import '../data/sql_executor.dart';
import 'review_notation.dart';
import 'review_query.dart';
import 'review_ranker.dart';

class ReviewSearchResult {
  const ReviewSearchResult({
    required this.hits,
    this.notice,
    this.degraded = false,
  });

  final List<ReviewRankedHit> hits;
  final String? notice;
  final bool degraded;
}

/// Read-only access to the bundled review index.  The SQL is fixed here; the
/// only user-controlled value is the already-validated FTS5 expression.
class ReviewSearchRepository {
  ReviewSearchRepository(this.executor);

  final SqlExecutor executor;

  Future<ReviewSearchResult> search(String raw, {int limit = 25}) async {
    final query = ReviewQuery.parse(raw);
    if (query.isEmpty) {
      return ReviewSearchResult(hits: const [], notice: query.notice);
    }
    try {
      final rows = await _pageRows(query.expression!);
      if (rows.isEmpty) {
        final titles = await _titleRows(
          query.rankWords,
          limit,
          prefixWord: query.prefixWord,
          exactWords: query.exactWords,
        );
        return ReviewSearchResult(hits: titles, notice: query.notice);
      }
      return ReviewSearchResult(
        hits: ReviewRanker.rank(rows, query.rankWords, limit: limit),
        notice: query.notice,
      );
    } catch (_) {
      final titles = await _titleRows(
        query.rankWords,
        limit,
        prefixWord: query.prefixWord,
        exactWords: query.exactWords,
      );
      return ReviewSearchResult(
        hits: titles,
        notice: 'degraded',
        degraded: true,
      );
    }
  }

  Future<List<ReviewPageRow>> _pageRows(String expression) async {
    final rows = await executor.select(
      '''
      SELECT r.file, r.title, r.title_norm, r.full_title, r.sha256,
             p.page, p.heading, p.section_start_page, p.is_reference,
             p.caption,
             bm25(page_fts, 8.0, 1.0, 0.5, 4.0, 2.0) AS rank
        FROM page_fts
        JOIN page p ON p.id = page_fts.rowid
        JOIN review r ON r.file = p.file
       WHERE page_fts MATCH ?
       ORDER BY rank
      ''',
      [expression],
    );
    return [
      for (final row in rows)
        ReviewPageRow(
          file: row['file'] as String,
          title: row['title'] as String,
          titleNorm: row['title_norm'] as String,
          fullTitle: row['full_title'] as String,
          page: (row['page'] as num).toInt(),
          heading: (row['heading'] as String?) ?? '',
          sectionStartPage: (row['section_start_page'] as num?)?.toInt(),
          isReference: (row['is_reference'] as num?)?.toInt() ?? 0,
          caption: (row['caption'] as String?) ?? '',
          rank: (row['rank'] as num).toDouble(),
          sha256: row['sha256'] as String?,
        ),
    ];
  }

  Future<List<ReviewRankedHit>> _titleRows(
    List<String> words,
    int limit, {
    String? prefixWord,
    Set<String> exactWords = const {},
  }) async {
    if (words.isEmpty) return const [];
    final rows = await executor.select(
      'SELECT file, title, title_norm, full_title, pages, sha256 FROM review',
    );
    final hits = <ReviewRankedHit>[];
    for (final row in rows) {
      final titleNorm = row['title_norm'] as String;
      final allWords = ReviewNotation.titleMatches(
        titleNorm,
        words,
        prefixWord: prefixWord,
        exactWords: exactWords,
      );
      if (!allWords && !ReviewNotation.titleHasPhrase(titleNorm, words)) {
        continue;
      }
      hits.add(
        ReviewRankedHit(
          file: row['file'] as String,
          title: row['title'] as String,
          page: 1,
          heading: row['full_title'] as String,
          caption: '',
          matchCount: 0,
          score: allWords ? 20 : 10,
          matchField: 'title',
          sha256: row['sha256'] as String?,
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList(growable: false);
  }

  Future<void> dispose() => executor.dispose();
}
