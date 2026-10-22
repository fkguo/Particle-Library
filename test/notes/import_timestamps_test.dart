import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/notes/notes.dart';

void main() {
  late Directory tempDir;
  late NotesStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdgapp-import-dates-');
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

  Map<String, Object?> note(
    String uuid, {
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) => {
    'uuid': uuid,
    'title': 'Note $uuid',
    'bodyMarkdown': 'body',
    'anchors': <Object?>[],
    'tags': <Object?>[],
    'collections': <Object?>[],
    'createdAt': ?createdAt,
    'updatedAt': ?updatedAt,
    'deletedAt': ?deletedAt,
  };

  test('timestamps outside years 0000-9999 do not corrupt the store', () async {
    final result = await store.importJson({
      'schema': 'particle-library.notes.v2',
      'notes': [
        note(
          'negative-year',
          createdAt: '-0005-01-01T00:00:00Z',
          updatedAt: '-0001-06-01T00:00:00Z',
        ),
        note(
          'five-digit-year',
          createdAt: '+12345-01-01T00:00:00Z',
          updatedAt: '+12345-01-02T00:00:00Z',
        ),
        note(
          'trashed',
          createdAt: '2020-01-01T00:00:00Z',
          deletedAt: '-0003-01-01T00:00:00Z',
        ),
        note('ordinary', createdAt: '2024-05-06T07:08:09Z'),
      ],
    });
    expect(result.added, 4);

    // Every read path must still work after the import.
    final recent = await store.recent();
    expect(recent.map((item) => item.title), isNot(contains('Note trashed')));
    expect(recent, hasLength(3));
    final everything = await store.allForExport(includeDeleted: true);
    expect(everything, hasLength(4));
    expect((await store.deleted()).single.title, 'Note trashed');
    expect(await store.search('Note'), hasLength(3));

    DateTime created(String title) =>
        everything.firstWhere((item) => item.title == title).createdAt;
    expect(created('Note negative-year').year, 0);
    expect(created('Note five-digit-year').year, 9999);
    expect(created('Note ordinary'), DateTime.utc(2024, 5, 6, 7, 8, 9));
  });

  test(
    'a trashed note with an unusable deletion date stays in the trash',
    () async {
      await store.importJson({
        'schema': 'particle-library.notes.v2',
        'notes': [note('trashed', deletedAt: '-0003-01-01T00:00:00Z')],
      });
      expect(await store.recent(), isEmpty);
      expect(await store.deleted(), hasLength(1));
    },
  );
}
