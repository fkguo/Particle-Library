import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/notes/notes_format.dart';
import 'package:pdgapp/notes/notes.dart';

void main() {
  late Directory tempDir;
  late NotesStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdgapp-collections-p0-');
    store = await NotesStore.open(overridePath: '${tempDir.path}/user.db');
  });

  tearDown(() async {
    await store.close();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Disposable temp dir; WAL files may linger briefly.
    }
  });

  test('collection summaries count active notes', () async {
    final collection = await store.createCollection('Project');
    final note = await store.create(title: 'A', collectionIds: [collection.id]);
    await store.create(title: 'B');
    final summaries = await store.collectionSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.name, 'Project');
    expect(summaries.single.activeNoteCount, 1);

    await store.delete(note.id);
    final afterDelete = await store.collectionSummaries();
    expect(afterDelete.single.activeNoteCount, 0);
  });

  test('edge add/remove is idempotent and does not reorder notes', () async {
    final collection = await store.createCollection('Project');
    final note = await store.create(title: 'A');
    final before = note.updatedAt;

    await store.addNoteToCollection(note.id, collection.id);
    await store.addNoteToCollection(note.id, collection.id);
    final joined = (await store.noteById(note.id))!;
    expect(joined.collections.single.id, collection.id);
    expect(joined.updatedAt, before);

    await store.removeNoteFromCollection(note.id, collection.id);
    await store.removeNoteFromCollection(note.id, collection.id);
    expect((await store.noteById(note.id))!.collections, isEmpty);
  });

  test('unfiled and collection queries support offset', () async {
    final collection = await store.createCollection('Project');
    for (var i = 0; i < 3; i++) {
      await store.create(title: 'note-$i', collectionIds: [collection.id]);
    }
    await store.create(title: 'unfiled');

    expect((await store.unfiled()).single.title, 'unfiled');
    expect(await store.unfiled(offset: 1), isEmpty);

    final first = await store.notesInCollection(collection.id, limit: 1);
    final second = await store.notesInCollection(
      collection.id,
      limit: 1,
      offset: 1,
    );
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(first.single.id, isNot(second.single.id));
  });

  test('JSON v2 exports and imports empty collections', () async {
    await store.createCollection('Empty project');
    final json = notesExportJson(
      await store.allForExport(),
      collections: await store.collections(),
    );
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded['schema'], 'particle-library.notes.v2');
    expect(decoded['collections'], hasLength(1));

    final otherDir = await Directory.systemTemp.createTemp('pdgapp-import-');
    final other = await NotesStore.open(
      overridePath: '${otherDir.path}/user.db',
    );
    try {
      final source = (await store.collections()).single;
      final result = await other.importJson(decoded);
      expect(result.added, 0);
      final imported = (await other.collections()).single;
      expect(imported.name, 'Empty project');
      expect(imported.id, source.id);
    } finally {
      await other.close();
      await otherDir.delete(recursive: true);
    }
  });
}
