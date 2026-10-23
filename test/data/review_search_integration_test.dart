import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/search/review_ranker.dart';
import 'package:pdgapp/search/review_search_repository.dart';
import 'package:pdgapp/search/review_search_service.dart';
import 'package:pdgapp/search/search_service.dart';

class _FlakyReviewSearch extends ReviewSearchService {
  int calls = 0;

  @override
  Future<ReviewSearchResult> search(String raw, {int limit = 25}) async {
    calls++;
    if (calls == 1) {
      return const ReviewSearchResult(
        hits: [],
        notice: 'unavailable',
        degraded: true,
      );
    }
    return const ReviewSearchResult(
      hits: [
        ReviewRankedHit(
          file: 'rpp2026-rev-clebsch-gordan-coefs.pdf',
          title: 'Clebsch-Gordan coeff., sph. harmonics, and d functions',
          page: 1,
          heading: 'Clebsch-Gordan Coefficients',
          caption: '',
          matchCount: 1,
          score: 1,
          matchField: 'title',
          sha256: 'x',
        ),
      ],
    );
  }
}

class _ThrowingReviewSearch extends ReviewSearchService {
  @override
  Future<ReviewSearchResult> search(String raw, {int limit = 25}) async {
    throw StateError('review search failure');
  }
}

void main() {
  late DirectSqlExecutor pdgExecutor;
  late DirectSqlExecutor reviewExecutor;
  late PdgDatabase database;
  late ReviewSearchService reviewSearch;
  late SearchService search;

  setUpAll(() async {
    if (!File('assets/pdgall-2026.0.sqlite').existsSync() ||
        !File('assets/review_index_2026.sqlite').existsSync()) {
      fail('Bundled PDG/review assets are missing.');
    }
    pdgExecutor = await DirectSqlExecutor.open('assets/pdgall-2026.0.sqlite');
    database = await PdgDatabase.open(
      pdgExecutor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
    reviewExecutor = await DirectSqlExecutor.open(
      'assets/review_index_2026.sqlite',
    );
    reviewSearch = ReviewSearchService(
      repository: ReviewSearchRepository(reviewExecutor),
    );
    search = SearchService(database, reviewSearch: reviewSearch);
  });

  tearDownAll(() async {
    await reviewSearch.dispose();
    await pdgExecutor.dispose();
  });

  test('reviews scope returns a typed review group and hit', () async {
    final result = await search.search('CG coefficients', SearchScope.reviews);
    expect(result.groups, isNotEmpty);
    final group = result.groups.firstWhere(
      (group) => group.kind == SearchGroupKind.review,
    );
    expect(group.hits, isNotEmpty);
    final hit = group.hits.first;
    expect(hit.kind, SearchGroupKind.review);
    expect(hit.reviewFile, 'rpp2026-rev-clebsch-gordan-coefs.pdf');
    expect(hit.reviewPage, 1);
    expect(hit.reason, SearchReason.reviewTitle);
    expect(hit.snippet, isNotNull);
    expect(hit.reviewSha256, isNotNull);
  });

  test('U2 keeps the figure-caption reason and page', () async {
    final result = await search.search(
      'hadronic cross sections',
      SearchScope.reviews,
    );
    final hit = result.groups
        .firstWhere((group) => group.kind == SearchGroupKind.review)
        .hits
        .first;
    expect(hit.reviewPage, 5);
    expect(hit.reason, SearchReason.reviewCaption);
  });

  test('a review failure does not drop all-scope results', () async {
    final isolated = SearchService(
      database,
      reviewSearch: _ThrowingReviewSearch(),
    );
    final result = await isolated.search('CG coefficients', SearchScope.all);
    expect(result.notice, 'degraded');
  });

  test('a degraded result is not cached across identical searches', () async {
    final flaky = _FlakyReviewSearch();
    final service = SearchService(database, reviewSearch: flaky);
    final first = await service.search('CG coefficients', SearchScope.reviews);
    expect(first.notice, 'unavailable');
    final second = await service.search('CG coefficients', SearchScope.reviews);
    expect(flaky.calls, 2);
    expect(second.groups, isNotEmpty);
  });

  test('note rail can opt out of review hits', () async {
    final result = await search.search(
      'CG coefficients',
      SearchScope.all,
      includeReviews: false,
    );
    expect(
      result.groups.where((group) => group.kind == SearchGroupKind.review),
      isEmpty,
    );
  });
}
