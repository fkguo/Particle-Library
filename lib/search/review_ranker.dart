import 'dart:math' as math;

import 'review_notation.dart';

/// One FTS5 page hit.  Rows come from `page_fts` joined to `page`/`review`.
class ReviewPageRow {
  const ReviewPageRow({
    required this.file,
    required this.title,
    required this.titleNorm,
    required this.fullTitle,
    required this.page,
    required this.heading,
    required this.sectionStartPage,
    required this.isReference,
    required this.caption,
    required this.rank,
    this.sha256,
  });

  final String file;
  final String title;
  final String titleNorm;
  final String fullTitle;
  final int page;
  final String heading;
  final int? sectionStartPage;
  final int isReference;
  final String caption;
  final double rank;
  final String? sha256;
}

class ReviewRankedHit {
  const ReviewRankedHit({
    required this.file,
    required this.title,
    required this.page,
    required this.heading,
    required this.caption,
    required this.matchCount,
    required this.score,
    required this.matchField,
    this.sha256,
  });

  final String file;
  final String title;
  final int page;
  final String heading;
  final String caption;
  final int matchCount;
  final double score;
  final String matchField;
  final String? sha256;
}

class ReviewRanker {
  const ReviewRanker._();

  /// Rank reviews, then keep only the best page per review.  Every page is
  /// scored before the winner is chosen; picking the minimum bm25 first would
  /// let a reference page beat the actual table page.
  static List<ReviewRankedHit> rank(
    Iterable<ReviewPageRow> rows,
    List<String> words, {
    int limit = 25,
  }) {
    final groups = <String, List<ReviewPageRow>>{};
    for (final row in rows) {
      (groups[row.file] ??= []).add(row);
    }

    final hits = <ReviewRankedHit>[];
    for (final entry in groups.entries) {
      final pages = entry.value;
      var bestScore = double.negativeInfinity;
      ReviewPageRow? best;
      for (final row in pages) {
        var score = -row.rank;
        if (row.sectionStartPage == row.page) score += 1.5;
        final heading = row.heading.toLowerCase();
        if (words.isNotEmpty && words.every((word) => _has(heading, word))) {
          score += 4;
        }
        if (words.isNotEmpty && heading.contains(words.join(' '))) {
          score += 6;
        }
        if (words.any((word) => row.caption.toLowerCase().contains(word))) {
          score += 1;
        }
        if (row.isReference == 1) score -= 2.5;
        if (score > bestScore ||
            (score == bestScore && best != null && row.page < best.page)) {
          bestScore = score;
          best = row;
        }
      }
      if (best == null) continue;
      final titleText = '${best.title} ${best.fullTitle}';
      final titleMatched = ReviewNotation.titleMatches(titleText, words);
      final titleHits = words
          .where((word) => ReviewNotation.titleKey(titleText).contains(word))
          .length;
      final phrase = ReviewNotation.titleHasPhrase(titleText, words);
      final matchCount = pages.map((row) => row.page).toSet().length;
      final score =
          bestScore +
          6 * titleHits +
          (phrase ? 10 : 0) +
          0.8 * (math.log(1 + matchCount) / math.ln2);
      final matchField = titleMatched && best.page == 1
          ? 'title'
          : words.any((word) => best!.caption.toLowerCase().contains(word))
          ? 'caption'
          : words.any((word) => _has(best!.heading.toLowerCase(), word))
          ? 'heading'
          : 'body';
      hits.add(
        ReviewRankedHit(
          file: entry.key,
          title: best.title,
          page: best.page,
          heading: best.heading,
          caption: best.caption,
          matchCount: matchCount,
          score: score,
          matchField: matchField,
          sha256: best.sha256,
        ),
      );
    }

    hits.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.file.compareTo(b.file);
    });
    return hits.take(limit).toList(growable: false);
  }

  static bool _has(String haystack, String word) {
    if (word.isEmpty) return false;
    if (haystack.contains(word)) return true;
    if (word.endsWith('s') && word.length > 3) {
      return haystack.contains(word.substring(0, word.length - 1));
    }
    return false;
  }
}
