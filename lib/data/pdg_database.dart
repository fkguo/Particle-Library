import '../core/contract.dart';
import '../core/errors.dart';
import '../domain/filters.dart';
import '../domain/models.dart';
import 'sql_executor.dart';

/// Read-only access to one verified pdgall snapshot.
///
/// Every method is asynchronous; SQL runs in the background connection. SQL is
/// fixed in this file (never built from user text), user values are bound as
/// parameters, and list arguments are chunked to stay within SQLite's parameter
/// limits. Empty child lists are successful results; a missing object throws
/// [NotFoundException].
class PdgDatabase {
  PdgDatabase._(
    this.executor,
    this.snapshotHash,
    this.info,
    this.editions,
    this._docs,
  );

  final SqlExecutor executor;
  final String snapshotHash;
  final SnapshotInfo info;
  final List<String> editions;
  final Map<String, DocRecord> _docs;

  String get currentEdition => info.edition ?? SnapshotContract.expectedEdition;

  /// All editions present in the snapshot. The scan is deliberately lazy; UI
  /// paths use series-level edition data or [currentEdition].
  Future<List<String>> loadEditions() async {
    final rows = await executor.select(
      'SELECT DISTINCT edition FROM pdgdata WHERE edition IS NOT NULL ORDER BY edition DESC',
    );
    return [for (final row in rows) asString(row['edition'])!];
  }

  static Future<PdgDatabase> open(
    SqlExecutor executor, {
    required String snapshotHash,
    bool validateSchema = true,
    bool verifyIntegrity = true,
  }) async {
    final db = PdgDatabase._(
      executor,
      snapshotHash,
      SnapshotInfo({}),
      const [],
      {},
    );
    if (validateSchema) {
      await db._validateSchema(verifyIntegrity: verifyIntegrity);
    }
    final infoRows = await executor.select('SELECT * FROM pdginfo ORDER BY id');
    final info = SnapshotInfo.fromRows(infoRows);
    if (info.schemaVersion != SnapshotContract.expectedSchemaVersion) {
      throw SnapshotContract.schemaError(
        'schema_version=${info.schemaVersion}, expected ${SnapshotContract.expectedSchemaVersion}',
      );
    }
    if (info.edition == null || info.edition!.isEmpty) {
      throw SnapshotContract.schemaError('pdginfo 缺少 edition。');
    }
    final docRows = await executor.select('SELECT * FROM pdgdoc ORDER BY id');
    final docs = <String, DocRecord>{};
    for (final row in docRows) {
      final record = DocRecord(row);
      docs[_docKey(record.tableName, record.columnName, record.value)] = record;
    }
    // Editions are only needed by diagnostics/tests; a DISTINCT scan over the
    // full pdgdata table is not on the startup path.
    return PdgDatabase._(executor, snapshotHash, info, const <String>[], docs);
  }

  static String _docKey(String table, String column, String? value) =>
      '${table.toUpperCase()}.${column.toUpperCase()}|${value ?? ''}';

  DocRecord? docFor(String table, String column, String? value) =>
      _docs[_docKey(table, column, value)];

  List<DocRecord> docsForTable(String table) => _docs.values
      .where((doc) => doc.tableName.toUpperCase() == table.toUpperCase())
      .toList(growable: false);

  List<DocRecord> get allDocs {
    final docs = _docs.values.toList();
    docs.sort((a, b) {
      final table = a.tableName.compareTo(b.tableName);
      if (table != 0) return table;
      final column = a.columnName.compareTo(b.columnName);
      if (column != 0) return column;
      return (a.value ?? '').compareTo(b.value ?? '');
    });
    return docs;
  }

