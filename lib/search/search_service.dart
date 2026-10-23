import 'package:flutter/foundation.dart';

import '../app/app_strings.dart';
import '../data/pdg_database.dart';
import '../domain/labels.dart';
import '../domain/models.dart';
import '../domain/reference_title.dart';
import '../notes/notes.dart';
import 'name_syntax.dart';
import 'review_search_service.dart';

enum SearchScope { all, particles, titles, decays, references, reviews, notes }

enum SearchGroupKind {
  identifier,
  particle,
  topic,
  decay,
  reference,
  text,
  review,
  note,
}

enum SearchReason {
  exactPdgid,
  exactName,
  commonAlias,
  namePrefix,
  nameContains,
  mcNumber,
  titleMatch,
  textMatch,
  reviewTitle,
  reviewHeading,
  reviewBody,
  reviewCaption,
  decayText,
  referenceIdentifier,
  referenceTitle,
}

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.pdgid,
    this.referenceId,
    this.reference,
    this.entry,
    this.particles = const [],
    this.reason = SearchReason.titleMatch,
    this.snippet,
    this.note,
    this.reviewFile,
    this.reviewPage,
    this.reviewHeading,
    this.reviewCaption,
    this.reviewMatchCount = 0,
    this.reviewSha256,
  });

  final SearchGroupKind kind;
  final String title;
  final String subtitle;
  final String? pdgid;
  final int? referenceId;
  final Reference? reference;
  final Entry? entry;
  final List<Particle> particles;
  final SearchReason reason;
  final String? snippet;
  final NoteRecord? note;

  /// Set when [kind] is [SearchGroupKind.review].  [reviewFile] is the PDG
  /// file name, [reviewPage] is a 1-based physical PDF page.
  final String? reviewFile;
  final int? reviewPage;
  final String? reviewHeading;
  final String? reviewCaption;
  final int reviewMatchCount;
  final String? reviewSha256;

  String get openPdgid => pdgid ?? entry?.pdgid ?? '';
}

class SearchGroup {
  const SearchGroup({
    required this.kind,
    required this.total,
    required this.hits,
    this.note,
  });

  final SearchGroupKind kind;
  final int total;
  final List<SearchHit> hits;
  final String? note;

  bool get isEmpty => hits.isEmpty;
}

class SearchResults {
  const SearchResults({required this.query, required this.groups, this.notice});

  final String query;
  final List<SearchGroup> groups;

  /// Non-fatal status shown above the groups, even when there are no hits.
  final String? notice;

  bool get isEmpty => groups.every((group) => group.hits.isEmpty);
  int get total => groups.fold(0, (sum, group) => sum + group.total);
}

class ResolvedName {
  const ResolvedName({
    required this.item,
    required this.chain,
    required this.direct,
    required this.mapped,
    required this.candidates,
  });

  final ItemRecord item;
  final List<ItemRecord> chain;
  final List<Particle> direct;
  final List<Particle> mapped;
  final List<Particle> candidates;

  Map<String, List<Particle>> get byListing {
    final result = <String, List<Particle>>{};
    for (final particle in candidates) {
      result.putIfAbsent(particle.pdgid, () => []).add(particle);
    }
    return result;
  }
}

class NameIndexMatch {
  NameIndexMatch(this.itemId, this.score, this.reason);

  final int itemId;
  final int score;
  final SearchReason reason;
}

/// In-memory index of the small name tables (3,270 items and 1,170 particle
/// rows). This is a derived index built from the verified snapshot; it never
/// edits source names. Physical resolution is kept as a list of candidates.
class NameIndex {
  NameIndex(this.db);

