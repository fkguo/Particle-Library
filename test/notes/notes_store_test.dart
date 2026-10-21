import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/notes/notes.dart';
import 'package:pdgapp/features/notes/notes_format.dart';
import 'package:sqlite3/sqlite3.dart';

Matcher throwsNotes(NotesErrorCode code) =>
    throwsA(isA<NotesException>().having((error) => error.code, 'code', code));

void main() {
  late Directory tempDir;
  late String dbPath;
  final stores = <NotesStore>[];

  Future<NotesStore> openStore({String? path}) async {
    final store = await NotesStore.open(overridePath: path ?? dbPath);
    stores.add(store);
    return store;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdgapp-notes-');
    dbPath = '${tempDir.path}/ParticleDesk/user.db';
  });

  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // A failed open can leave a WAL/SHM pair briefly; the OS temp dir is
      // still safely disposable.
    }
  });

  test('create persists note, anchors and tags and survives reopen', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'D0 笔记',
      bodyMarkdown: '**D0** 寿命与 [论文](https://example.com) 讨论。',
      anchors: [
        NoteAnchorInput.pdgid(
          'S032M',
          snapshotHash: 'hash-1',
          targetLabel: 'D0 (S032M)',
          context: {'table': 'MEASUREMENT'},
        ),
        NoteAnchorInput.referenceDoi(
          '10.1103/PhysRevD.98.030001',
          snapshotHash: 'hash-1',
          targetLabel: 'Review of Particle Physics',
        ),
      ],
      tags: [' lifetime ', 'D0', 'lifetime', ''],
    );

    expect(note.title, 'D0 笔记');
    expect(note.bodyMarkdown, contains('**D0**'));
    expect(note.bodyPlain, contains('D0'));
    expect(note.bodyPlain, isNot(contains('https://')));
    expect(note.revision, 1);
    expect(note.uuid, isNotEmpty);
    expect(note.uuid, isNot(note.id));
    expect(note.createdAt.isUtc, isTrue);
    expect(note.updatedAt.isUtc, isTrue);
    expect(note.anchors, hasLength(2));
    expect(note.tagNames, ['D0', 'lifetime']);

    final pdgAnchor = note.anchorFor('pdgid', 'S032M', snapshotHash: 'hash-1');
    expect(pdgAnchor, isNotNull);
    expect(pdgAnchor!.targetId, 'pdgid:S032M');
    expect(pdgAnchor.status, NoteAnchorStatus.exact);
    expect(pdgAnchor.isResolved, isTrue);
    expect(pdgAnchor.snapshotHash, 'hash-1');
    expect(pdgAnchor.targetLabel, 'D0 (S032M)');
    expect(pdgAnchor.context, {'table': 'MEASUREMENT'});

    final doiAnchor = note.anchorFor(
      'reference',
      'doi:10.1103/physrevd.98.030001',
    );
    expect(doiAnchor?.targetId, 'reference:doi:10.1103/physrevd.98.030001');

    await store.close();
    final reopened = await openStore();
    final loaded = await reopened.get(note.id);
    expect(loaded, isNotNull);
    expect(loaded!.title, note.title);
    expect(loaded.bodyPlain, note.bodyPlain);
    expect(loaded.revision, 1);
    expect(loaded.anchors, hasLength(2));
    expect(loaded.tagNames, ['D0', 'lifetime']);
    expect(loaded.anchorFor(' PDGID ', ' S032M ')?.context, {
      'table': 'MEASUREMENT',
    });

    final json = loaded.toJson();
    expect(jsonEncode(json), isNotEmpty);
    expect(json['tags'], ['D0', 'lifetime']);
    expect((json['anchors'] as List).first['targetId'], 'pdgid:S032M');
  });

  test(
    'update replaces anchors/tags, bumps revision and validates atomically',
    () async {
      final store = await openStore();
      final note = await store.create(
        title: 'old',
        bodyMarkdown: 'old body',
        anchors: [NoteAnchorInput.pdgid('S032M')],
        tags: ['old'],
      );

      final updated = await store.update(
        note.id,
        title: 'new',
        bodyMarkdown: 'new 内容',
        anchors: [
          NoteAnchorInput.referenceDoc(
            '42',
            snapshotHash: 'hash-2',
            targetLabel: 'Doc 42',
          ),
        ],
        tags: ['new', 'new', ' '],
      );

      expect(updated.title, 'new');
      expect(updated.bodyMarkdown, 'new 内容');
      expect(updated.bodyPlain, 'new 内容');
      expect(updated.revision, 2);
      expect(updated.anchors, hasLength(1));
      expect(updated.anchors.single.targetId, 'reference:doc:42');
      expect(updated.anchors.single.snapshotHash, 'hash-2');
      expect(updated.tagNames, ['new']);
      expect(updated.updatedAt.isBefore(note.updatedAt), isFalse);

      // Invalid anchor input is rejected before the transaction starts, so the
      // previous update remains intact.
      await expectLater(
        store.update(
          note.id,
          title: 'should not apply',
          anchors: [const NoteAnchorInput(targetKind: '', targetKey: '')],
        ),
        throwsNotes(NotesErrorCode.invalidInput),
      );
      final unchanged = await store.get(note.id);
      expect(unchanged!.title, 'new');
      expect(unchanged.revision, 2);
      expect(unchanged.anchors.single.targetId, 'reference:doc:42');

      // Null arguments leave fields unchanged.
      final stillSame = await store.update(note.id);
      expect(stillSame.title, 'new');
      expect(stillSame.revision, 3);
      expect(stillSame.anchors.single.targetId, 'reference:doc:42');
    },
  );

  test(
    'a mid-transaction write failure rolls back note, anchors and tags',
    () async {
      final store = await openStore();
      await store.close();

      final db = sqlite3.open(dbPath);
      db.execute('''
      CREATE TRIGGER notes_fail_tags
      BEFORE INSERT ON note_tags
      BEGIN
        SELECT RAISE(ABORT, 'injected tag failure');
      END;
    ''');
      db.dispose();

      final reopened = await openStore();
      await expectLater(
        reopened.create(
          title: 'rolled back',
          bodyMarkdown: 'body',
          anchors: [NoteAnchorInput.pdgid('S032M')],
          tags: ['will-fail'],
        ),
        throwsA(anything),
      );

      final check = sqlite3.open(dbPath);
      try {
        expect(check.select('SELECT COUNT(*) AS n FROM notes').first['n'], 0);
        expect(
          check.select('SELECT COUNT(*) AS n FROM note_anchors').first['n'],
          0,
        );
        expect(
          check.select('SELECT COUNT(*) AS n FROM note_tags').first['n'],
          0,
        );
      } finally {
        check.dispose();
      }
    },
  );

  test('legacy measurement markers are removed from note bodies', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'measurement note',
      bodyMarkdown: '> 1.0 ± 0.1\n<!-- measurement:42 -->\n',
    );
    expect(await store.cleanupLegacyMeasurementMarkers(), 1);
    final cleaned = await store.get(note.id);
    expect(cleaned!.bodyMarkdown, '> 1.0 ± 0.1');
    expect(cleaned.bodyMarkdown, isNot(contains('<!--')));
  });

  test('distinct backlink count does not double-count multi-anchor notes', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'two anchors',
      anchors: [
        NoteAnchorInput.referenceDoi('10.1/x'),
        NoteAnchorInput.referenceDoc('DOC-X'),
      ],
    );
    final targets = [
      NoteTarget.referenceDoi('10.1/x'),
      NoteTarget.referenceDoc('DOC-X'),
    ];
    expect(await store.countDistinctForTargets(targets), 1);
    expect(note.anchors, hasLength(2));
  });

  test('JSON import round-trips notes, anchors, tags and UUIDs', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-import-');
    final source = await openStore();
    final original = await source.create(
      title: 'import me',
      bodyMarkdown: 'Body [D0](pdgid:S008)',
      anchors: [NoteAnchorInput.pdgid('S008')],
      tags: ['todo'],
    );
    final target = await NotesStore.open(
      overridePath: '${dir.path}/target.db',
    );
    stores.add(target);
    final first = await target.importJson([original.toJson()]);
    expect(first.added, 1);
    expect(first.skipped, 0);
    final imported = await target.noteByUuid(original.uuid);
    expect(imported, isNotNull);
    expect(imported!.tagNames, ['todo']);
    expect(imported.bodyMarkdown, contains('[D0](pdgid:S008)'));
    expect(imported.createdAt, original.createdAt);
    expect(imported.anchors.single.targetId, 'pdgid:S008');
    final again = await target.importJson([original.toJson()]);
    expect(again.skipped, 1);
    await target.close();
    stores.remove(target);
    await dir.delete(recursive: true);
  });

  test('tags can be counted and combined as filters', () async {
    final store = await openStore();
    final a = await store.create(title: 'tagged a', tags: ['todo', 'pdg']);
    await store.create(title: 'tagged b', tags: ['todo']);
    final counts = await store.tagCounts();
    expect(counts['todo'], 2);
    expect(counts['pdg'], 1);
    final filtered = await store.notesByTags(['todo', 'pdg']);
    expect(filtered.single.id, a.id);
  });

  test('tags can be renamed and deleted across notes', () async {
    final store = await openStore();
    await store.create(title: 'a', tags: ['todo', 'pdg']);
    await store.create(title: 'b', tags: ['todo']);
    expect(await store.renameTag('todo', 'task'), 2);
    expect((await store.tagCounts())['task'], 2);
    expect((await store.tagCounts())['todo'], isNull);
    expect(await store.deleteTag('task'), 2);
    expect((await store.tagCounts())['task'], isNull);
    expect((await store.tagCounts())['pdg'], 1);
  });

  test('measurement anchors are stored and queried like other targets', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'D0 lifetime',
      anchors: [NoteAnchorInput.measurement('S032M:42')],
    );
    expect(
      (await store.notesForTarget(
        NoteTargetKinds.measurement,
        'S032M:42',
      )).single.id,
      note.id,
    );
    expect(
      (await store.countForTargets([
        NoteTarget.measurement('S032M:42'),
      ])).values.first,
      1,
    );
  });

  test('anchored notes are not also reported as textual mentions', () async {
    final store = await openStore();
    await store.create(
      title: 'anchored',
      bodyMarkdown: 'See [D0](pdgid:S008).',
      anchors: [NoteAnchorInput.pdgid('S008')],
    );
    expect(
      await store.notesMentioningTargets([NoteTarget.pdgid('S008')]),
      isEmpty,
    );
  });

  test('body links are discoverable as textual mentions', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'linked in prose',
      bodyMarkdown: 'See [D0](pdgid:S008) and [the paper](reference:doi:10.1/x).',
    );
    expect(
      (await store.notesMentioningTargets([
        NoteTarget.pdgid('S008'),
      ])).single.id,
      note.id,
    );
    expect(
      (await store.notesMentioningTargets([
        NoteTarget.referenceDoi('10.1/x'),
      ])).single.id,
      note.id,
    );
    expect(
      await store.notesMentioningTargets([NoteTarget.pdgid('S999')]),
      isEmpty,
    );
  });

  test('soft-deleted notes are listed in Trash and can be restored', () async {
    final store = await openStore();
    final note = await store.create(title: 'recover me');
    await store.delete(note.id);
    expect(await store.recent(), isEmpty);
    expect((await store.deleted()).single.id, note.id);
    await store.restore(note.id);
    expect((await store.recent()).single.id, note.id);
    expect(await store.deleted(), isEmpty);
  });

  test('search finds notes by PDG anchor, tag and collection metadata', () async {
    final store = await openStore();
    final collection = await store.createCollection('Lifetime');
    final note = await store.create(
      title: 'Pion note',
      bodyMarkdown: 'body without identifiers',
      anchors: [NoteAnchorInput.pdgid('S008')],
      tags: ['lifetime'],
      collectionIds: [collection.id],
    );
    expect((await store.search('S008')).single.id, note.id);
    expect((await store.search('lifetime')).single.id, note.id);
    expect((await store.search('Lifetime')).single.id, note.id);
  });

  test('collection-scoped search uses the same metadata predicates', () async {
    final store = await openStore();
    final selected = await store.createCollection('Selected');
    final other = await store.createCollection('Other');
    final note = await store.create(
      title: 'Metadata note',
      anchors: [NoteAnchorInput.pdgid('S008')],
      collectionIds: [selected.id],
    );
    expect(
      (await store.search('S008', collectionId: selected.id)).single.id,
      note.id,
    );
    expect(await store.search('S008', collectionId: other.id), isEmpty);
  });

  test('collections are many-to-many and cascade on deletion', () async {
    final store = await openStore();
    final reviews = await store.createCollection('Reviews');
    final lifetime = await store.createCollection('Lifetime');

    final note = await store.create(
      title: 'D0',
      collectionIds: [reviews.id, lifetime.id],
    );
    expect(note.collections.map((c) => c.name), ['Lifetime', 'Reviews']);
    expect(await store.notesInCollection(reviews.id), hasLength(1));
    expect(await store.notesInCollection(lifetime.id), hasLength(1));

    final other = await store.create(title: 'B+', collectionIds: [lifetime.id]);
    expect(await store.notesInCollection(lifetime.id), hasLength(2));
    expect(other.collections.single.name, 'Lifetime');

    await store.setNoteCollections(note.id, [reviews.id]);
    final updated = await store.get(note.id);
    expect(updated!.collections.single.name, 'Reviews');

    await store.deleteCollection(lifetime.id);
    expect((await store.get(other.id))!.collections, isEmpty);
    expect(await store.collections(), hasLength(1));
  });

  test('stale revisions are rejected instead of overwriting newer text', () async {
    final store = await openStore();
    final note = await store.create(title: 'first', bodyMarkdown: 'v1');
    final newer = await store.update(note.id, bodyMarkdown: 'v2');
    expect(newer.revision, note.revision + 1);

    await expectLater(
      store.update(
        note.id,
        bodyMarkdown: 'stale',
        expectedRevision: note.revision,
      ),
      throwsNotes(NotesErrorCode.conflict),
    );
    expect((await store.get(note.id))!.bodyMarkdown, 'v2');
  });

  test('collection names are trimmed and unique case-insensitively', () async {
    final store = await openStore();
    final created = await store.createCollection('  Reviews  ');
    expect(created.name, 'Reviews');
    await expectLater(
      store.createCollection('reviews'),
      throwsNotes(NotesErrorCode.invalidInput),
    );
    await expectLater(
      store.createCollection('   '),
      throwsNotes(NotesErrorCode.invalidInput),
    );
    final renamed = await store.renameCollection(created.id, 'Papers');
    expect(renamed.name, 'Papers');
  });

  test('hashtag tags parse with comma-separated tags', () {
    expect(
      parseNoteTags('#lifetime #D0, lifetime, #CP'),
      ['lifetime', 'D0', 'CP'],
    );
    expect(parseNoteTags('two words, #tag'), ['two words', 'tag']);
  });

  test('soft delete hides the note but retains data for export', () async {
    final store = await openStore();
    final note = await store.create(
      title: 'to delete',
      bodyMarkdown: 'unique 删除内容',
      anchors: [NoteAnchorInput.pdgid('S032M')],
      tags: ['delete-me'],
    );

    await store.delete(note.id);
    expect(await store.recent(), isEmpty);
    expect(await store.search('删除'), isEmpty);
    expect(await store.notesForTarget('pdgid', 'S032M'), isEmpty);
    expect(await store.countForTargets([NoteTarget.pdgid('S032M')]), {
      NoteTarget.pdgid('S032M'): 0,
    });
    expect(await store.allForExport(), isEmpty);

    final retained = await store.get(note.id);
    expect(retained, isNotNull);
    expect(retained!.isDeleted, isTrue);
    expect(retained.deletedAt, isNotNull);
    expect(retained.anchors, hasLength(1));
    expect(retained.tagNames, ['delete-me']);

    final exported = await store.allForExport(includeDeleted: true);
    expect(exported, hasLength(1));
    expect(exported.single.id, note.id);
    expect(exported.single.isDeleted, isTrue);

    // Idempotent delete; missing notes are reported.
    await store.delete(note.id);
    await expectLater(
      store.delete('missing-note'),
      throwsNotes(NotesErrorCode.notFound),
    );
    await expectLater(
      store.update(note.id, title: 'nope'),
      throwsNotes(NotesErrorCode.notFound),
    );
  });

  test(
    'notesForTarget filters by snapshot and returns each note once',
    () async {
      final store = await openStore();
      final first = await store.create(
        title: 'first',
        anchors: [NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1')],
      );
      final second = await store.create(
        title: 'second',
        anchors: [NoteAnchorInput.pdgid('S032M', snapshotHash: 'h2')],
      );
      final third = await store.create(
        title: 'third',
        anchors: [
          NoteAnchorInput.referenceDoi('10.1/x', snapshotHash: 'h1'),
          NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1'),
        ],
      );
      final fourth = await store.create(
        title: 'fourth',
        anchors: [
          NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1'),
          NoteAnchorInput.pdgid('S032M', snapshotHash: 'h2'),
        ],
      );

      final anySnapshot = await store.notesForTarget('pdgid', 'S032M');
      expect(anySnapshot.map((note) => note.id).toSet(), {
        first.id,
        second.id,
        third.id,
        fourth.id,
      });
      expect(anySnapshot, hasLength(4));
      expect(anySnapshot.where((note) => note.id == fourth.id), hasLength(1));

      final h1 = await store.notesForTarget(
        'PDGID',
        'S032M',
        snapshotHash: 'h1',
      );
      expect(h1.map((note) => note.id).toSet(), {
        first.id,
        third.id,
        fourth.id,
      });

      final h2 = await store.notesForTarget(
        'pdgid',
        'S032M',
        snapshotHash: 'h2',
      );
      expect(h2.map((note) => note.id).toSet(), {second.id, fourth.id});

      final limited = await store.notesForTarget('pdgid', 'S032M', limit: 2);
      expect(limited, hasLength(2));

      expect(await store.notesForTarget('pdgid', 'UNKNOWN'), isEmpty);
      await expectLater(
        store.notesForTarget(' ', 'S032M'),
        throwsNotes(NotesErrorCode.invalidInput),
      );
      await expectLater(
        store.notesForTarget('pdgid', ' '),
        throwsNotes(NotesErrorCode.invalidInput),
      );
    },
  );

  test(
    'countForTargets is a batch, deduplicates notes and returns zeros',
    () async {
      final store = await openStore();
      final first = await store.create(
        title: 'first',
        anchors: [
          NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1'),
          NoteAnchorInput.pdgid('S032M', snapshotHash: 'h2'),
        ],
      );
      await store.create(
        title: 'second',
        anchors: [NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1')],
      );
      await store.create(
        title: 'reference',
        anchors: [NoteAnchorInput.referenceDoi('10.1/X', snapshotHash: 'h1')],
      );

      final counts = await store.countForTargets([
        NoteTarget.pdgid('S032M'),
        NoteTarget.pdgid('S032M', snapshotHash: 'h1'),
        NoteTarget.pdgid('S032M', snapshotHash: 'h2'),
        NoteTarget.referenceDoi('10.1/x'),
        NoteTarget.pdgid('UNKNOWN'),
        // Duplicate request: still one map entry.
        NoteTarget.pdgid('S032M'),
      ]);

      expect(counts, hasLength(5));
      expect(counts[NoteTarget.pdgid('S032M')], 2);
      expect(counts[NoteTarget.pdgid('S032M', snapshotHash: 'h1')], 2);
      expect(counts[NoteTarget.pdgid('S032M', snapshotHash: 'h2')], 1);
      expect(counts[NoteTarget.referenceDoi('10.1/x')], 1);
      expect(counts[NoteTarget.pdgid('UNKNOWN')], 0);

      await store.delete(first.id);
      final afterDelete = await store.countForTargets([
        NoteTarget.pdgid('S032M'),
        NoteTarget.pdgid('S032M', snapshotHash: 'h1'),
        NoteTarget.pdgid('S032M', snapshotHash: 'h2'),
      ]);
      expect(afterDelete[NoteTarget.pdgid('S032M')], 1);
      expect(afterDelete[NoteTarget.pdgid('S032M', snapshotHash: 'h1')], 1);
      expect(afterDelete[NoteTarget.pdgid('S032M', snapshotHash: 'h2')], 0);
      expect(await store.countForTargets(const <NoteTarget>[]), isEmpty);
    },
  );

  test('CJK substring search and LIKE escaping', () async {
    final store = await openStore();
    await store.create(title: '轻子', bodyMarkdown: '弱相互作用与轻子衰变宽度');
    await store.create(title: '重子', bodyMarkdown: '重子质量');
    await store.create(
      title: 'Baryon',
      bodyMarkdown: 'Baryon WIDTH and 100% complete',
    );
    await store.create(
      title: 'Escapes',
      bodyMarkdown: r'literal 100%_done and a\b',
    );
    await store.create(title: '中文标题', bodyMarkdown: '');

    final decay = await store.search('衰变');
    expect(decay, hasLength(1));
    expect(decay.single.title, '轻子');

    final lepton = await store.search('轻子');
    expect(lepton, hasLength(1));
    expect(lepton.single.title, '轻子');

    expect((await store.search('中文')).single.title, '中文标题');

    // ASCII case-insensitivity comes from LIKE.
    expect((await store.search('WIDTH')).single.title, 'Baryon');
    expect((await store.search('width')).single.title, 'Baryon');

    // '%' must be escaped: without escaping this would match every note.
    expect((await store.search('%')).map((n) => n.title).toSet(), {
      'Baryon',
      'Escapes',
    });
    expect((await store.search('100%')), hasLength(2));
    expect((await store.search('100%_done')).single.title, 'Escapes');
    expect((await store.search('_')).single.title, 'Escapes');
    expect((await store.search(r'a\b')).single.title, 'Escapes');

    expect(await store.search('   '), isEmpty);
    await expectLater(
      store.search('x', limit: 0),
      throwsNotes(NotesErrorCode.invalidInput),
    );
  });

  test(
    'unresolved returns only fuzzy/unresolved anchors of active notes',
    () async {
      final store = await openStore();
      final active = await store.create(
        title: 'active',
        anchors: [
          NoteAnchorInput.pdgid('S032M'),
          NoteAnchorInput.pdgid(
            'S033M',
            status: NoteAnchorStatus.fuzzy,
            targetLabel: 'fuzzy',
          ),
          NoteAnchorInput.referenceDoc(
            '77',
            status: NoteAnchorStatus.unresolved,
          ),
        ],
      );
      final deleted = await store.create(
        title: 'deleted',
        anchors: [
          NoteAnchorInput.pdgid('S032M', status: NoteAnchorStatus.fuzzy),
        ],
      );
      await store.delete(deleted.id);

      final unresolved = await store.unresolved();
      expect(unresolved, hasLength(2));
      expect(unresolved.every((anchor) => anchor.noteId == active.id), isTrue);
      expect(
        unresolved.map((anchor) => anchor.status),
        containsAll([NoteAnchorStatus.fuzzy, NoteAnchorStatus.unresolved]),
      );
      expect(await store.unresolved(limit: 1), hasLength(1));
      await expectLater(
        store.unresolved(limit: 0),
        throwsNotes(NotesErrorCode.invalidInput),
      );
    },
  );

  test('user_version v2 is created once and reopening is idempotent', () async {
    final store = await openStore();
    final diagnostics = await store.diagnostics();
    expect(diagnostics['userVersion'], 2);
    expect(diagnostics['journalMode'], 'wal');
    expect(diagnostics['synchronous'], 2);
    expect(diagnostics['foreignKeys'], 1);
    expect(diagnostics['busyTimeout'], 5000);
    expect(diagnostics['trustedSchema'], 0);

    final note = await store.create(title: 'persist');
    await store.close();

    var raw = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    expect(raw.userVersion, 2);
    final tables = raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'])
        .toSet();
    raw.dispose();
    expect(tables, containsAll(['notes', 'note_anchors', 'note_tags', 'meta']));

    final reopened = await openStore();
    expect((await reopened.get(note.id))?.title, 'persist');
    expect((await reopened.diagnostics())['userVersion'], 2);

    // Opening an existing v2 database must not rerun the migration.
    await reopened.close();
    raw = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    expect(raw.userVersion, 2);
    raw.dispose();
    final third = await openStore();
    expect(await third.recent(), hasLength(1));
  });

  test('newer user_version is refused and left untouched', () async {
    final path = '${tempDir.path}/future.db';
    final raw = sqlite3.open(path, mode: OpenMode.readWriteCreate);
    raw.userVersion = 3;
    raw.execute('CREATE TABLE future_only(x TEXT)');
    raw.dispose();

    await expectLater(
      NotesStore.open(overridePath: path),
      throwsNotes(NotesErrorCode.unsupportedSchema),
    );

    final check = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(check.userVersion, 3);
    expect(
      check.select("SELECT name FROM sqlite_master WHERE name = 'future_only'"),
      hasLength(1),
    );
    expect(
      check.select("SELECT name FROM sqlite_master WHERE name = 'notes'"),
      isEmpty,
    );
    check.dispose();
  });

  test('user_version 0 with existing tables is refused, not reset', () async {
    final path = '${tempDir.path}/foreign.db';
    final raw = sqlite3.open(path, mode: OpenMode.readWriteCreate);
    raw.execute('CREATE TABLE foreign_data(value TEXT)');
    raw.execute("INSERT INTO foreign_data(value) VALUES ('keep me')");
    raw.dispose();

    await expectLater(
      NotesStore.open(overridePath: path),
      throwsNotes(NotesErrorCode.unsupportedSchema),
    );

    final check = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(check.userVersion, 0);
    expect(
      check.select('SELECT value FROM foreign_data').single['value'],
      'keep me',
    );
    expect(
      check.select("SELECT name FROM sqlite_master WHERE name = 'notes'"),
      isEmpty,
    );
    check.dispose();
  });

  test('corrupt database throws a typed error and is preserved', () async {
    final path = '${tempDir.path}/corrupt.db';
    final original = [
      for (var index = 0; index < 4096; index++) index.isEven ? 0xFF : 0x00,
    ];
    final file = File(path);
    await file.writeAsBytes(original, flush: true);

    await expectLater(
      NotesStore.open(overridePath: path),
      throwsNotes(NotesErrorCode.corrupt),
    );

    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), original);
  });

  test('truncated database throws a typed error and is preserved', () async {
    final store = await openStore();
    await store.create(title: 'large enough', bodyMarkdown: 'x' * 20000);
    await store.close();

    final file = File(dbPath);
    final length = await file.length();
    expect(length, greaterThan(4096));
    final handle = await file.open(mode: FileMode.append);
    await handle.truncate(length ~/ 2);
    await handle.close();
    final truncatedLength = await file.length();

    await expectLater(
      NotesStore.open(overridePath: dbPath),
      throwsNotes(NotesErrorCode.corrupt),
    );
    expect(await file.length(), truncatedLength);
  });

  test('unwritable/unavailable database directory is reported', () async {
    final blocker = File('${tempDir.path}/not-a-directory');
    await blocker.writeAsString('file, not a directory');
    final path = '${blocker.path}/user.db';

    await expectLater(
      NotesStore.open(overridePath: path),
      throwsNotes(NotesErrorCode.unavailable),
    );
  });

  test('backupTo creates a verified copy and never overwrites', () async {
    final store = await openStore();
    await store.create(
      title: 'backup me',
      bodyMarkdown: '备份内容',
      anchors: [NoteAnchorInput.pdgid('S032M', snapshotHash: 'h1')],
      tags: ['backup'],
    );

    final backupPath = '${tempDir.path}/backup/user.db';
    await store.backupTo(backupPath);
    expect(await File(backupPath).exists(), isTrue);

    final backup = sqlite3.open(backupPath, mode: OpenMode.readOnly);
    expect(backup.userVersion, 2);
    expect(backup.select('PRAGMA quick_check').single.values.first, 'ok');
    expect(
      backup.select('SELECT title FROM notes').single['title'],
      'backup me',
    );
    expect(backup.select('SELECT tag FROM note_tags').single['tag'], 'backup');
    backup.dispose();

    final size = await File(backupPath).length();
    await expectLater(
      store.backupTo(backupPath),
      throwsNotes(NotesErrorCode.backupFailed),
    );
    expect(await File(backupPath).length(), size);

    final leftovers = tempDir
        .listSync(recursive: true)
        .where((entity) => entity.path.contains('.partial-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('missing notes are reported and get returns null', () async {
    final store = await openStore();
    expect(await store.get('missing'), isNull);
    await expectLater(
      store.get('   '),
      throwsNotes(NotesErrorCode.invalidInput),
    );
    await expectLater(
      store.update('missing', title: 'x'),
      throwsNotes(NotesErrorCode.notFound),
    );
    await expectLater(
      store.recent(limit: 0),
      throwsNotes(NotesErrorCode.invalidInput),
    );
  });

  test('anchor factories produce canonical keys', () {
    final pdgid = NoteAnchorInput.pdgid(' S032M ');
    expect(pdgid.targetId, 'pdgid:S032M');

    final doi = NoteAnchorInput.referenceDoi('10.1103/PhysRevD.98.030001');
    expect(doi.targetKind, 'reference');
    expect(doi.targetKey, 'doi:10.1103/physrevd.98.030001');
    expect(doi.targetId, 'reference:doi:10.1103/physrevd.98.030001');

    final document = NoteAnchorInput.referenceDoc(' 123 ');
    expect(document.targetKey, 'doc:123');
    expect(document.targetId, 'reference:doc:123');

    expect(
      NoteTarget(kind: ' PDGID ', key: ' S032M ', snapshotHash: '  '),
      NoteTarget.pdgid('S032M'),
    );

    expect(NoteAnchorStatus.fromWireName('resolved'), NoteAnchorStatus.exact);
    expect(NoteAnchorStatus.fromWireName('fuzzy'), NoteAnchorStatus.fuzzy);
    expect(
      NoteAnchorStatus.fromWireName('future-status'),
      NoteAnchorStatus.unresolved,
    );
  });

  test('empty reference anchors are rejected', () {
    expect(() => NoteTarget.referenceDoi('   '), throwsArgumentError);
    expect(() => NoteTarget.referenceDoc(''), throwsArgumentError);
    expect(() => NoteAnchorInput.referenceDoi(''), throwsArgumentError);
    expect(() => NoteAnchorInput.referenceDoc('  '), throwsArgumentError);
  });

  group('plainTextFromMarkdown', () {
    test('keeps CJK text and strips common Markdown markers', () {
      expect(
        plainTextFromMarkdown('# 标题\n\n**轻子**与__重子__ [论文](https://x.y)'),
        '标题\n\n轻子与重子 论文',
      );
    });

    test('keeps fenced code content and single underscores', () {
      expect(
        plainTextFromMarkdown('`body_plain`\n```\nfinal x = 1;\n```'),
        'body_plain\nfinal x = 1;',
      );
    });

    test('does not strip HTML or emphasis inside fenced code', () {
      const source =
          '```cpp\n#include <stdio.h>\nstd::vector<int> v;\n**not bold**\n[link](x)\n```';
      final plain = plainTextFromMarkdown(source);
      expect(plain, contains('#include <stdio.h>'));
      expect(plain, contains('std::vector<int> v;'));
      expect(plain, contains('**not bold**'));
      expect(plain, contains('[link](x)'));
    });
  });
}
