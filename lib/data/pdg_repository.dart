import '../domain/filters.dart';
import '../domain/labels.dart';
import '../domain/models.dart';
import '../domain/views.dart';
import 'pdg_database.dart';

/// Composes the narrow database queries into the complete data needed by one
/// screen. Nothing here invents physical links: the directory tree, mappings
/// and measurement attachment sets come from the source rows.
class PdgRepository {
  PdgRepository(this.db);

  final PdgDatabase db;

  String get currentEdition => db.currentEdition;
  String get snapshotHash => db.snapshotHash;
  SnapshotInfo get info => db.info;

  Future<Entry> requireEntry(String pdgid) => db.requireEntryByPdgid(pdgid);

  Future<ParticleView> loadParticle(Entry entry) async {
    final results = await Future.wait([
      db.particlesForEntry(entry.id),
      db.ancestors(entry.id),
      db.descendants(entry.id),
      db.referenceCountForSubtree(entry.id),
    ]);
    final particles = results[0] as List<Particle>;
    final ancestors = results[1] as List<Entry>;
    final descendants = results[2] as List<Entry>;
    final referenceCount = results[3] as int;
    final ids = {
      for (final row in ancestors) row.id,
      for (final row in descendants) row.id,
    }.toList(growable: false);
    final textsAndSummaries = await Future.wait([
      db.textsForEntries(ids),
      db.currentSummariesForEntries(ids),
      db.summaryCountsForEntries(ids, edition: currentEdition),
      db.measurementCountsForEntries(ids),
    ]);
    final texts = textsAndSummaries[0] as List<SectionText>;
    final summaries = textsAndSummaries[1] as List<Summary>;
    final summaryCounts = textsAndSummaries[2] as Map<int, int>;
    final measurementCounts = textsAndSummaries[3] as Map<int, int>;
    final byEntry = <int, List<Summary>>{};
    for (final row in summaries) {
      byEntry.putIfAbsent(row.pdgidId, () => []).add(row);
    }
    return ParticleView(
      entry: entry,
      particles: particles,
      ancestors: ancestors,
      descendants: descendants,
      summariesByEntry: byEntry,
      summaryCounts: summaryCounts,
      measurementCounts: measurementCounts,
      texts: texts,
      referenceCount: referenceCount,
      currentEdition: currentEdition,
    );
  }

  Future<SeriesView> loadSeries(Entry entry) async {
    final results = await Future.wait([
      db.ancestors(entry.id),
      db.summariesForEntry(entry.id),
      db.footnotesForPdgid(entry.pdgid),
      db.relatedSources(entry.id),
      db.directMeasurementCount(entry.id),
    ]);
    final ancestors = results[0] as List<Entry>;
    final summaries = results[1] as List<Summary>;
    final footnotes = results[2] as List<Footnote>;
    final relatedSources = results[3] as List<RelatedQuantity>;
    final directMeasurementCount = results[4] as int;
    final ids = [for (final row in ancestors) row.id, entry.id];
    final texts = await db.textsForEntries(ids);
    final currentSummaries = summaries
        .where((row) => row.edition == currentEdition)
        .toList(growable: false);
    final parent = ancestors.isEmpty ? null : ancestors.last;
    final siblings = parent == null
        ? const <Entry>[]
        : (await db.children(parent.id))
              .where((row) => row.id != entry.id)
              .take(10)
              .toList(growable: false);
    return SeriesView(
      entry: entry,
      ancestors: ancestors,
      texts: texts,
      summaries: summaries,
      currentSummaries: currentSummaries,
      footnotes: footnotes,
      relatedSources: relatedSources,
      directMeasurementCount: directMeasurementCount,
      currentEdition: currentEdition,
      siblings: siblings,
    );
  }