  Future<void> _validateSchema({bool verifyIntegrity = true}) async {
    final tableRows = await executor.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tables = {for (final row in tableRows) asString(row['name']) ?? ''};
    for (final required in SnapshotContract.requiredSchema.keys) {
      if (!tables.contains(required)) {
        throw SnapshotContract.schemaError('缺少表 $required');
      }
    }
    for (final entry in SnapshotContract.requiredSchema.entries) {
      final infoRows = await executor.select('PRAGMA table_info(${entry.key})');
      final columns = {for (final row in infoRows) asString(row['name']) ?? ''};
      final missing = entry.value.difference(columns);
      if (missing.isNotEmpty) {
        throw SnapshotContract.schemaError(
          '表 ${entry.key} 缺少字段 ${missing.join(', ')}',
        );
      }
    }
    if (!verifyIntegrity) return;
    final check = await executor.select('PRAGMA quick_check');
    if (check.isNotEmpty) {
      final first = check.first.values.first;
      if (first != 'ok') {
        throw AppException(
          AppErrorCode.corruptDatabase,
          '数据库完整性检查未通过。',
          detail: '$first',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Entries, catalog and section text
  // ---------------------------------------------------------------------------

  Future<Entry?> entryById(int id) async {
    final rows = await executor.select('SELECT * FROM pdgid WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : Entry(rows.first);
  }

  Future<Entry?> entryByPdgid(String pdgid) async {
    final exact = await executor.select('SELECT * FROM pdgid WHERE pdgid = ?', [
      pdgid,
    ]);
    if (exact.isNotEmpty) return Entry(exact.first);
    final insensitive = await executor.select(
      'SELECT * FROM pdgid WHERE pdgid = ? COLLATE NOCASE',
      [pdgid],
    );
    return insensitive.isEmpty ? null : Entry(insensitive.first);
  }

  Future<Entry> requireEntryByPdgid(String pdgid) async {
    final entry = await entryByPdgid(pdgid);
    if (entry == null) {
      throw NotFoundException('当前快照未收录条目 $pdgid。');
    }
    return entry;
  }

  Future<List<Entry>> children(int entryId) async {
    final rows = await executor.select(
      'SELECT * FROM pdgid WHERE parent_id = ? ORDER BY sort, id',
      [entryId],
    );
    return [for (final row in rows) Entry(row)];
  }

  Future<List<Entry>> ancestors(int entryId) async {
    final rows = await executor.select(
      '''
      WITH RECURSIVE anc(id, depth) AS (
        SELECT parent_id, 1 FROM pdgid WHERE id = ? AND parent_id IS NOT NULL
        UNION ALL
        SELECT p.parent_id, a.depth + 1
          FROM pdgid p JOIN anc a ON p.id = a.id
         WHERE p.parent_id IS NOT NULL AND a.depth < 40
      )
      SELECT i.*, a.depth AS ancestor_depth
        FROM anc a JOIN pdgid i ON i.id = a.id
       ORDER BY a.depth DESC
    ''',
      [entryId],
    );
    return [
      for (final row in rows)
        Entry({
          for (final e in row.entries)
            if (e.key != 'ancestor_depth') e.key: e.value,
        }),
    ];
  }

  /// All descendants including [entryId], depth-first in source order.
  Future<List<Entry>> descendants(int entryId, {int maxDepth = 32}) async {
    final rows = await executor.select(
      '''
      WITH RECURSIVE d(id, depth) AS (
        SELECT id, 0 FROM pdgid WHERE id = ?
        UNION ALL
        SELECT p.id, d.depth + 1
          FROM pdgid p JOIN d ON p.parent_id = d.id
         WHERE d.depth < $maxDepth
      )
      SELECT i.*
        FROM d JOIN pdgid i ON i.id = d.id
       ORDER BY d.depth, i.sort, i.id
    ''',
      [entryId],
    );
    return [for (final row in rows) Entry(row)];
  }

  Future<int> childCount(int entryId) async {
    final rows = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgid WHERE parent_id = ?',
      [entryId],
    );
    return asInt(rows.first['n']) ?? 0;
  }

  Future<List<Entry>> roots() async {
    final rows = await executor.select(
      'SELECT * FROM pdgid WHERE parent_id IS NULL ORDER BY sort, id',
    );
    return [for (final row in rows) Entry(row)];
  }

  Future<List<CatalogRoot>> catalogRoots() async {
    final rows = await executor.select('''
      SELECT r.*,
             (SELECT COUNT(*) FROM pdgid c WHERE c.parent_id = r.id) AS child_count,
             (SELECT COUNT(*) FROM pdgparticle p WHERE p.pdgid_id = r.id) AS particle_count,
             (EXISTS (SELECT 1 FROM pdgid c WHERE c.parent_id = r.id)
               OR EXISTS (SELECT 1 FROM pdgparticle p WHERE p.pdgid_id = r.id)
               OR EXISTS (SELECT 1 FROM pdgtext t WHERE t.pdgid_id = r.id)
               OR EXISTS (SELECT 1 FROM pdgmeasurement m WHERE m.pdgid_id = r.id)
               OR EXISTS (SELECT 1 FROM pdgdecay d WHERE d.pdgid_id = r.id)) AS has_content
        FROM pdgid r
       WHERE r.parent_id IS NULL
       ORDER BY r.sort, r.id
    ''');
    return [
      for (final row in rows)
        CatalogRoot(
          Entry(row),
          asInt(row['child_count']) ?? 0,
          asInt(row['particle_count']) ?? 0,
          hasContent: (asInt(row['has_content']) ?? 0) != 0,
        ),
    ];
  }

  Future<List<SectionText>> textsForEntries(List<int> entryIds) async {
    final result = <SectionText>[];
    for (final chunk in _chunk(entryIds, 400)) {
      final rows = await executor.select('''
        SELECT * FROM pdgtext
         WHERE pdgid_id IN (${_placeholders(chunk.length)})
         ORDER BY pdgid_id, sort, id
      ''', chunk);
      result.addAll([for (final row in rows) SectionText(row)]);
    }
    return result;
  }

  Future<List<SectionText>> textsForPdgid(String pdgid) async {
    final rows = await executor.select(
      'SELECT * FROM pdgtext WHERE pdgid = ? ORDER BY sort, id',
      [pdgid],
    );
    return [for (final row in rows) SectionText(row)];
  }

  Future<List<Footnote>> footnotesForPdgid(String pdgid) async {
    final rows = await executor.select(
      'SELECT * FROM pdgfootnote WHERE pdgid = ? ORDER BY footnote_index, id',
      [pdgid],
    );
    return [for (final row in rows) Footnote(row)];
  }

  // ---------------------------------------------------------------------------
  // Particles and name items
  // ---------------------------------------------------------------------------

  Future<List<Particle>> particlesForEntry(int entryId) async {
    final rows = await executor.select(
      'SELECT * FROM pdgparticle WHERE pdgid_id = ? ORDER BY id',
      [entryId],
    );
    return [for (final row in rows) Particle(row)];
  }

  Future<List<Particle>> particlesForItem(int itemId) async {
    final rows = await executor.select(
      'SELECT * FROM pdgparticle WHERE pdgitem_id = ? ORDER BY id',
      [itemId],
    );
    return [for (final row in rows) Particle(row)];
  }

  Future<List<Entry>> entriesByPdgids(List<String> pdgids) async {
    final result = <Entry>[];
    for (final chunk in _chunk(pdgids, 400)) {
      final rows = await executor.select(
        'SELECT * FROM pdgid WHERE pdgid IN (${_placeholders(chunk.length)})',
        chunk,
      );
      result.addAll([for (final row in rows) Entry(row)]);
    }
    return result;
  }

  Future<List<Particle>> particlesByMcid(int mcid) async {
    final rows = await executor.select(
      'SELECT * FROM pdgparticle WHERE mcid = ? ORDER BY id',
      [mcid],
    );
    return [for (final row in rows) Particle(row)];
  }

  Future<ItemRecord?> itemById(int itemId) async {
    final rows = await executor.select('SELECT * FROM pdgitem WHERE id = ?', [
      itemId,
    ]);
    return rows.isEmpty ? null : ItemRecord(rows.first);
  }

  Future<ItemRecord?> itemByName(String name) async {
    final rows = await executor.select('SELECT * FROM pdgitem WHERE name = ?', [
      name,
    ]);
    return rows.isEmpty ? null : ItemRecord(rows.first);
  }

  Future<List<ItemRecord>> allItems() async {
    final rows = await executor.select('SELECT * FROM pdgitem ORDER BY id');
    return [for (final row in rows) ItemRecord(row)];
  }

  Future<List<Particle>> allParticles() async {
    final rows = await executor.select('SELECT * FROM pdgparticle ORDER BY id');
    return [for (final row in rows) Particle(row)];
  }

  Future<List<ItemEdge>> allItemEdges() async {
    final rows = await executor.select('SELECT * FROM pdgitem_map ORDER BY id');
    return [for (final row in rows) ItemEdge(row)];
  }

  Future<List<ItemEdge>> itemEdges(int itemId) async {
    final rows = await executor.select(
      'SELECT * FROM pdgitem_map WHERE pdgitem_id = ? ORDER BY sort, id',
      [itemId],
    );
    return [for (final row in rows) ItemEdge(row)];
  }

  Future<ItemResolution> resolveItem(int itemId) async {
    final item = await itemById(itemId);
    if (item == null) {
      throw NotFoundException('当前快照未收录名称项 $itemId。');
    }
    final direct = await particlesForItem(itemId);
    final chainRows = await executor.select(
      '''
      WITH RECURSIVE chain(item_id, depth) AS (
        SELECT ?, 0
        UNION ALL
        SELECT m.target_id, c.depth + 1
          FROM pdgitem_map m JOIN chain c ON m.pdgitem_id = c.item_id
         WHERE c.depth < 5
      )
      SELECT i.*, MIN(c.depth) AS chain_depth
        FROM chain c JOIN pdgitem i ON i.id = c.item_id
       GROUP BY i.id
       ORDER BY chain_depth, i.id
    ''',
      [itemId],
    );
    final chain = [
      for (final row in chainRows)
        ItemRecord({
          for (final e in row.entries)
            if (e.key != 'chain_depth') e.key: e.value,
        }),
    ];
    final mapped = <Particle>[];
    final seenParticleIds = <int>{for (final particle in direct) particle.id};
    for (final record in chain) {
      if (record.id == itemId) continue;
      final particles = await particlesForItem(record.id);
      for (final particle in particles) {
        if (seenParticleIds.add(particle.id)) mapped.add(particle);
      }
    }
    final all = <Particle>[];
    final seen = <int>{};
    for (final particle in [...direct, ...mapped]) {
      if (seen.add(particle.id)) all.add(particle);
    }
    final listings = {for (final particle in all) particle.pdgid};
    return ItemResolution(
      item: item,
      chain: chain,
      directParticles: direct,
      mappedParticles: mapped,
      candidates: all,
      listings: listings,
    );
  }

  /// Resolves a whole Mode page with a fixed number of SQL statements:
  /// items, direct particles, recursive chains and chain particles. This is
  /// intentionally not a `resolveItem` loop.
  Future<List<ItemResolution>> resolveItems(List<int> itemIds) async {
    if (itemIds.isEmpty) return const [];
    final ids = itemIds.toSet().toList();
    final itemRows = await executor.select(
      'SELECT * FROM pdgitem WHERE id IN (${_placeholders(ids.length)})',
      ids,
    );
    final items = {
      for (final row in itemRows) asInt(row['id'])!: ItemRecord(row),
    };
    for (final id in ids) {
      if (!items.containsKey(id)) {
        throw NotFoundException('当前快照未收录名称项 $id。');
      }
    }

    final directRows = await executor.select(
      'SELECT * FROM pdgparticle WHERE pdgitem_id IN (${_placeholders(ids.length)}) ORDER BY pdgitem_id, id',
      ids,
    );
    final directByItem = <int, List<Particle>>{};
    for (final row in directRows) {
      final itemId = asInt(row['pdgitem_id'])!;
      directByItem.putIfAbsent(itemId, () => []).add(Particle(row));
    }

    final chainRows = await executor.select('''
      WITH RECURSIVE chain(root_id, item_id, depth) AS (
        SELECT id, id, 0 FROM pdgitem
         WHERE id IN (${_placeholders(ids.length)})
        UNION ALL
        SELECT c.root_id, m.target_id, c.depth + 1
          FROM chain c JOIN pdgitem_map m ON m.pdgitem_id = c.item_id
         WHERE c.depth < 5
      )
      SELECT c.root_id, i.*, MIN(c.depth) AS chain_depth
        FROM chain c JOIN pdgitem i ON i.id = c.item_id
       GROUP BY c.root_id, i.id
       ORDER BY c.root_id, chain_depth, i.id
    ''', ids);
    final chainByRoot = <int, List<ItemRecord>>{};
    final chainIds = <int>{};
    for (final row in chainRows) {
      final root = asInt(row['root_id'])!;
      final item = ItemRecord({
        for (final e in row.entries)
          if (e.key != 'chain_depth' && e.key != 'root_id') e.key: e.value,
      });
      chainByRoot.putIfAbsent(root, () => []).add(item);
      chainIds.add(item.id);
    }

    final allParticleRows = await executor.select(
      'SELECT * FROM pdgparticle WHERE pdgitem_id IN (${_placeholders(chainIds.length)}) ORDER BY pdgitem_id, id',
      chainIds.toList(),
    );
    final particlesByItem = <int, List<Particle>>{};
    for (final row in allParticleRows) {
      final itemId = asInt(row['pdgitem_id'])!;
      particlesByItem.putIfAbsent(itemId, () => []).add(Particle(row));
    }

    return [
      for (final id in ids)
        _resolutionFromBatch(
          id,
          items[id]!,
          directByItem[id] ?? const [],
          chainByRoot[id] ?? const [],
          particlesByItem,
        ),
    ];
  }

  ItemResolution _resolutionFromBatch(
    int itemId,
    ItemRecord item,
    List<Particle> direct,
    List<ItemRecord> chain,
    Map<int, List<Particle>> particlesByItem,
  ) {
    final mapped = <Particle>[];
    final seen = <int>{for (final particle in direct) particle.id};
    for (final record in chain) {
      if (record.id == itemId) continue;
      for (final particle in particlesByItem[record.id] ?? const <Particle>[]) {
        if (seen.add(particle.id)) mapped.add(particle);
      }
    }
    final all = <Particle>[];
    final seenAll = <int>{};
    for (final particle in [...direct, ...mapped]) {
      if (seenAll.add(particle.id)) all.add(particle);
    }
    return ItemResolution(
      item: item,
      chain: chain,
      directParticles: direct,
      mappedParticles: mapped,
      candidates: all,
      listings: {for (final particle in all) particle.pdgid},
    );
  }

  // ---------------------------------------------------------------------------
  // Summaries and history
  // ---------------------------------------------------------------------------

  Future<List<Summary>> summariesForEntry(
    int entryId, {
    String? edition,
  }) async {
    final params = <Object?>[entryId];
    var sql = 'SELECT * FROM pdgdata WHERE pdgid_id = ?';
    if (edition != null) {
      sql += ' AND edition = ?';
      params.add(edition);
    }
    sql += ' ORDER BY edition DESC, sort, id';
    final rows = await executor.select(sql, params);
    return [for (final row in rows) Summary(row)];
  }

  /// Returns the human-readable property description for a PDG identifier.
  Future<String?> descriptionForPdgid(String pdgid) async {
    final rows = await executor.select(
      'SELECT description FROM pdgid WHERE pdgid = ? LIMIT 1',
      [pdgid],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['description']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<Summary?> summaryById(int id) async {
    final rows = await executor.select('SELECT * FROM pdgdata WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : Summary(rows.first);
  }

  /// Resolves the current-edition counterpart of a captured summary row.
  ///
  /// A captured row may belong to an older edition, so its row id is not used
  /// blindly: the current edition is queried by pdgid + value_type. Exactly
  /// one match is authoritative; multiple matches are ambiguous and return
  /// null (the caller reports missing/fuzzy rather than guessing).
  Future<List<Summary>> currentSummaryCandidatesForCapture({
    required String pdgid,
    required String valueType,
    required int capturedRowId,
  }) async {
    final current = await summaryById(capturedRowId);
    if (current != null &&
        current.edition == currentEdition &&
        current.pdgid == pdgid &&
        current.valueType == valueType) {
      return [current];
    }
    final rows = await executor.select(
      'SELECT * FROM pdgdata WHERE pdgid = ? AND edition = ? AND value_type = ? '
      'ORDER BY sort, id',
      [pdgid, currentEdition, valueType],
    );
    return [for (final row in rows) Summary(row)];
  }

  Future<Summary?> currentSummaryForCapture({
    required String pdgid,
    required String valueType,
    required int capturedRowId,
  }) async {
    final rows = await currentSummaryCandidatesForCapture(
      pdgid: pdgid,
      valueType: valueType,
      capturedRowId: capturedRowId,
    );
    return rows.length == 1 ? rows.first : null;
  }

  /// Finds measurements by the identity fingerprint used when a stored id is
  /// no longer stable. Values/errors are deliberately not part of the key.
  Future<List<Measurement>> measurementCandidatesForFingerprint({
    required String pdgid,
    String? quantityLabel,
    String? technique,
    String? referenceDoi,
    String? referenceDocumentId,
  }) async {
    final params = <Object?>[pdgid];
    var sql =
        'SELECT m.* FROM pdgmeasurement m '
        'JOIN pdgid i ON i.pdgid = m.pdgid '
        'WHERE m.pdgid = ?';
    final label = quantityLabel?.trim() ?? '';
    if (label.isNotEmpty) {
      sql += ' AND i.description = ?';
      params.add(label);
    }
    final method = technique?.trim() ?? '';
    if (method.isNotEmpty) {
      sql += ' AND m.technique = ?';
      params.add(method);
    }
    final doi = referenceDoi?.trim() ?? '';
    if (doi.isNotEmpty) {
      sql +=
          ' AND EXISTS (SELECT 1 FROM pdgreference r '
          'WHERE r.id = m.pdgreference_id AND r.doi = ? COLLATE NOCASE)';
      params.add(doi);
    }
    final documentId = referenceDocumentId?.trim() ?? '';
    if (documentId.isNotEmpty) {
      sql +=
          ' AND EXISTS (SELECT 1 FROM pdgreference r '
          'WHERE r.id = m.pdgreference_id AND r.document_id = ?)';
      params.add(documentId);
    }
    sql += ' ORDER BY m.sort, m.id';
    final rows = await executor.select(sql, params);
    return [for (final row in rows) Measurement(row)];
  }

  Future<List<Summary>> currentSummariesForEntries(List<int> entryIds) async {
    final result = <Summary>[];
    for (final chunk in _chunk(entryIds, 350)) {
      final rows = await executor.select(
        '''
        SELECT * FROM pdgdata
         WHERE pdgid_id IN (${_placeholders(chunk.length)}) AND edition = ?
         ORDER BY pdgid_id, sort, id
      ''',
        [...chunk, currentEdition],
      );
      result.addAll([for (final row in rows) Summary(row)]);
    }
    return result;
  }

  Future<Map<int, int>> summaryCountsForEntries(
    List<int> entryIds, {
    String? edition,
  }) async {
    final result = <int, int>{};
    for (final chunk in _chunk(entryIds, 350)) {
      final params = <Object?>[...chunk];
      var sql =
          '''
        SELECT pdgid_id, COUNT(*) AS n FROM pdgdata
         WHERE pdgid_id IN (${_placeholders(chunk.length)})
      ''';
      if (edition != null) {
        sql += ' AND edition = ?';
        params.add(edition);
      }
      sql += ' GROUP BY pdgid_id';
      final rows = await executor.select(sql, params);
      for (final row in rows) {
        result[asInt(row['pdgid_id'])!] = asInt(row['n']) ?? 0;
      }
    }
    return result;
  }

  Future<List<String>> editionsForEntry(int entryId) async {
    final rows = await executor.select(
      'SELECT DISTINCT edition FROM pdgdata WHERE pdgid_id = ? AND edition IS NOT NULL ORDER BY edition DESC',
      [entryId],
    );
    return [for (final row in rows) asString(row['edition'])!];
  }

  // ---------------------------------------------------------------------------
  // Measurements
  // ---------------------------------------------------------------------------

  Future<MeasurementPage> measurementsPage(
    int entryId,
    String seriesPdgid, {
    MeasurementCursor? cursor,
    MeasurementFilter filter = const MeasurementFilter(),
    int pageSize = 50,
  }) async {
    if (cursor != null && cursor.seriesPdgid != seriesPdgid) {
      throw AppException(AppErrorCode.invalidInput, '分页游标与请求的系列不一致。');
    }
    final where = StringBuffer('m.pdgid_id = ?');
    final baseParams = <Object?>[entryId];
    if (filter.changebarOnly) where.write(' AND m.changebar = 1');
    _appendValueFilter(where, baseParams, filter);

    final countRows = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgmeasurement m WHERE $where',
      baseParams,
    );
    final total = asInt(countRows.first['n']) ?? 0;

    final pageParams = <Object?>[...baseParams];
    final wherePage = StringBuffer(where.toString());
    if (cursor != null) {
      wherePage.write(' AND (m.sort > ? OR (m.sort = ? AND m.id > ?))');
      pageParams.addAll([cursor.sort, cursor.sort, cursor.id]);
    }
    final rows = await executor.select('''
      SELECT m.* FROM pdgmeasurement m
       WHERE $wherePage
       ORDER BY m.sort, m.id
       LIMIT ${pageSize + 1}
    ''', pageParams);
    final hasMore = rows.length > pageSize;
    final pageRows = rows.take(pageSize).toList(growable: false);
    final measurements = [for (final row in pageRows) Measurement(row)];
    final bundles = await _bundlesFor(measurements);
    MeasurementCursor? nextCursor;
    if (measurements.isNotEmpty && hasMore) {
      final last = measurements.last;
      nextCursor = MeasurementCursor(
        seriesPdgid: seriesPdgid,
        sort: last.sort,
        id: last.id,
      );
    }
    return MeasurementPage(
      items: bundles,
      cursor: nextCursor,
      hasMore: hasMore,
      totalCount: total,
    );
  }

  void _appendValueFilter(
    StringBuffer where,
    List<Object?> params,
    MeasurementFilter filter,
  ) {
    final clauses = <String>[];
    switch (filter.average) {
      case InclusionFilter.any:
        break;
      case InclusionFilter.yes:
        clauses.add('v.used_in_average = 1');
      case InclusionFilter.no:
        clauses.add('v.used_in_average = 0');
      case InclusionFilter.unknown:
        clauses.add('v.used_in_average IS NULL');
    }
    switch (filter.fit) {
      case InclusionFilter.any:
        break;
      case InclusionFilter.yes:
        clauses.add('v.used_in_fit = 1');
      case InclusionFilter.no:
        clauses.add('v.used_in_fit = 0');
      case InclusionFilter.unknown:
        clauses.add('v.used_in_fit IS NULL');
    }
    switch (filter.limit) {
      case LimitFilter.any:
        break;
      case LimitFilter.point:
        clauses.add('v.limit_type IS NULL');
      case LimitFilter.upper:
        clauses.add("v.limit_type = 'U'");
      case LimitFilter.lower:
        clauses.add("v.limit_type = 'L'");
      case LimitFilter.range:
        clauses.add("v.limit_type = 'R'");
      case LimitFilter.exclusion:
        clauses.add("v.limit_type = 'X'");
    }
    if (clauses.isNotEmpty) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM pdgmeasurement_values v WHERE v.pdgmeasurement_id = m.id AND ${clauses.join(' AND ')})',
      );
    }
  }

  Future<List<MeasurementBundle>> _bundlesFor(
    List<Measurement> measurements,
  ) async {
    if (measurements.isEmpty) return const [];
    final ids = [for (final measurement in measurements) measurement.id];
    final valuesBy = <int, List<MeasurementValue>>{};
    final footnotesBy = <int, List<Footnote>>{};
    final references = <int, Reference>{};

    for (final chunk in _chunk(ids, 400)) {
      final valueRows = await executor.select('''
        SELECT * FROM pdgmeasurement_values
         WHERE pdgmeasurement_id IN (${_placeholders(chunk.length)})
         ORDER BY pdgmeasurement_id, sort, id
      ''', chunk);
      for (final row in valueRows) {
        final value = MeasurementValue(row);
        valuesBy.putIfAbsent(value.measurementId, () => []).add(value);
      }

      final footnoteRows = await executor.select('''
        SELECT f.*, mf.pdgmeasurement_id AS link_measurement_id
          FROM pdgmeasurement_footnote mf
          JOIN pdgfootnote f ON f.id = mf.pdgfootnote_id
         WHERE mf.pdgmeasurement_id IN (${_placeholders(chunk.length)})
         ORDER BY mf.pdgmeasurement_id, f.footnote_index, f.id
      ''', chunk);
      for (final row in footnoteRows) {
        final link = asInt(row['link_measurement_id'])!;
        final raw = Map<String, Object?>.from(row)
          ..remove('link_measurement_id');
        footnotesBy.putIfAbsent(link, () => []).add(Footnote(raw));
      }
    }

    final referenceIds = {
      for (final measurement in measurements) measurement.pdgreferenceId,
    }.toList(growable: false);
    for (final chunk in _chunk(referenceIds, 400)) {
      final referenceRows = await executor.select(
        'SELECT * FROM pdgreference WHERE id IN (${_placeholders(chunk.length)})',
        chunk,
      );
      for (final row in referenceRows) {
        final reference = Reference(row);
        references[reference.id] = reference;
      }
    }

    return [
      for (final measurement in measurements)
        MeasurementBundle(
          measurement: measurement,
          values: valuesBy[measurement.id] ?? const [],
          footnotes: footnotesBy[measurement.id] ?? const [],
          reference: references[measurement.pdgreferenceId],
        ),
    ];
  }

  Future<Map<int, int>> measurementCountsForEntries(List<int> entryIds) async {
    final result = <int, int>{};
    for (final chunk in _chunk(entryIds, 350)) {
      final rows = await executor.select('''
        SELECT pdgid_id, COUNT(*) AS n FROM pdgmeasurement
         WHERE pdgid_id IN (${_placeholders(chunk.length)})
         GROUP BY pdgid_id
      ''', chunk);
      for (final row in rows) {
        result[asInt(row['pdgid_id'])!] = asInt(row['n']) ?? 0;
      }
    }
    return result;
  }

  Future<int> directMeasurementCount(int entryId) async {
    final rows = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgmeasurement WHERE pdgid_id = ?',
      [entryId],
    );
    return asInt(rows.first['n']) ?? 0;
  }

  Future<MeasurementBundle?> measurementById(int id) async {
    final rows = await executor.select(
      'SELECT * FROM pdgmeasurement WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final bundles = await _bundlesFor([Measurement(rows.first)]);
    return bundles.isEmpty ? null : bundles.first;
  }

  // ---------------------------------------------------------------------------
  // References
  // ---------------------------------------------------------------------------

  Future<Reference?> referenceById(int id) async {
    final rows = await executor.select(
      'SELECT * FROM pdgreference WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : Reference(rows.first);
  }

  Future<List<Reference>> referencesForMeasurementIds(List<int> ids) async {
    final result = <Reference>[];
    for (final chunk in _chunk(ids, 400)) {
      final rows = await executor.select(
        'SELECT * FROM pdgreference WHERE id IN (${_placeholders(chunk.length)})',
        chunk,
      );
      result.addAll([for (final row in rows) Reference(row)]);
    }
    return result;
  }

  Future<int> referenceCountForSubtree(int rootEntryId) async {
    final countRows = await executor.select(
      '''
      WITH RECURSIVE d(id, depth) AS (
        SELECT id, 0 FROM pdgid WHERE id = ?
        UNION ALL
        SELECT p.id, d.depth + 1 FROM pdgid p JOIN d ON p.parent_id = d.id
         WHERE d.depth < 32
      )
      SELECT COUNT(DISTINCT m.pdgreference_id) AS n
        FROM d JOIN pdgmeasurement m ON m.pdgid_id = d.id
    ''',
      [rootEntryId],
    );
    return asInt(countRows.first['n']) ?? 0;
  }

  Future<ReferenceListPage> referencesForSubtree(
    int rootEntryId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final total = await referenceCountForSubtree(rootEntryId);
    final rows = await executor.select(
      '''
      WITH RECURSIVE d(id, depth) AS (
        SELECT id, 0 FROM pdgid WHERE id = ?
        UNION ALL
        SELECT p.id, d.depth + 1 FROM pdgid p JOIN d ON p.parent_id = d.id
         WHERE d.depth < 32
      )
      SELECT r.*, COUNT(m.id) AS measurement_count
        FROM d
        JOIN pdgmeasurement m ON m.pdgid_id = d.id
        JOIN pdgreference r ON r.id = m.pdgreference_id
       GROUP BY r.id
       ORDER BY r.publication_year DESC, r.document_id, r.id
       LIMIT ? OFFSET ?
    ''',
      [rootEntryId, limit, offset],
    );
    return ReferenceListPage(
      total: total,
      items: [
        for (final row in rows)
          ReferenceWithCount(
            Reference({
              for (final e in row.entries)
                if (e.key != 'measurement_count') e.key: e.value,
            }),
            asInt(row['measurement_count']) ?? 0,
          ),
      ],
    );
  }

  Future<List<ReferenceSeriesGroup>> referenceSeriesGroups(
    int referenceId,
  ) async {
    final rows = await executor.select(
      '''
      SELECT m.pdgid_id, i.pdgid, i.description, i.data_type, COUNT(*) AS n
        FROM pdgmeasurement m JOIN pdgid i ON i.id = m.pdgid_id
       WHERE m.pdgreference_id = ?
       GROUP BY m.pdgid_id
       ORDER BY i.sort, i.id
    ''',
      [referenceId],
    );
    return [
      for (final row in rows)
        ReferenceSeriesGroup(
          entryId: asInt(row['pdgid_id'])!,
          pdgid: asString(row['pdgid']) ?? '',
          description: asString(row['description']) ?? '',
          dataType: asString(row['data_type']) ?? '',
          count: asInt(row['n']) ?? 0,
        ),
    ];
  }

  Future<List<MeasurementBundle>> measurementsForReferenceSeries(
    int referenceId,
    int entryId, {
    int limit = 50,
  }) async {
    final rows = await executor.select(
      '''
      SELECT * FROM pdgmeasurement
       WHERE pdgreference_id = ? AND pdgid_id = ?
       ORDER BY sort, id
       LIMIT ?
    ''',
      [referenceId, entryId, limit],
    );
    return _bundlesFor([for (final row in rows) Measurement(row)]);
  }

  // ---------------------------------------------------------------------------
  // Related quantities and decay structure
  // ---------------------------------------------------------------------------

  Future<List<RelatedQuantity>> relatedQuantities(int sourceEntryId) async {
    final rows = await executor.select(
      '''
      SELECT m.id AS edge_id, m.source_id, m.source, m.target_id, m.target,
             m.type AS edge_type, m.sort AS edge_sort,
             q.id, q.pdgid, q.parent_id, q.parent_pdgid, q.description,
             q.mode_number, q.data_type, q.flags, q.year_added, q.sort
        FROM pdgid_map m JOIN pdgid q ON q.id = m.target_id
       WHERE m.source_id = ?
       ORDER BY m.sort, m.id
    ''',
      [sourceEntryId],
    );
    final targets = <RelatedQuantity>[];
    final targetIds = <int>[];
    for (final row in rows) {
      final edge = EntryEdge({
        'id': row['edge_id'],
        'source_id': row['source_id'],
        'source': row['source'],
        'target_id': row['target_id'],
        'target': row['target'],
        'type': row['edge_type'],
        'sort': row['edge_sort'],
      });
      final target = Entry({
        'id': row['id'],
        'pdgid': row['pdgid'],
        'parent_id': row['parent_id'],
        'parent_pdgid': row['parent_pdgid'],
        'description': row['description'],
        'mode_number': row['mode_number'],
        'data_type': row['data_type'],
        'flags': row['flags'],
        'year_added': row['year_added'],
        'sort': row['sort'],
      });
      targetIds.add(target.id);
      targets.add(
        RelatedQuantity(
          edge: edge,
          target: target,
          summaryCount: 0,
          measurementCount: 0,
        ),
      );
    }
    if (targetIds.isEmpty) return targets;
    final summaryCounts = await summaryCountsForEntries(
      targetIds,
      edition: currentEdition,
    );
    final measurementCounts = await measurementCountsForEntries(targetIds);
    return [
      for (final item in targets)
        RelatedQuantity(
          edge: item.edge,
          target: item.target,
          summaryCount: summaryCounts[item.target.id] ?? 0,
          measurementCount: measurementCounts[item.target.id] ?? 0,
        ),
    ];
  }

  Future<List<RelatedQuantity>> relatedSources(int targetEntryId) async {
    final rows = await executor.select(
      '''
      SELECT m.id AS edge_id, m.source_id, m.source, m.target_id, m.target,
             m.type AS edge_type, m.sort AS edge_sort,
             q.id, q.pdgid, q.parent_id, q.parent_pdgid, q.description,
             q.mode_number, q.data_type, q.flags, q.year_added, q.sort
        FROM pdgid_map m JOIN pdgid q ON q.id = m.source_id
       WHERE m.target_id = ?
       ORDER BY m.sort, m.id
    ''',
      [targetEntryId],
    );
    final result = <RelatedQuantity>[];
    for (final row in rows) {
      final edge = EntryEdge({
        'id': row['edge_id'],
        'source_id': row['source_id'],
        'source': row['source'],
        'target_id': row['target_id'],
        'target': row['target'],
        'type': row['edge_type'],
        'sort': row['edge_sort'],
      });
      final source = Entry({
        'id': row['id'],
        'pdgid': row['pdgid'],
        'parent_id': row['parent_id'],
        'parent_pdgid': row['parent_pdgid'],
        'description': row['description'],
        'mode_number': row['mode_number'],
        'data_type': row['data_type'],
        'flags': row['flags'],
        'year_added': row['year_added'],
        'sort': row['sort'],
      });
      result.add(
        RelatedQuantity(
          edge: edge,
          target: source,
          summaryCount: 0,
          measurementCount: 0,
        ),
      );
    }
    return result;
  }

  Future<List<DecayToken>> decayTokens(int entryId) async {
    final rows = await executor.select(
      '''
      SELECT d.*, i.item_type, i.name AS item_name
        FROM pdgdecay d JOIN pdgitem i ON i.id = d.pdgitem_id
       WHERE d.pdgid_id = ?
       ORDER BY d.sort, d.id
    ''',
      [entryId],
    );
    return [for (final row in rows) DecayToken(row)];
  }

  Future<int> decayTokenCount(int entryId) async {
    final rows = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgdecay WHERE pdgid_id = ?',
      [entryId],
    );
    return asInt(rows.first['n']) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Search helpers (title/text/reference SQL; names live in the Dart index)
  // ---------------------------------------------------------------------------

  Future<List<Entry>> entriesByDescription(
    String term, {
    bool decaysOnly = false,
    bool excludeDecays = false,
    int limit = 30,
    int offset = 0,
  }) async {
    final like = '%${_escapeLike(term)}%';
    final conditions = <String>['description LIKE ? ESCAPE \'\\\''];
    final params = <Object?>[like];
    if (decaysOnly) {
      conditions.add("data_type LIKE 'BF%'");
    } else if (excludeDecays) {
      conditions.add("data_type NOT LIKE 'BF%'");
    }
    final rows = await executor.select(
      '''
      SELECT * FROM pdgid
       WHERE ${conditions.join(' AND ')}
       ORDER BY CASE WHEN description = ? THEN 0 ELSE 1 END, sort, id
       LIMIT ? OFFSET ?
    ''',
      [...params, term, limit, offset],
    );
    return [for (final row in rows) Entry(row)];
  }

  Future<int> countEntriesByDescription(
    String term, {
    bool decaysOnly = false,
    bool excludeDecays = false,
  }) async {
    final like = '%${_escapeLike(term)}%';
    final conditions = <String>['description LIKE ? ESCAPE \'\\\''];
    if (decaysOnly) conditions.add("data_type LIKE 'BF%'");
    if (excludeDecays) conditions.add("data_type NOT LIKE 'BF%'");
    final rows = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgid WHERE ${conditions.join(' AND ')}',
      [like],
    );
    return asInt(rows.first['n']) ?? 0;
  }

  Future<List<TextSearchHit>> entriesByText(
    String term, {
    int limit = 20,
    int offset = 0,
  }) async {
    final like = '%${_escapeLike(term)}%';
    final rows = await executor.select(
      '''
      SELECT t.id AS text_id, t.text, t.type AS text_type, t.sort AS text_sort,
             i.id, i.pdgid, i.description, i.data_type, i.flags, i.parent_id,
             i.parent_pdgid, i.mode_number, i.year_added, i.sort
        FROM pdgtext t JOIN pdgid i ON i.id = t.pdgid_id
       WHERE t.text LIKE ? ESCAPE '\\'
       ORDER BY i.sort, i.id, t.sort, t.id
       LIMIT ? OFFSET ?
    ''',
      [like, limit, offset],
    );
    return [
      for (final row in rows)
        TextSearchHit(
          entry: Entry({
            'id': row['id'],
            'pdgid': row['pdgid'],
            'parent_id': row['parent_id'],
            'parent_pdgid': row['parent_pdgid'],
            'description': row['description'],
            'mode_number': row['mode_number'],
            'data_type': row['data_type'],
            'flags': row['flags'],
            'year_added': row['year_added'],
            'sort': row['sort'],
          }),
          text: asString(row['text']) ?? '',
          textId: asInt(row['text_id'])!,
        ),
    ];
  }

  Future<int> countEntriesByText(String term) async {
    final like = '%${_escapeLike(term)}%';
    final rows = await executor.select(
      'SELECT COUNT(DISTINCT pdgid_id) AS n FROM pdgtext WHERE text LIKE ? ESCAPE \'\\\'',
      [like],
    );
    return asInt(rows.first['n']) ?? 0;
  }

  Future<({List<Reference> items, int total})> searchReferencesPage(
    String term, {
    int limit = 30,
    int offset = 0,
    int? year,
  }) async {
    final like = '%${_escapeLike(term)}%';
    final params = <Object?>[term, term, term, term, like, like];
    var sql = '''
      SELECT *, COUNT(*) OVER() AS __total FROM pdgreference
       WHERE (TRIM(document_id) = ? COLLATE NOCASE
              OR TRIM(doi) = ? COLLATE NOCASE
              OR TRIM(inspire_id) = ? COLLATE NOCASE
              OR TRIM(title) = ? COLLATE NOCASE
              OR title LIKE ? ESCAPE '\\'
              OR publication_name LIKE ? ESCAPE '\\')
    ''';
    if (year != null) {
      sql += ' AND publication_year = ?';
      params.add(year);
    }
    sql += '''
       ORDER BY CASE WHEN TRIM(document_id) = ? COLLATE NOCASE
                      OR TRIM(doi) = ? COLLATE NOCASE
                      OR TRIM(inspire_id) = ? COLLATE NOCASE THEN 0 ELSE 1 END,
                publication_year DESC, document_id, id
       LIMIT ? OFFSET ?
    ''';
    params.addAll([term, term, term, limit, offset]);
    final rows = await executor.select(sql, params);
    final total = rows.isEmpty ? 0 : (asInt(rows.first['__total']) ?? 0);
    return (items: [for (final row in rows) Reference(row)], total: total);
  }

  /// Full reference list for client-side matching of cleaned MathML titles.
  /// The PDG snapshot exposes raw MathML titles, so SQL LIKE cannot find terms
  /// such as `WZ` that are split across `<mi>` elements.
  Future<List<Reference>> allReferencesForTitleScan() async {
    final rows = await executor.select(
      'SELECT * FROM pdgreference ORDER BY id',
    );
    return [for (final row in rows) Reference(row)];
  }

  Future<List<Reference>> searchReferences(
    String term, {
    int limit = 30,
    int offset = 0,
    int? year,
  }) async {
    final like = '%${_escapeLike(term)}%';
    final params = <Object?>[term, term, term, term, like, like];
    var sql = '''
      SELECT * FROM pdgreference
       WHERE (TRIM(document_id) = ? COLLATE NOCASE
              OR TRIM(doi) = ? COLLATE NOCASE
              OR TRIM(inspire_id) = ? COLLATE NOCASE
              OR TRIM(title) = ? COLLATE NOCASE
              OR title LIKE ? ESCAPE '\\'
              OR publication_name LIKE ? ESCAPE '\\')
    ''';
    // params[3] is the exact-title slot.
    if (year != null) {
      sql += ' AND publication_year = ?';
      params.add(year);
    }
    sql += '''
       ORDER BY CASE WHEN TRIM(document_id) = ? COLLATE NOCASE
                      OR TRIM(doi) = ? COLLATE NOCASE
                      OR TRIM(inspire_id) = ? COLLATE NOCASE THEN 0 ELSE 1 END,
                publication_year DESC, document_id, id
       LIMIT ? OFFSET ?
    ''';
    params.addAll([term, term, term, limit, offset]);
    final rows = await executor.select(sql, params);
    return [for (final row in rows) Reference(row)];
  }

  Future<int> countSearchReferences(String term, {int? year}) async {
    final like = '%${_escapeLike(term)}%';
    final params = <Object?>[term, term, term, like, like];
    var sql = '''
      SELECT COUNT(*) AS n FROM pdgreference
       WHERE (TRIM(document_id) = ? COLLATE NOCASE
              OR TRIM(doi) = ? COLLATE NOCASE
              OR TRIM(inspire_id) = ? COLLATE NOCASE
              OR title LIKE ? ESCAPE '\\'
              OR publication_name LIKE ? ESCAPE '\\')
    ''';
    if (year != null) {
      sql += ' AND publication_year = ?';
      params.add(year);
    }
    final rows = await executor.select(sql, params);
    return asInt(rows.first['n']) ?? 0;
  }

  Future<Reference?> referenceByDocumentId(String documentId) async {
    final id = documentId.trim();
    if (id.isEmpty) return null;
    final rows = await executor.select(
      'SELECT * FROM pdgreference WHERE TRIM(document_id) = ? COLLATE NOCASE '
      'ORDER BY id LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : Reference(rows.first);
  }

  /// Resolves citation keys such as `MYERS 2014` to local PDG references.
  /// Only exact document IDs are returned; a year or spelling mismatch is not
  /// guessed, because that would link the wrong paper.
  Future<Map<String, int>> referenceIdsForCitationKeys(
    Iterable<String> keys,
  ) async {
    final requested = <String, Set<String>>{};
    for (final key in keys) {
      final normalized = key
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toUpperCase();
      if (normalized.isEmpty) continue;
      final variants = <String>{normalized};
      // PDG bibliographies often abbreviate the year (`SCHUMACHER 05`), while
      // the descriptive text writes the full year (`SCHUMACHER 2005`).
      final match = RegExp(r'^(.*?)\s+((?:19|20)\d{2})([A-Z]?)$')
          .firstMatch(normalized);
      if (match != null) {
        variants.add(
          '${match.group(1)} ${match.group(2)!.substring(2)}${match.group(3) ?? ''}',
        );
      }
      requested[normalized] = variants;
    }
    if (requested.isEmpty) return const <String, int>{};
    final allVariants = <String>{
      for (final variants in requested.values) ...variants,
    }.toList(growable: false);
    final byVariant = <String, int>{};
    for (var start = 0; start < allVariants.length; start += 400) {
      final chunk = allVariants.sublist(
        start,
        (start + 400 < allVariants.length) ? start + 400 : allVariants.length,
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await executor.select(
        'SELECT id, document_id FROM pdgreference '
        'WHERE UPPER(TRIM(document_id)) IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        final normalized = (asString(row['document_id']) ?? '')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toUpperCase();
        final id = asInt(row['id']);
        if (id != null) byVariant.putIfAbsent(normalized, () => id);
      }
    }
    final result = <String, int>{};
    for (final entry in requested.entries) {
      for (final variant in entry.value) {
        final id = byVariant[variant];
        if (id != null) {
          result[entry.key] = id;
          break;
        }
      }
    }
    return result;
  }

  Future<List<Reference>> referencesByDoi(String doi) async {
    final rows = await executor.select(
      'SELECT * FROM pdgreference WHERE doi = ? COLLATE NOCASE ORDER BY id',
      [doi],
    );
    return [for (final row in rows) Reference(row)];
  }

  // ---------------------------------------------------------------------------
  // Footnotes attached to measurements
  // ---------------------------------------------------------------------------

  Future<List<FootnoteAttachment>> footnoteAttachments(int footnoteId) async {
    final rows = await executor.select(
      '''
      SELECT mf.pdgmeasurement_id, m.pdgid, m.sort
        FROM pdgmeasurement_footnote mf
        JOIN pdgmeasurement m ON m.id = mf.pdgmeasurement_id
       WHERE mf.pdgfootnote_id = ?
       ORDER BY m.pdgid, m.sort, m.id
    ''',
      [footnoteId],
    );
    return [
      for (final row in rows)
        FootnoteAttachment(
          footnoteId: footnoteId,
          measurementId: asInt(row['pdgmeasurement_id'])!,
          seriesPdgid: asString(row['pdgid']) ?? '',
          sort: asInt(row['sort']) ?? 0,
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Snapshot statistics
  // ---------------------------------------------------------------------------

  Future<List<TableStat>> tableStats() async {
    final result = <TableStat>[];
    for (final table in SnapshotContract.requiredSchema.keys) {
      final rows = await executor.select('SELECT COUNT(*) AS n FROM $table');
      result.add(TableStat(table, asInt(rows.first['n']) ?? 0));
    }
    return result;
  }

  Future<SnapshotStats>? _snapshotStatsCache;

  /// Snapshot counts, cached for this database handle. Both Home and Settings
  /// request them during startup; without this cache every mounted page would
  /// rescan all tables.
  Future<SnapshotStats> snapshotStats() =>
      _snapshotStatsCache ??= _snapshotStatsUncached();

  Future<SnapshotStats> _snapshotStatsUncached() async {
    // Only the headline counts are eager. The 15-table breakdown is loaded by
    // the Settings disclosure on demand.
    final entries = await executor.select('SELECT COUNT(*) AS n FROM pdgid');
    final current = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgdata WHERE edition = ?',
      [currentEdition],
    );
    final all = await executor.select('SELECT COUNT(*) AS n FROM pdgdata');
    final refs = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgreference',
    );
    final measurements = await executor.select(
      'SELECT COUNT(*) AS n FROM pdgmeasurement',
    );
    return SnapshotStats(
      tables: const <TableStat>[],
      entries: asInt(entries.first['n']) ?? 0,
      currentSummaries: asInt(current.first['n']) ?? 0,
      allSummaries: asInt(all.first['n']) ?? 0,
      references: asInt(refs.first['n']) ?? 0,
      measurements: asInt(measurements.first['n']) ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<List<T>> _chunk<T>(List<T> source, int size) {
    if (source.isEmpty) return const [];
    final chunks = <List<T>>[];
    for (var i = 0; i < source.length; i += size) {
      chunks.add(
        source.sublist(i, i + size > source.length ? source.length : i + size),
      );
    }
    return chunks;
  }

  static String _placeholders(int count) => List.filled(count, '?').join(',');

  static String _escapeLike(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

class CatalogRoot {
  const CatalogRoot(
    this.entry,
    this.childCount,
    this.particleCount, {
    this.hasContent = true,
  });

  final Entry entry;
  final int childCount;
  final int particleCount;

  /// False for PDG section rows that carry nothing at all (no children,
  /// particles, texts, measurements or decays). The catalog hides those
  /// instead of showing a tile that opens an empty page.
  final bool hasContent;
}

class ReferenceWithCount {
  const ReferenceWithCount(this.reference, this.measurementCount);

  final Reference reference;
  final int measurementCount;
}

class ReferenceListPage {
  const ReferenceListPage({required this.total, required this.items});

  final int total;
  final List<ReferenceWithCount> items;
}

class ReferenceSeriesGroup {
  const ReferenceSeriesGroup({
    required this.entryId,
    required this.pdgid,
    required this.description,
    required this.dataType,
    required this.count,
  });

  final int entryId;
  final String pdgid;
  final String description;
  final String dataType;
  final int count;
}

class FootnoteAttachment {
  const FootnoteAttachment({
    required this.footnoteId,
    required this.measurementId,
    required this.seriesPdgid,
    required this.sort,
  });

  final int footnoteId;
  final int measurementId;
  final String seriesPdgid;
  final int sort;
}

class TextSearchHit {
  const TextSearchHit({
    required this.entry,
    required this.text,
    required this.textId,
  });

  final Entry entry;
  final String text;
  final int textId;
}

class TableStat {
  const TableStat(this.table, this.rows);

  final String table;
  final int rows;
}

class SnapshotStats {
  const SnapshotStats({
    required this.tables,
    required this.entries,
    required this.currentSummaries,
    required this.allSummaries,
    required this.references,
    required this.measurements,
  });

  final List<TableStat> tables;
  final int entries;
  final int currentSummaries;
  final int allSummaries;
  final int references;
  final int measurements;
}