  final PdgDatabase db;
  final Map<int, ItemRecord> items = {};
  final Map<int, List<Particle>> particlesByItem = {};
  final Map<int, List<ItemEdge>> edgesByItem = {};
  final Map<String, List<int>> _keys = {};
  bool _loaded = false;
  Future<void>? _loadingFuture;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final inFlight = _loadingFuture;
    if (inFlight != null) return inFlight;
    final future = _load();
    _loadingFuture = future;
    try {
      await future;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      db.allItems(),
      db.allParticles(),
      db.allItemEdges(),
    ]);
    final itemList = results[0] as List<ItemRecord>;
    final particleList = results[1] as List<Particle>;
    final edgeList = results[2] as List<ItemEdge>;
    for (final item in itemList) {
      items[item.id] = item;
      _addKey(item.name, item.id);
    }
    for (final particle in particleList) {
      particlesByItem.putIfAbsent(particle.pdgitemId, () => []).add(particle);
      _addKey(particle.name, particle.pdgitemId);
    }
    for (final edge in edgeList) {
      edgesByItem.putIfAbsent(edge.pdgitemId, () => []).add(edge);
    }
    _loaded = true;
  }

  void _addKey(String name, int itemId) {
    final key = normalizeName(name).toLowerCase();
    if (key.isEmpty) return;
    final list = _keys.putIfAbsent(key, () => []);
    if (!list.contains(itemId)) list.add(itemId);
  }

  List<NameIndexMatch> match(String input) {
    final keys = nameQueryKeys(input);
    if (keys.isEmpty) return const [];
    final baseKey = normalizeName(input).toLowerCase();
    final matches = <int, NameIndexMatch>{};
    void offer(int itemId, int score, SearchReason reason) {
      final existing = matches[itemId];
      if (existing == null || score > existing.score) {
        matches[itemId] = NameIndexMatch(itemId, score, reason);
      }
    }

    for (final key in keys) {
      final viaAlias = key != baseKey;
      for (final itemId in _keys[key] ?? const <int>[]) {
        offer(
          itemId,
          viaAlias ? 95 : 100,
          viaAlias ? SearchReason.commonAlias : SearchReason.exactName,
        );
      }
      if (key.length < 2) continue;
      for (final entry in _keys.entries) {
        final nameKey = entry.key;
        if (nameKey == key) continue;
        if (nameKey.startsWith(key)) {
          for (final itemId in entry.value) {
            offer(
              itemId,
              viaAlias ? 80 : 85,
              viaAlias ? SearchReason.commonAlias : SearchReason.namePrefix,
            );
          }
        } else if (key.length >= 3 && nameKey.contains(key)) {
          for (final itemId in entry.value) {
            offer(
              itemId,
              viaAlias ? 55 : 60,
              viaAlias ? SearchReason.commonAlias : SearchReason.nameContains,
            );
          }
        }
      }
    }

    final result = matches.values.toList();
    result.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final typeA = _typeRank(items[a.itemId]?.itemType);
      final typeB = _typeRank(items[b.itemId]?.itemType);
      final type = typeB.compareTo(typeA);
      if (type != 0) return type;
      return a.itemId.compareTo(b.itemId);
    });
    return result;
  }

  static int _typeRank(String? type) => switch (type) {
    'P' => 4,
    'A' || 'W' || 'S' => 3,
    'G' => 2,
    'L' => 2,
    'I' => 1,
    'T' => 0,
    _ => 0,
  };

  ResolvedName resolve(int itemId) {
    final item = items[itemId];
    if (item == null) {
      throw StateError('Missing item $itemId');
    }
    final direct = particlesByItem[itemId] ?? const <Particle>[];
    final chain = <ItemRecord>[];
    final visited = <int>{itemId};
    final queue = <int>[itemId];
    final mapped = <Particle>[];
    final seenParticles = <int>{for (final particle in direct) particle.id};
    var depth = 0;
    while (queue.isNotEmpty && depth < 5) {
      final next = <int>[];
      for (final current in queue) {
        for (final edge in edgesByItem[current] ?? const <ItemEdge>[]) {
          if (!visited.add(edge.targetId)) continue;
          final target = items[edge.targetId];
          if (target != null) chain.add(target);
          for (final particle
              in particlesByItem[edge.targetId] ?? const <Particle>[]) {
            if (seenParticles.add(particle.id)) mapped.add(particle);
          }
          next.add(edge.targetId);
        }
      }
      queue
        ..clear()
        ..addAll(next);
      depth++;
    }
    final all = <Particle>[];
    final seen = <int>{};
    for (final particle in [...direct, ...mapped]) {
      if (seen.add(particle.id)) all.add(particle);
    }
    return ResolvedName(
      item: item,
      chain: List.unmodifiable(chain),
      direct: direct,
      mapped: mapped,
      candidates: all,
    );
  }
}

