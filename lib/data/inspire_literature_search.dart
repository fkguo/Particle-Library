import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/reference_title.dart';

/// One INSPIRE literature record returned by an online author/title search.
class InspireLiteratureHit {
  const InspireLiteratureHit({
    required this.recid,
    required this.title,
    required this.authors,
    required this.firstAuthor,
    required this.authorCount,
    required this.collaborations,
    required this.doi,
    required this.arxivId,
    required this.year,
    required this.journal,
    required this.citationCount,
    this.journalVolume = '',
    this.journalPage = '',
  });

  final int recid;
  final String title;
  final List<String> authors;
  final String firstAuthor;
  final int authorCount;
  final List<String> collaborations;
  final String doi;
  final String arxivId;
  final int? year;
  final String journal;
  final String journalVolume;
  final String journalPage;
  final int citationCount;

  String get inspireUrl => 'https://inspirehep.net/literature/$recid';

  /// The byline INSPIRE prints under a title: individual authors when the
  /// record lists them, otherwise the collaboration (collaboration-only
  /// papers have an empty author list but a collaboration entry).
  String get byline {
    if (authors.isNotEmpty) return authors.join(', ');
    final first = firstAuthor.trim();
    if (first.isNotEmpty) {
      return authorCount > 1 ? '$first et al.' : first;
    }
    return collaborations.map(_collaborationLabel).join(', ');
  }

  /// Byline for a compact result card: first five authors, or the
  /// collaboration when there are no individual authors.
  String get bylineShort {
    if (authors.isEmpty) return byline;
    final shown = authors.take(5).join(', ');
    return authors.length > 5 ? '$shown et al.' : shown;
  }

  static String _collaborationLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.toLowerCase().endsWith('collaboration')
        ? trimmed
        : '$trimmed Collaboration';
  }
}

class InspireLiteraturePage {
  const InspireLiteraturePage({required this.hits, required this.total});

  final List<InspireLiteratureHit> hits;
  final int total;
}

class InspireSearchException implements Exception {
  const InspireSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Explicit, user-triggered INSPIRE search. The local PDG snapshot has no
/// author column, so author searches must be online; title/journal queries
/// remain available offline in [PdgDatabase.searchReferences].
class InspireLiteratureSearchService {
  InspireLiteratureSearchService();

  final Map<String, InspireLiteraturePage> _cache = {};

  /// True when the input is already INSPIRE query syntax and must be sent
  /// verbatim instead of being wrapped as a natural-language author/title.
  static bool looksLikeInspireQuery(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return false;
    if (RegExp(
      r'(^|\s)(a|author|t|title|doi|arxiv|recid|cn|collaboration|reportnumber|fulltext|refersto|citedby)\s*:',
      caseSensitive: false,
    ).hasMatch(query)) {
      return true;
    }
    if (RegExp(r'^(a|t|cn)\s+\S', caseSensitive: false).hasMatch(query)) {
      return true;
    }
    if (RegExp(r'\b(and|or|not)\b', caseSensitive: false).hasMatch(query) &&
        query.contains(' ')) {
      return true;
    }
    return query.startsWith('(') || query.contains('->') || query.contains('"');
  }

  static const int maxPageSize = 1000;

