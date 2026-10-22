import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/core/errors.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/pdg_repository.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/features/notes/note_evidence_resolver.dart';
import 'package:pdgapp/domain/display.dart';
import 'package:pdgapp/domain/filters.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/search/search_service.dart';

void main() {
  late DirectSqlExecutor executor;
  late PdgDatabase db;

  setUpAll(() async {
    if (!File('assets/pdgall-2026.0.sqlite').existsSync()) {
      fail(
        'Snapshot asset missing; this suite must run against the real pdgall file.',
      );
    }
    executor = await DirectSqlExecutor.open('assets/pdgall-2026.0.sqlite');
    db = await PdgDatabase.open(
      executor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
  });

  tearDownAll(() async {
    await executor.dispose();
  });

  test('negative Monte Carlo ids resolve the antiparticle', () async {
    final particles = await db.particlesByMcid(-211);
    expect(particles, isNotEmpty);
    expect(particles.first.name, contains('pi'));
  });

  test('snapshot metadata and schema are the verified baseline', () async {
    expect(db.info.edition, '2026');
    expect(db.info.schemaVersion, '0.3');
    expect(db.info.license, 'CC BY 4.0');
    expect(db.currentEdition, '2026');
    final editions = await db.loadEditions();
    expect(editions.first, '2026');
    expect(editions.length, 54);
  });

  test('D0 listing has two identities and the expected decay tree', () async {
    final entry = await db.requireEntryByPdgid('S032');
    expect(entry.dataType, 'PART');
    expect(entry.flags, 'M');
    final particles = await db.particlesForEntry(entry.id);
    expect(
      particles.map((particle) => particle.name),
      containsAll(['D0', 'Dbar0']),
    );
    final descendants = await db.descendants(entry.id);
    expect(descendants.length, 1062);
    expect(descendants.where((row) => row.pdgid == 'S032M').length, 1);
    expect(
      descendants.where((row) => isDecayType(row.dataType)).length,
      greaterThan(100),
    );
  });

  test('property descriptions are available for Evidence display', () async {
    expect(await db.descriptionForPdgid('S032M'), 'D0 MASS');
    expect(await db.descriptionForPdgid('not-a-pdgid'), isNull);
  });

  test(
    'measurement fingerprint finds candidates and flags ambiguity',
    () async {
      final description = await db.descriptionForPdgid('M176M');
      expect(description, isNotNull);
      final candidates = await db.measurementCandidatesForFingerprint(
        pdgid: 'M176M',
        quantityLabel: description,
      );
      expect(candidates.length, greaterThan(1));

      final resolver = PdgEvidenceResolver(db);
      final current = await resolver.resolveMeasurement(
        'M176M',
        -1,
        technique: candidates.first.technique,
      );
      expect(current, isNotNull);
      expect(current!.ambiguous, isTrue);
    },
  );

  test(
    'measurement Evidence compares against the current PDG summary',
    () async {
      final rows = await executor.select(
        'SELECT id FROM pdgmeasurement WHERE pdgid = ? LIMIT 1',
        ['S032M'],
      );
      expect(rows, isNotEmpty);
      final current = await PdgEvidenceResolver(db)
          .resolveMeasurement('S032M', rows.first['id']! as int);
      expect(current, isNotNull);
      expect(current!.edition, '2026');
      expect(current.quantityLabel, 'D0 MASS');
      expect(current.value, isNotNull);
    },
  );

  test('captured summary resolves its current-edition counterpart', () async {
    final entry = await db.requireEntryByPdgid('S032M');
    final all = await db.summariesForEntry(entry.id);
    final current = all.where((row) => row.edition == '2026').toList();
    final old = all.where((row) => row.edition != '2026').toList();
    expect(current, isNotEmpty);
    expect(old, isNotEmpty);
    Summary? resolved;
    for (final candidate in old) {
      final peers = current
          .where((row) => row.valueType == candidate.valueType)
          .toList();
      if (peers.length != 1) continue;
      resolved = await db.currentSummaryForCapture(
        pdgid: candidate.pdgid,
        valueType: candidate.valueType,
        capturedRowId: candidate.id,
      );
      expect(resolved, isNotNull, reason: 'valueType ${candidate.valueType}');
      expect(resolved!.edition, '2026');
      expect(resolved.id, peers.single.id);
      break;
    }
    expect(resolved, isNotNull, reason: 'no historical summary candidate');
  });

  test('D0 mass has two candidates with a unique summary-table fit', () async {
    final entry = await db.requireEntryByPdgid('S032M');
    final summaries = await db.summariesForEntry(entry.id, edition: '2026');
    expect(summaries.length, 2);
    final selection = selectBestSummary(summaries);
    expect(selection.preferred, isNotNull);
    expect(selection.preferred!.valueType, 'FC');
    expect(selection.preferred!.inSummaryTable, isTrue);
    expect(selection.preferred!.unitText, 'MeV');
    expect(selection.candidates.length, 2);
  });

  test('decay mode tokens, related quantities and the absent direct BF measurement', () async {
    final entry = await db.requireEntryByPdgid('S032.1');
    expect(entry.description, 'D0 --> K- pi+');
    final tokens = await db.decayTokens(entry.id);
    expect(tokens.length, 3);
    expect(tokens.map((token) => token.name), ['D0', 'K-', 'pi+']);
    expect(tokens.last.itemType, 'P');
    final related = await db.relatedQuantities(entry.id);
    expect(related.length, 40);
    expect(await db.directMeasurementCount(entry.id), 0);
    expect(related.first.target.dataType, 'BR');
    expect(related.first.edge.type, 'D');
  });

  test(
    'photon multiplicity and multi-arrow source order are preserved',
    () async {
      final pi0decay = await db.requireEntryByPdgid('S009.1');
      final pi0tokens = await db.decayTokens(pi0decay.id);
      expect(pi0tokens.length, 2);
      expect(pi0tokens.last.name, 'gamma');
      expect(pi0tokens.last.multiplier, 2);

      final multi = await db.requireEntryByPdgid('S035.286');
      final tokens = await db.decayTokens(multi.id);
      expect(tokens.length, 9);
      expect(tokens.where((token) => token.name == '-->').length, 1);
      expect(RegExp(r'-->').allMatches(multi.description).length, 2);

      final incomplete = await db.requireEntryByPdgid('S035.319');
      final incompleteTokens = await db.decayTokens(incomplete.id);
      expect(incompleteTokens.any((token) => token.isOutgoing), isFalse);
      expect(incomplete.description, isNotEmpty);
    },
  );

  test('the S016T22 lifetime keeps its own power and unit', () async {
    final entry = await db.requireEntryByPdgid('S016T22');
    final summaries = await db.summariesForEntry(entry.id, edition: '2026');
    expect(summaries.length, 1);
    final quantity = DisplayQuantity.fromSummary(summaries.first);
    expect(quantity.inPercent, isFalse);
    expect(quantity.text.contains('×10³⁰'), isTrue);
    expect(quantity.unitText, 'years');
    expect(quantity.isLimit, isTrue);
  });

  test(
    'multi-column measurements keep every cell and inclusion flag',
    () async {
      final bundle = await db.measurementById(5970);
      expect(bundle, isNotNull);
      expect(bundle!.values.length, 6);
      expect(
        bundle.values.map((value) => value.columnName),
        containsAll(['<lambda>', 'CL%', '<eta>', 'ISOTOPE', 'METHOD']),
      );
      final cl = bundle.values.firstWhere((value) => value.columnName == 'CL%');
      expect(cl.value, 90);
      expect(cl.usedInAverage, isFalse);
      expect(cl.usedInFit, isFalse);
    },
  );

  test('measurement footnotes are attached by the integer edge only', () async {
    final bundle = await db.measurementById(15576);
    expect(bundle, isNotNull);
    expect(bundle!.footnotes, isNotEmpty);
    expect(bundle.footnotes.map((footnote) => footnote.id), contains(9467));
    final attachments = await db.footnoteAttachments(9467);
    expect(
      attachments.any((attachment) => attachment.measurementId == 15576),
      isTrue,
    );
  });

  test('reference rows retain every bibliographic field', () async {
    final reference = await db.referenceById(3);
    expect(reference, isNotNull);
    expect(reference!.documentId, 'GOLDHABER 1968');
    expect(reference.doi, '10.1103/PhysRevLett.21.567');
    expect(reference.inspireId, '53182');
    expect(reference.publicationYear, 1968);
    expect(reference.title, contains('Geomagnetic'));
    expect(reference.publicationName, isNotEmpty);
  });

  test(
    'the D0 subtree exposes all reverse-linked references with counts',
    () async {
      final entry = await db.requireEntryByPdgid('S032');
      final page = await db.referencesForSubtree(entry.id, limit: 10);
      expect(page.total, 383);
      expect(page.items.length, 10);
      expect(page.items.map((item) => item.reference.id).toSet().length, 10);
      expect(page.items.every((item) => item.measurementCount > 0), isTrue);
    },
  );

  test('a name item with two listings stays ambiguous', () async {
    final resolution = await db.resolveItem(1593);
    expect(resolution.item.name, 'P_c_cbar(4312)+');
    expect(resolution.listings.length, 2);
    expect(resolution.listings, containsAll(['B185', 'B205']));
    expect(resolution.candidates.length, 2);
  });

  test(
    'batch resolution returns the same listings without a query per item',
    () async {
      final alias = await db.itemByName('J/psi');
      expect(alias, isNotNull);
      final resolutions = await db.resolveItems([1593, alias!.id]);
      expect(resolutions, hasLength(2));
      expect(resolutions[0].listings, {'B185', 'B205'});
      expect(resolutions[1].listings, {'M070'});
      expect(resolutions[1].candidates.single.name, 'J/psi(1S)');
    },
  );

  test('an alias item resolves through pdgitem_map', () async {
    final item = await db.itemByName('J/psi');
    expect(item, isNotNull);
    expect(item!.itemType, 'G');
    final resolution = await db.resolveItem(item.id);
    expect(resolution.listings, {'M070'});
    expect(resolution.candidates.single.name, 'J/psi(1S)');
    expect(resolution.mappedParticles, isNotEmpty);
  });

  test(
    'catalog contains every root, including roots without particle rows',
    () async {
      final roots = await db.catalogRoots();
      expect(roots.length, 475);
      final s067 = roots.where((root) => root.entry.pdgid == 'S067');
      expect(s067, isNotEmpty);
      expect(s067.single.particleCount, 0);
      final m169 = roots.where((root) => root.entry.pdgid == 'M169');
      expect(m169, isNotEmpty);
      expect(m169.single.entry.dataType, 'PART');
      expect(m169.single.particleCount, 0);
      // S067 has children, so it is still shown; the eleven PDG section rows
      // with no children, particles, texts, measurements or decays are not.
      expect(s067.single.hasContent, isTrue);
      final empty = roots.where((root) => !root.hasContent).toList();
      expect(empty.length, 11);
      expect(
        empty.map((root) => root.entry.pdgid),
        containsAll(['M826', 'S841', 'S842', 'B801']),
      );
    },
  );

  test(
    'measurement pagination is complete, unique and cursor-stable',
    () async {
      final entry = await db.requireEntryByPdgid('S046GNO');
      final rawCount = await executor.select(
        'SELECT COUNT(*) AS n FROM pdgmeasurement WHERE pdgid_id = ?',
        [entry.id],
      );
      final total = asInt(rawCount.first['n'])!;
      expect(total, greaterThan(50));
      final valueCount = await executor.select(
        'SELECT COUNT(*) AS n FROM pdgmeasurement_values WHERE pdgmeasurement_id IN '
        '(SELECT id FROM pdgmeasurement WHERE pdgid_id = ?)',
        [entry.id],
      );
      final expectedValues = asInt(valueCount.first['n'])!;
      final ids = <int>{};
      var values = 0;
      MeasurementCursor? cursor;
      var pages = 0;
      do {
        final page = await db.measurementsPage(
          entry.id,
          entry.pdgid,
          cursor: cursor,
          pageSize: 50,
        );
        expect(page.totalCount, total);
        for (final item in page.items) {
          expect(ids.add(item.measurement.id), isTrue);
          values += item.values.length;
        }
        cursor = page.cursor;
        pages++;
        if (!page.hasMore) break;
        expect(cursor, isNotNull);
      } while (pages < 20);
      expect(ids.length, total);
      expect(values, expectedValues);
    },
  );

  test(
    'measurement filters are applied to value rows but keep whole groups',
    () async {
      final entry = await db.requireEntryByPdgid('S076ETA');
      const filter = MeasurementFilter(average: InclusionFilter.no);
      final page = await db.measurementsPage(
        entry.id,
        entry.pdgid,
        filter: filter,
      );
      final raw = await executor.select(
        '''
      SELECT COUNT(DISTINCT m.id) AS n FROM pdgmeasurement m
       WHERE m.pdgid_id = ?
         AND EXISTS (SELECT 1 FROM pdgmeasurement_values v
                      WHERE v.pdgmeasurement_id = m.id AND v.used_in_average = 0)
    ''',
        [entry.id],
      );
      expect(page.totalCount, asInt(raw.first['n']));
      for (final item in page.items) {
        expect(
          item.values.any((value) => value.usedInAverage == false),
          isTrue,
        );
      }
      final multi = page.items.where((item) => item.measurement.id == 5970);
      expect(multi, isNotEmpty);
      expect(multi.single.values.length, 6);
    },
  );

  test(
    'a cursor from another series is rejected, not silently switched',
    () async {
      final entry = await db.requireEntryByPdgid('S032M');
      await expectLater(
        db.measurementsPage(
          entry.id,
          entry.pdgid,
          cursor: const MeasurementCursor(seriesPdgid: 'S999', sort: 0, id: 0),
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            AppErrorCode.invalidInput,
          ),
        ),
      );
    },
  );

  test('name search handles Unicode, aliases and generic names', () async {
    final search = SearchService(db);
    Future<SearchResults> query(
      String text, [
      SearchScope scope = SearchScope.particles,
    ]) => search.search(text, scope);

    for (final spelling in ['pi0', 'π⁰', r'\pi^0']) {
      final results = await query(spelling);
      final group = results.groups
          .where((group) => group.kind == SearchGroupKind.particle)
          .toList();
      expect(group, isNotEmpty, reason: spelling);
      expect(
        group.first.hits.map((hit) => hit.pdgid),
        contains('S009'),
        reason: spelling,
      );
    }

    final proton = await query('proton');
    expect(proton.groups.first.hits.map((hit) => hit.pdgid), contains('S016'));

    final bs = await query('B_s0');
    expect(bs.groups.first.hits.map((hit) => hit.pdgid), contains('S086'));

    for (final spelling in ['J/ψ', 'J/psi', 'jpsi']) {
      final jpsi = await query(spelling);
      expect(
        jpsi.groups.first.hits.map((hit) => hit.pdgid),
        contains('M070'),
        reason: spelling,
      );
    }

    final mcid = await query('2212');
    expect(mcid.groups.first.hits.map((hit) => hit.pdgid), contains('S016'));

    final identifier = await search.search('S032', SearchScope.all);
    expect(
      identifier.groups.any(
        (group) =>
            group.kind == SearchGroupKind.identifier &&
            group.hits.single.pdgid == 'S032',
      ),
      isTrue,
    );
  });

  test('title, decay, text and reference scopes stay separate', () async {
    final search = SearchService(db);
    final topics = await search.search('Neutrino Mixing', SearchScope.titles);
    expect(
      topics.groups.any(
        (group) =>
            group.kind == SearchGroupKind.topic &&
            group.hits.any((hit) => hit.pdgid == 'S067'),
      ),
      isTrue,
    );

    final decays = await search.search('D0 --> K- pi+', SearchScope.decays);
    expect(
      decays.groups.any(
        (group) =>
            group.kind == SearchGroupKind.decay &&
            group.hits.any((hit) => hit.pdgid == 'S032.1'),
      ),
      isTrue,
    );

    final text = await search.search('The fit includes', SearchScope.titles);
    expect(
      text.groups.any((group) => group.kind == SearchGroupKind.text),
      isTrue,
    );

    final reference = await search.search(
      '10.1103/PhysRevLett.21.567',
      SearchScope.references,
    );
    expect(
      reference.groups.any(
        (group) =>
            group.kind == SearchGroupKind.reference &&
            group.hits.any((hit) => hit.referenceId == 3),
      ),
      isTrue,
    );

    final year = await search.search('1968', SearchScope.references);
    expect(
      year.groups.any((group) => group.kind == SearchGroupKind.reference),
      isTrue,
    );
  });

  test('LIKE metacharacters are treated as literals', () async {
    final count = await db.countEntriesByDescription('%');
    expect(count, lessThan(100));
    final rows = await db.entriesByDescription('%');
    expect(rows.every((row) => row.description.contains('%')), isTrue);
  });

  test('curated summary-type indicators match the snapshot pdgdoc', () async {
    final rows = await executor.select(
      "SELECT value, indicator FROM pdgdoc WHERE table_name = 'PDGDATA' AND column_name = 'VALUE_TYPE'",
    );
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final code = asString(row['value'])!;
      final official = asString(row['indicator']) ?? '';
      expect(
        valueTypeIndicator(code),
        official,
        reason: 'pdgdata.value_type $code indicator must come from pdgdoc',
      );
      expect(
        valueTypeLabel(code, TextLang.en),
        isNot(contains('average flag')),
      );
      expect(valueTypeLabel(code, TextLang.en), isNot(contains('fit flag')));
    }
  });

  test('snapshot statistics match the documented counts', () async {
    final stats = await db.snapshotStats();
    expect(stats.entries, 22049);
    expect(stats.references, 14594);
    expect(stats.currentSummaries, 19587);
    expect(stats.measurements, 43872);

    final tables = await db.tableStats();
    expect(tables.length, 15);
    expect(
      tables.firstWhere((table) => table.table == 'pdgmeasurement_values').rows,
      49080,
    );
    expect(tables.firstWhere((table) => table.table == 'pdgdecay').rows, 30357);
  });
  test('citation keys resolve to exact local references only', () async {
    final resolved = await db.referenceIdsForCitationKeys([
      'SCHMIEDMAYER 1988',
      ' schmiedmayer   1988 ',
      'SCHMIEDMAYER 1989',
    ]);
    expect(resolved['SCHMIEDMAYER 1988'], isNotNull);
    expect(resolved['SCHMIEDMAYER 1989'], isNull);
  });

  test('Q123 exposes current values for all light-quark children', () async {
    final entry = await db.requireEntryByPdgid('Q123');
    final view = await PdgRepository(db).loadEntry(entry);
    expect(
      view.children.map((c) => c.pdgid),
      containsAll(['Q123UM', 'Q123DM', 'Q123MR4', 'Q123MR0', 'Q123SM']),
    );
    final u = view.selectionForChild(
      view.children.firstWhere((c) => c.pdgid == 'Q123UM').id,
    );
    expect(u.preferred, isNotNull);
    expect(u.preferred!.unitText, 'MeV');
    expect(u.preferred!.value, closeTo(2.16, 0.2));
    final ratio = view.selectionForChild(
      view.children.firstWhere((c) => c.pdgid == 'Q123MR0').id,
    );
    expect(ratio.preferred, isNotNull);
  });
}