class SearchService {
  SearchService(
    this.db, {
    this.notes,
    this.notesChanges,
    this.reviewSearch,
    this.language = TextLang.zh,
  }) : names = NameIndex(db);

  final NotesStore? notes;
  final ReviewSearchService? reviewSearch;
  final ValueListenable<int>? notesChanges;
  TextLang language;

  TextLang get lang => language;

  set lang(TextLang value) {
    if (language == value) return;
    language = value;
    _cache.clear();
  }

  AppStrings get _strings => AppStrings(language);

  final PdgDatabase db;
  final NameIndex names;
  final Map<String, SearchResults> _cache = {};
  List<Reference>? _referenceTitleCache;

  /// Preloads the derived name index after the first frame. Safe to call more
  /// than once, and safe to race with a user search.
  Future<void> warmNameIndex() => names.ensureLoaded();
  static const int _cacheLimit = 24;

  Future<SearchResults> search(
    String rawQuery,
    SearchScope scope, {
    int limit = 25,
    bool includeReviews = true,
  }) async {
    final reviewState = reviewSearch == null
        ? 'none'
        : '${reviewSearch!.isReady}:${reviewSearch!.revision}';
    final key =
        '${scope.name}|$limit|$includeReviews|${notesChanges?.value ?? 0}|$reviewState|${rawQuery.trim()}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final result = await _searchUncached(
      rawQuery,
      scope,
      limit: limit,
      includeReviews: includeReviews,
    );
    // A degraded/unavailable review result must be retried on the next
    // submit; caching it under the same key would bypass the lazy loader.
    if (isCacheable(result)) {
      if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
      _cache[key] = result;
    }
    return result;
  }

  Future<SearchResults> _searchUncached(
    String rawQuery,
    SearchScope scope, {
    int limit = 25,
    bool includeReviews = true,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return SearchResults(query: query, groups: const []);
    final groups = <SearchGroup>[];
    final runNames = scope == SearchScope.all || scope == SearchScope.particles;
    final runTitles = scope == SearchScope.all || scope == SearchScope.titles;
    final runDecays = scope == SearchScope.all || scope == SearchScope.decays;
    final runReferences =
        scope == SearchScope.all || scope == SearchScope.references;
    final runNotes = scope == SearchScope.all || scope == SearchScope.notes;
    final runReviews =
        includeReviews &&
        (scope == SearchScope.all || scope == SearchScope.reviews);
    String? notice;
    // Loading the in-memory name index costs ~80 ms and is only needed for
    // particle-name lookups. A references-only search must not pay for it.
    if (runNames) await names.ensureLoaded();

    // Exact identifier is useful in every scope.
    if (scope != SearchScope.notes && looksLikePdgIdentifier(query)) {
      final entry = await db.entryByPdgid(query);
      if (entry != null) {
        groups.add(
          SearchGroup(
            kind: SearchGroupKind.identifier,
            total: 1,
            hits: [
              SearchHit(
                kind: SearchGroupKind.identifier,
                title: entry.description,
                subtitle:
                    '${entry.pdgid} · ${dataTypeInfo(entry.dataType).label(lang)}',
                pdgid: entry.pdgid,
                entry: entry,
                reason: SearchReason.exactPdgid,
              ),
            ],
          ),
        );
      }
    }

    final particlePdgids = <String>{};
    if (runNames) {
      final particleGroup = await _nameHits(query, limit);
      if (particleGroup != null) {
        groups.add(particleGroup);
        particlePdgids.addAll(particleGroup.hits.map((hit) => hit.pdgid ?? ''));
      }
      final mcidGroup = await _mcidHits(query, limit);
      if (mcidGroup != null) {
        particlePdgids.addAll(mcidGroup.hits.map((hit) => hit.pdgid ?? ''));
        if (particleGroup == null) {
          groups.add(mcidGroup);
        } else {
          final merged = SearchGroup(
            kind: SearchGroupKind.particle,
            total: particleGroup.total + mcidGroup.total,
            hits: [...particleGroup.hits, ...mcidGroup.hits],
            note: particleGroup.note,
          );
          groups
            ..remove(particleGroup)
            ..add(merged);
        }
      }
    }

    if (runTitles) {
      final topicGroup = await _titleHits(
        query,
        limit,
        decaysOnly: false,
        excludeDecays: true,
        excludePdgids: particlePdgids,
      );
      if (topicGroup != null) groups.add(topicGroup);
    }
    if (runDecays) {
      final decayGroup = await _titleHits(
        query,
        limit,
        decaysOnly: true,
        excludeDecays: false,
      );
      if (decayGroup != null) groups.add(decayGroup);
    }
    if (runReferences) {
      final referenceGroup = await _referenceHits(query, limit);
      if (referenceGroup != null) groups.add(referenceGroup);
    }
    if (runNotes) {
      final noteGroup = await _noteHits(query, limit);
      if (noteGroup != null) groups.add(noteGroup);
    }
    if (runTitles) {
      final textGroup = await _textHits(query, limit);
      if (textGroup != null) groups.add(textGroup);
    }
    if (runReviews && reviewSearch != null) {
      try {
        final result = await reviewSearch!.search(query, limit: limit);
        notice = result.notice;
        if (result.hits.isNotEmpty) {
          groups.add(
            SearchGroup(
              kind: SearchGroupKind.review,
              total: result.hits.length,
              hits: [
                for (final hit in result.hits)
                  SearchHit(
                    kind: SearchGroupKind.review,
                    title: hit.title,
                    subtitle: [
                      _strings.searchReviewPage(hit.page),
                      if (hit.heading.trim().isNotEmpty) hit.heading,
                    ].join(' · '),
                    reviewFile: hit.file,
                    reviewPage: hit.page,
                    reviewHeading: hit.heading,
                    reviewCaption: hit.caption,
                    reviewMatchCount: hit.matchCount,
                    reviewSha256: hit.sha256,
                    snippet: _reviewSnippet(switch (hit.matchField) {
                      'title' => hit.title,
                      'heading' => hit.heading,
                      _ => hit.caption,
                    }),
                    reason: _reviewReason(hit.matchField),
                  ),
              ],
            ),
          );
        }
      } catch (_) {
        // A broken review index must never drop the other search groups.
        notice ??= 'degraded';
      }
    }
    return SearchResults(query: query, groups: groups, notice: notice);
  }

  @visibleForTesting
  static bool isCacheable(SearchResults result) {
    return result.notice != 'unavailable' && result.notice != 'degraded';
  }

  static String? _reviewSnippet(String caption) {
    final text = caption.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  static SearchReason _reviewReason(String field) {
    return switch (field) {
      'caption' => SearchReason.reviewCaption,
      'heading' => SearchReason.reviewHeading,
      'title' => SearchReason.reviewTitle,
      _ => SearchReason.reviewBody,
    };
  }

  Future<SearchGroup?> _nameHits(String query, int limit) async {
    final matches = names.match(query);
    if (matches.isEmpty) return null;
    final byListing =
        <
          String,
          ({List<Particle> particles, SearchReason reason, ItemRecord item})
        >{};
    for (final match in matches.take(120)) {
      final resolved = names.resolve(match.itemId);
      if (resolved.candidates.isEmpty) continue;
      for (final entry in resolved.byListing.entries) {
        final existing = byListing[entry.key];
        if (existing == null) {
          byListing[entry.key] = (
            particles: entry.value,
            reason: match.reason,
            item: resolved.item,
          );
        }
      }
    }
    if (byListing.isEmpty) return null;
    final total = byListing.length;
    final listingEntries = await db.entriesByPdgids(byListing.keys.toList());
    final entryByPdgid = {
      for (final entry in listingEntries) entry.pdgid: entry,
    };
    final hits = <SearchHit>[];
    for (final entry in byListing.entries.take(limit)) {
      final listing = entryByPdgid[entry.key];
      final data = entry.value;
      final particleNames = data.particles
          .map((particle) => particle.name)
          .join(' / ');
      final preferred = listing?.description ?? entry.key;
      final kind = data.item.itemType == 'G' || data.item.itemType == 'L'
          ? _strings.searchKindCommonName
          : data.item.itemType == 'A' ||
                data.item.itemType == 'W' ||
                data.item.itemType == 'S'
          ? _strings.searchKindPdgAlias
          : _strings.searchKindParticleName;
      hits.add(
        SearchHit(
          kind: SearchGroupKind.particle,
          title: preferred,
          subtitle: '$particleNames · ${entry.key} · $kind',
          pdgid: entry.key,
          entry: listing,
          particles: data.particles,
          reason: data.reason,
        ),
      );
    }
    return SearchGroup(
      kind: SearchGroupKind.particle,
      total: total,
      hits: hits,
      note: total > hits.length
          ? _strings.searchShowingFirstCount(hits.length)
          : null,
    );
  }

  Future<SearchGroup?> _mcidHits(String query, int limit) async {
    // PDG Monte Carlo ids include negative values (antiparticles).
    if (!RegExp(r'^-?\d+$').hasMatch(query)) return null;
    final mcid = int.tryParse(query);
    if (mcid == null) return null;
    final particles = await db.particlesByMcid(mcid);
    if (particles.isEmpty) return null;
    final byListing = <String, List<Particle>>{};
    for (final particle in particles) {
      byListing.putIfAbsent(particle.pdgid, () => []).add(particle);
    }
    final entries = await db.entriesByPdgids(byListing.keys.toList());
    final entryByPdgid = {for (final entry in entries) entry.pdgid: entry};
    final hits = <SearchHit>[
      for (final entry in byListing.entries.take(limit))
        SearchHit(
          kind: SearchGroupKind.particle,
          title: entryByPdgid[entry.key]?.description ?? entry.key,
          subtitle:
              '${entry.value.map((particle) => particle.name).join(' / ')} · MC $mcid',
          pdgid: entry.key,
          entry: entryByPdgid[entry.key],
          particles: entry.value,
          reason: SearchReason.mcNumber,
        ),
    ];
    return SearchGroup(
      kind: SearchGroupKind.particle,
      total: byListing.length,
      hits: hits,
      note: byListing.length > hits.length
          ? _strings.searchShowingFirstCount(hits.length)
          : null,
    );
  }

  Future<SearchGroup?> _titleHits(
    String query,
    int limit, {
    required bool decaysOnly,
    required bool excludeDecays,
    Set<String> excludePdgids = const {},
  }) async {
    final entries =
        (await db.entriesByDescription(
              query,
              decaysOnly: decaysOnly,
              excludeDecays: excludeDecays,
              limit: limit,
            ))
            .where((entry) => !excludePdgids.contains(entry.pdgid))
            .toList(growable: false);
    if (entries.isEmpty) return null;
    final total = await db.countEntriesByDescription(
      query,
      decaysOnly: decaysOnly,
      excludeDecays: excludeDecays,
    );
    return SearchGroup(
      kind: decaysOnly ? SearchGroupKind.decay : SearchGroupKind.topic,
      total: total,
      hits: [
        for (final entry in entries)
          SearchHit(
            kind: decaysOnly ? SearchGroupKind.decay : SearchGroupKind.topic,
            title: entry.description,
            subtitle:
                '${entry.pdgid} · ${dataTypeInfo(entry.dataType).label(lang)}',
            pdgid: entry.pdgid,
            entry: entry,
            reason: decaysOnly
                ? SearchReason.decayText
                : SearchReason.titleMatch,
          ),
      ],
      note: total > entries.length
          ? _strings.searchShowingFirstCount(entries.length)
          : null,
    );
  }

  Future<SearchGroup?> _textHits(String query, int limit) async {
    final hits = await db.entriesByText(query, limit: limit);
    if (hits.isEmpty) return null;
    final total = await db.countEntriesByText(query);
    return SearchGroup(
      kind: SearchGroupKind.text,
      total: total,
      hits: [
        for (final hit in hits)
          SearchHit(
            kind: SearchGroupKind.text,
            title: hit.entry.description,
            subtitle: hit.entry.pdgid,
            pdgid: hit.entry.pdgid,
            entry: hit.entry,
            reason: SearchReason.textMatch,
            snippet: hit.text.length > 220
                ? '${hit.text.substring(0, 220)}…'
                : hit.text,
          ),
      ],
      note: total > hits.length
          ? _strings.searchShowingFirstCount(hits.length)
          : null,
    );
  }

  Future<SearchGroup?> _noteHits(String query, int limit) async {
    final store = notes;
    if (store == null) return null;
    final matches = await store.search(query, limit: limit);
    if (matches.isEmpty) return null;
    return SearchGroup(
      kind: SearchGroupKind.note,
      total: matches.length,
      hits: [
        for (final note in matches)
          SearchHit(
            kind: SearchGroupKind.note,
            title: note.title.trim().isEmpty
                ? (note.bodyPlain.trim().isEmpty
                      ? _strings.notesUntitled
                      : note.bodyPlain.trim())
                : note.title,
            subtitle: note.anchors.isEmpty
                ? '${_strings.notesTitle} · ${note.updatedAt.toLocal().toString().split('.').first}'
                : '${_strings.notesTitle} · ${note.anchors.first.targetLabel.trim().isEmpty ? note.anchors.first.targetId : note.anchors.first.targetLabel}',
            snippet: note.bodyPlain,
            note: note,
            reason: SearchReason.textMatch,
          ),
      ],
    );
  }

  Future<SearchGroup?> _referenceHits(String query, int limit) async {
    final year = int.tryParse(query);
    var refs = await db.searchReferences(
      query,
      limit: limit,
      year: year != null && year >= 1900 && year <= 2100 ? year : null,
    );
    if (refs.isEmpty && query.trim().isNotEmpty) {
      // Raw PDG titles contain MathML; a query such as `WZ` lives in separate
      // <mi> nodes and cannot match SQL LIKE. Match cleaned titles in Dart as
      // a fallback, then reuse the normal reference-hit rendering.
      final all = _referenceTitleCache ??= await db.allReferencesForTitleScan();
      final needle = query.toLowerCase();
      refs = [
        for (final ref in all)
          if ((year == null || year == ref.publicationYear) &&
              cleanReferenceTitle(ref.displayTitle)
                  .toLowerCase()
                  .contains(needle))
            ref,
      ].take(limit).toList(growable: false);
    }
    if (refs.isEmpty) return null;
    final counted = await db.countSearchReferences(
      query,
      year: year != null && year >= 1900 && year <= 2100 ? year : null,
    );
    final total = counted == 0 && refs.isNotEmpty ? refs.length : counted;
    return SearchGroup(
      kind: SearchGroupKind.reference,
      total: total,
      hits: [
        for (final ref in refs)
          SearchHit(
            kind: SearchGroupKind.reference,
            title: cleanReferenceTitle(ref.displayTitle),
            subtitle: [
              ref.documentId,
              if (ref.publicationYear != null) '${ref.publicationYear}',
              if (ref.publicationName.isNotEmpty) ref.publicationName,
            ].join(' · '),
            referenceId: ref.id,
            reference: ref,
            reason: SearchReason.referenceTitle,
          ),
      ],
      note: total > refs.length
          ? _strings.searchShowingFirstCount(refs.length)
          : null,
    );
  }
}