  /// Fetches one page, newest/cited sort chosen by [sort] (`mostcited` or
  /// `mostrecent`). INSPIRE can return up to 10,000 results; the UI pages
  /// through them rather than truncating at 20.
  Future<InspireLiteraturePage> searchPage(
    String rawQuery, {
    int page = 1,
    int size = 50,
    String sort = 'mostcited',
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const InspireLiteraturePage(hits: [], total: 0);
    final normalizedPage = page < 1 ? 1 : page;
    final normalizedSize = size.clamp(1, maxPageSize);
    final normalizedSort = sort == 'mostrecent' ? 'mostrecent' : 'mostcited';
    final key = '$normalizedPage|$normalizedSize|$normalizedSort|$query';
    final cached = _cache[key];
    if (cached != null) return cached;
    final result = await _fetch(
      query,
      normalizedSize,
      page: normalizedPage,
      sort: normalizedSort,
    );
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[key] = result;
    return result;
  }

  /// Backwards-compatible list API used by tests and other callers.
  Future<List<InspireLiteratureHit>> search(
    String rawQuery, {
    int limit = 20,
  }) async {
    final page = await searchPage(rawQuery, size: limit);
    return page.hits;
  }

  Future<InspireLiteraturePage> _fetch(
    String query,
    int limit, {
    required int page,
    required String sort,
  }) async {
    final uri = Uri.https('inspirehep.net', '/api/literature', {
      'q': query,
      'size': '$limit',
      'page': '$page',
      'sort': sort,
      // Do not ask for the full author array: a single 2900-author
      // collaboration paper makes a 20-record page ~2 MB instead of ~34 KB.
      // `first_author` + `author_count` is enough for the result list.
      'fields':
          'titles,first_author,author_count,collaborations,dois,'
          'publication_info,arxiv_eprints,citation_count,control_number',
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Particle Library/0.1 (offline PDG reader; INSPIRE author search)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw InspireSearchException('INSPIRE 返回 HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const InspireSearchException('INSPIRE 返回了无法识别的数据。');
      }
      final hits = decoded['hits'];
      if (hits is! Map) {
        return const InspireLiteraturePage(hits: [], total: 0);
      }
      final items = hits['hits'];
      final totalRaw = hits['total'];
      final total = totalRaw is num
          ? totalRaw.toInt()
          : int.tryParse(totalRaw?.toString() ?? '') ?? 0;
      final parsed = <InspireLiteratureHit>[
        if (items is List)
          for (final item in items)
            if (_parse(item) case final InspireLiteratureHit hit) hit,
      ];
      return InspireLiteraturePage(hits: parsed, total: total);
    } on TimeoutException {
      throw const InspireSearchException('联网查询 INSPIRE 超时。');
    } on SocketException {
      throw const InspireSearchException('无法连接 INSPIRE。');
    } on FormatException {
      throw const InspireSearchException('INSPIRE 返回的数据无法解析。');
    } on InspireSearchException {
      rethrow;
    } catch (error) {
      throw InspireSearchException('INSPIRE 查询失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  /// INSPIRE often returns the same title from several sources: APS may give
  /// raw MathML while arXiv gives a clean LaTeX title. Prefer the latter, then
  /// fall back to stripping MathML/HTML so raw tags never reach the UI.
  String _displayTitle(Object? rawTitles) {
    if (rawTitles is! List || rawTitles.isEmpty) return '';
    final candidates = <({String title, String source})>[];
    for (final raw in rawTitles) {
      if (raw is! Map) continue;
      final title = raw['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      candidates.add((
        title: title,
        source: (raw['source']?.toString() ?? '').toLowerCase(),
      ));
    }
    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => _titleScore(b).compareTo(_titleScore(a)));
    return _stripMarkup(candidates.first.title);
  }

  static int _titleScore(({String title, String source}) candidate) {
    var score = 0;
    if (candidate.source == 'arxiv') score += 8;
    if (candidate.title.contains(r'$')) score += 5;
    if (!candidate.title.contains('<')) score += 4;
    if (candidate.title.contains('<math')) score -= 6;
    return score;
  }

  static String _stripMarkup(String title) => cleanReferenceTitle(title);

  InspireLiteratureHit? _parse(Object? raw) {
    if (raw is! Map) return null;
    final metadata = raw['metadata'];
    if (metadata is! Map) return null;
    final control = metadata['control_number'];
    final recid = control is num
        ? control.toInt()
        : int.tryParse(control?.toString() ?? '');
    if (recid == null) return null;
    final titles = metadata['titles'];
    final title = _displayTitle(titles);
    final authors = <String>[];
    final rawAuthors = metadata['authors'];
    if (rawAuthors is List) {
      for (final author in rawAuthors) {
        if (author is! Map) continue;
        final name =
            author['full_name']?.toString() ?? author['name']?.toString() ?? '';
        if (name.isNotEmpty) authors.add(name);
      }
    }
    final collaborations = <String>[];
    final rawCollaborations = metadata['collaborations'];
    if (rawCollaborations is List) {
      for (final collaboration in rawCollaborations) {
        final value = collaboration is Map
            ? collaboration['value']?.toString() ?? ''
            : collaboration?.toString() ?? '';
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) collaborations.add(trimmed);
      }
    }
    final firstAuthor = metadata['first_author'] is Map
        ? ((metadata['first_author'] as Map)['full_name']?.toString() ?? '')
        : '';
    final rawCount = metadata['author_count'];
    final authorCount = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '') ?? 0;
    final dois = metadata['dois'];
    final doi = dois is List && dois.isNotEmpty && dois.first is Map
        ? (dois.first as Map)['value']?.toString() ?? ''
        : '';
    final arxiv = metadata['arxiv_eprints'];
    final arxivId = arxiv is List && arxiv.isNotEmpty && arxiv.first is Map
        ? (arxiv.first as Map)['value']?.toString() ?? ''
        : '';
    final pubInfo = metadata['publication_info'];
    int? year;
    var journal = '';
    var journalVolume = '';
    var journalPage = '';
    if (pubInfo is List) {
      for (final info in pubInfo) {
        if (info is! Map) continue;
        final parsedYear = info['year'];
        if (year == null && parsedYear is num) year = parsedYear.toInt();
        final parsedJournal = info['journal_title']?.toString().trim() ?? '';
        if (journal.isEmpty && parsedJournal.isNotEmpty) {
          journal = parsedJournal;
        }
        if (journalVolume.isEmpty) {
          journalVolume = info['journal_volume']?.toString().trim() ?? '';
        }
        if (journalPage.isEmpty) {
          final pageStart = info['page_start']?.toString().trim() ?? '';
          final pageEnd = info['page_end']?.toString().trim() ?? '';
          final artid = info['artid']?.toString().trim() ?? '';
          if (artid.isNotEmpty) {
            journalPage = artid;
          } else if (pageStart.isNotEmpty) {
            journalPage = pageEnd.isEmpty || pageEnd == pageStart
                ? pageStart
                : '$pageStart-$pageEnd';
          }
        }
      }
    }
    final citations = metadata['citation_count'];
    return InspireLiteratureHit(
      recid: recid,
      title: title.isEmpty ? '(untitled INSPIRE record)' : title,
      authors: authors,
      firstAuthor: firstAuthor,
      authorCount: authorCount,
      collaborations: collaborations,
      doi: doi,
      arxivId: arxivId,
      year: year,
      journal: journal,
      journalVolume: journalVolume,
      journalPage: journalPage,
      citationCount: citations is num ? citations.toInt() : 0,
    );
  }
}

/// Parses one INSPIRE API hit. Exposed for tests; the service uses the same
/// code path.
InspireLiteratureHit? parseInspireLiteratureHit(Object? raw) =>
    InspireLiteratureSearchService()._parse(raw);