  Future<ModeView> loadMode(Entry entry) async {
    final results = await Future.wait([
      db.ancestors(entry.id),
      db.decayTokens(entry.id),
      db.relatedQuantities(entry.id),
      db.children(entry.id),
      db.summariesForEntry(entry.id),
      db.footnotesForPdgid(entry.pdgid),
      db.directMeasurementCount(entry.id),
    ]);
    final ancestors = results[0] as List<Entry>;
    final tokens = results[1] as List<DecayToken>;
    final related = results[2] as List<RelatedQuantity>;
    final children = results[3] as List<Entry>;
    final summaries = results[4] as List<Summary>;
    final footnotes = results[5] as List<Footnote>;
    final directMeasurementCount = results[6] as int;
    final ids = [for (final row in ancestors) row.id, entry.id];
    final texts = await db.textsForEntries(ids);
    final itemIds = {for (final token in tokens) token.pdgitemId}
        .toList(growable: false);
    final resolved = await db.resolveItems(itemIds);
    final resolutions = <int, ItemResolution>{
      for (var i = 0; i < itemIds.length; i++) itemIds[i]: resolved[i],
    };
    final currentSummaries = summaries
        .where((row) => row.edition == currentEdition)
        .toList(growable: false);
    return ModeView(
      entry: entry,
      ancestors: ancestors,
      texts: texts,
      tokens: tokens,
      resolutions: resolutions,
      related: related,
      children: children,
      summaries: summaries,
      currentSummaries: currentSummaries,
      footnotes: footnotes,
      directMeasurementCount: directMeasurementCount,
      currentEdition: currentEdition,
    );
  }

  Future<EntryView> loadEntry(Entry entry) async {
    final results = await Future.wait([
      db.ancestors(entry.id),
      db.particlesForEntry(entry.id),
      db.children(entry.id),
      db.summariesForEntry(entry.id, edition: currentEdition),
      db.directMeasurementCount(entry.id),
    ]);
    final ancestors = results[0] as List<Entry>;
    final particles = results[1] as List<Particle>;
    final children = results[2] as List<Entry>;
    final currentSummaries = results[3] as List<Summary>;
    final measurementCount = results[4] as int;
    final ids = [for (final row in ancestors) row.id, entry.id];
    final childIds = [for (final row in children) row.id];
    final allSummaries = await db.currentSummariesForEntries([
      ...ids,
      ...childIds,
    ]);
    final byEntry = <int, List<Summary>>{};
    for (final row in allSummaries) {
      byEntry.putIfAbsent(row.pdgidId, () => []).add(row);
    }
    final texts = await db.textsForEntries(ids);
    return EntryView(
      entry: entry,
      ancestors: ancestors,
      particles: particles,
      children: children,
      texts: texts,
      currentSummaries: currentSummaries,
      currentSummaryCount: currentSummaries.length,
      measurementCount: measurementCount,
      currentEdition: currentEdition,
      summariesByEntry: byEntry,
    );
  }

  Future<bool> isPropertySeries(Entry entry) async {
    if (isParticleType(entry.dataType) ||
        isDecayType(entry.dataType) ||
        isSectionType(entry.dataType) ||
        isSearchType(entry.dataType)) {
      return false;
    }
    const propertyTypes = {
      'M',
      'G',
      'T',
      'D',
      'BR',
      'g',
      'e',
      'm',
      'v',
      'f',
      's',
      'c',
      'd',
    };
    if (propertyTypes.contains(entry.dataType)) return true;
    final summaryCount =
        (await db.summaryCountsForEntries([
          entry.id,
        ], edition: currentEdition))[entry.id] ??
        0;
    if (summaryCount > 0) return true;
    return (await db.directMeasurementCount(entry.id)) > 0;
  }

  Future<MeasurementPage> measurements(
    Entry entry, {
    MeasurementCursor? cursor,
    MeasurementFilter filter = const MeasurementFilter(),
    int pageSize = 50,
  }) => db.measurementsPage(
    entry.id,
    entry.pdgid,
    cursor: cursor,
    filter: filter,
    pageSize: pageSize,
  );

  Future<ReferenceListPage> referencesForSubtree(
    Entry entry, {
    int limit = 50,
    int offset = 0,
  }) => db.referencesForSubtree(entry.id, limit: limit, offset: offset);

  Future<List<ReferenceSeriesGroup>> referenceSeriesGroups(int referenceId) =>
      db.referenceSeriesGroups(referenceId);

  Future<List<MeasurementBundle>> measurementsForReferenceSeries(
    int referenceId,
    int entryId, {
    int limit = 50,
  }) => db.measurementsForReferenceSeries(referenceId, entryId, limit: limit);

  Future<CatalogData> catalog() async {
    final roots = await db.catalogRoots();
    final particles = await db.particlesForEntries([
      for (final root in roots) root.entry.id,
    ]);
    return CatalogData(roots: roots, particlesByEntry: particles);
  }
}

/// Catalog roots plus the particle identities needed by their compact rows.
class CatalogData {
  const CatalogData({required this.roots, required this.particlesByEntry});

  final List<CatalogRoot> roots;
  final Map<int, List<Particle>> particlesByEntry;

  List<Particle> particlesFor(CatalogRoot root) =>
      particlesByEntry[root.entry.id] ?? const <Particle>[];
}
