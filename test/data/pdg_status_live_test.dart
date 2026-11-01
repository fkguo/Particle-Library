import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/pdg_notes.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DirectSqlExecutor executor;
  late PdgDatabase db;

  setUpAll(() async {
    if (!File('assets/pdg_notes_2026.sqlite').existsSync()) {
      fail('The pdgLive sidecar asset is missing.');
    }
    executor = await DirectSqlExecutor.open('assets/pdgall-2026.0.sqlite');
    db = await PdgDatabase.open(
      executor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
  });

  setUp(PdgNotes.resetCache);

  tearDownAll(() async {
    await executor.dispose();
  });

  test('the sidecar stores stars and the meson established bullet', () async {
    final stars = await PdgNotes.statusFor('S016');
    expect(stars, isNotNull);
    expect(stars!.stars, 4);
    expect(stars.established, isFalse);
    expect(stars.marker, '****');

    final evidence = await PdgNotes.statusFor('B009');
    expect(evidence!.stars, 2);

    final marginal = await PdgNotes.statusFor('B159');
    expect(marginal!.stars, 1);

    final meson = await PdgNotes.statusFor('S008');
    expect(meson, isNotNull);
    expect(meson!.stars, isNull);
    expect(meson.established, isTrue);
    expect(meson.marker, '•');
    expect((await PdgNotes.statusFor('M005'))!.established, isTrue);
  });

  test('pages without a published mark return null', () async {
    // pi_1(1400) has no established bullet on the meson group page.
    expect(await PdgNotes.statusFor('M111'), isNull);
    // Xi_bc has no star on the bottom-baryon group page.
    expect(await PdgNotes.statusFor('B198'), isNull);
    expect(await PdgNotes.statusFor('NOT-A-PDGID'), isNull);
  });

  test('the patch table has the requested columns and faithful marks', () {
    final database = sqlite3.open(
      'assets/pdg_notes_2026.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      final columns = {
        for (final row in database.select(
          'PRAGMA table_info(pdg_particle_status)',
        ))
          row['name'] as String,
      };
      expect(columns, containsAll(['pdgid', 'stars', 'established']));

      final totals = database
          .select(
            'SELECT COUNT(*) AS total, '
            'SUM(stars IS NOT NULL) AS stars, '
            'SUM(established = 1) AS dots FROM pdg_particle_status',
          )
          .first;
      expect(totals['total'], 341);
      expect(totals['stars'], 189);
      expect(totals['dots'], 152);

      // A row is either a star-rated baryon or a bullet-marked meson, never an
      // invented combination of both.
      final mixed = database
          .select(
            'SELECT COUNT(*) AS n FROM pdg_particle_status '
            'WHERE stars IS NOT NULL AND established = 1',
          )
          .first['n'];
      expect(mixed, 0);
      final badStars = database
          .select(
            'SELECT COUNT(*) AS n FROM pdg_particle_status '
            'WHERE stars IS NOT NULL AND (stars < 1 OR stars > 4)',
          )
          .first['n'];
      expect(badStars, 0);

      // Every derived status row must be traceable to a scanned source row
      // with exactly the same mark.
      final orphaned = database
          .select(
            'SELECT COUNT(*) AS n FROM pdg_particle_status s '
            'LEFT JOIN pdg_particle_status_scan c ON c.pdgid = s.pdgid '
            'WHERE c.pdgid IS NULL '
            'OR c.stars IS NOT s.stars '
            'OR c.established IS NOT s.established',
          )
          .first['n'];
      expect(orphaned, 0);

      // A star-rated row must come from a baryon group page; a bullet-marked
      // row must come from a meson group page.
      final wrongSource = database
          .select(
            'SELECT COUNT(*) AS n FROM pdg_particle_status s '
            'JOIN pdg_particle_status_scan c ON c.pdgid = s.pdgid '
            "WHERE (s.stars IS NOT NULL AND c.group_node NOT LIKE 'BXXX%') "
            "OR (s.established = 1 AND c.group_node NOT LIKE 'MXXX%')",
          )
          .first['n'];
      expect(wrongSource, 0);

      final sourceMismatch = database
          .select(
            'SELECT COUNT(*) AS n FROM pdg_particle_status_scan '
            "WHERE source NOT LIKE '%node=' || group_node",
          )
          .first['n'];
      expect(sourceMismatch, 0);
    } finally {
      database.dispose();
    }
  });

  test('every status row points at a catalog root with content', () async {
    final statuses = await PdgNotes.statuses();
    final roots = {
      for (final root in await db.catalogRoots()) root.entry.pdgid: root,
    };
    expect(statuses, hasLength(341));
    final withoutParticle = <String>[];
    for (final entry in statuses.entries) {
      final root = roots[entry.key];
      expect(root, isNotNull, reason: '${entry.key} is not a catalog root');
      expect(root!.hasContent, isTrue);
      if (root.particleCount == 0) withoutParticle.add(entry.key);
      expect(entry.value.isEmpty, isFalse);
    }
    // The two B-meson admixture listings carry the PDG Live bullet but have no
    // particle identity row of their own; every other status has particles.
    expect(withoutParticle..sort(), ['S049', 'S051']);
  });

  test('the existing pdgLive notes and review links are preserved', () async {
    final note = await PdgNotes.forPdgid('M252');
    expect(note, isNotNull);
    expect(note!.was, contains('2400'));
    final reviews = await PdgNotes.reviewFilesFor('S010');
    expect(reviews, hasLength(3));
    final database = sqlite3.open(
      'assets/pdg_notes_2026.sqlite',
      mode: OpenMode.readOnly,
    );
    try {
      expect(
        database.select('SELECT COUNT(*) AS n FROM pdg_notes').first['n'],
        299,
      );
      expect(
        database
            .select('SELECT COUNT(*) AS n FROM pdg_note_reviews')
            .first['n'],
        greaterThanOrEqualTo(67),
      );
    } finally {
      database.dispose();
    }
  });
}
