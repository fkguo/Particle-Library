import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/full_backup.dart';
import 'package:pdgapp/notes/notes.dart';
import 'package:pdgapp/user/user_store.dart';

/// A real PNG signature followed by arbitrary bytes: restore checks the
/// signature, not the image.
final _pngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  1,
  2,
  3,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full backup v2 keeps collections, trash and anchor contexts', () async {
    final dir = await Directory.systemTemp.createTemp('particle-backup-v2-');
    addTearDown(() => dir.delete(recursive: true));
    final source = await UserStore.open(
      overridePath: '${dir.path}/source-user.json',
    );
    final sourceNotes = await NotesStore.open(
      overridePath: '${dir.path}/source-notes.db',
    );
    final collection = await sourceNotes.createCollection(
      'Project',
      createdAt: DateTime.utc(2026, 2, 3),
    );
    await sourceNotes.createCollection('Empty collection');
    final active = await sourceNotes.create(
      title: 'Active',
      collectionIds: [collection.id],
      anchors: [
        NoteAnchorInput.pdgid(
          'S032M',
          targetLabel: 'D0 mass',
          context: {
            'ctxVersion': 1,
            'kind': 'pdg_summary',
            'pdgid': 'S032M',
            'propertyId': 'S032M',
            'quantityLabel': 'D0 MASS',
            'valueType': 'FC',
            'summaryRowId': 7,
            'value': '1864.84',
            'unit': 'MeV',
            'edition': '2026',
            'unknownFutureField': 'preserved',
          },
        ),
      ],
    );
    final deleted = await sourceNotes.create(title: 'In trash');
    await sourceNotes.delete(deleted.id);

    final archive = '${dir.path}/backup.zip';
    final exported = await FullBackup.export(
      user: source,
      notes: sourceNotes,
      destinationPath: archive,
    );
    expect(exported.notes, 2);

    final target = await UserStore.open(
      overridePath: '${dir.path}/target-user.json',
    );
    final targetNotes = await NotesStore.open(
      overridePath: '${dir.path}/target-notes.db',
    );
    final imported = await FullBackup.import(
      user: target,
      notes: targetNotes,
      sourcePath: archive,
    );
    expect(imported.notes, 2);
    expect((await targetNotes.recent()).single.title, 'Active');
    expect((await targetNotes.deleted()).single.title, 'In trash');
    expect(
      (await targetNotes.collections()).map((c) => c.name),
      containsAll(['Project', 'Empty collection']),
    );
    final restored = (await targetNotes.noteByUuid(active.uuid))!;
    expect(restored.anchors.single.context!['unknownFutureField'], 'preserved');
    expect(restored.collections.single.name, 'Project');
    await sourceNotes.close();
    await targetNotes.close();
  });

  test('full backup includes region annotation images', () async {
    final dir = await Directory.systemTemp.createTemp(
      'particle-backup-regions-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final source = await UserStore.open(
      overridePath: '${dir.path}/source-user.json',
    );
    final sourceNotes = await NotesStore.open(
      overridePath: '${dir.path}/source-notes.db',
    );
    final sourceRegions = Directory('${dir.path}/source-regions');
    await sourceRegions.create();
    final png = File('${sourceRegions.path}/region-1.png');
    await png.writeAsBytes(_pngBytes);
    final note = await sourceNotes.create(
      title: 'Region note',
      anchors: [
        NoteAnchorInput.review(
          '2026/review.pdf',
          targetLabel: 'p.1',
          context: {
            'schema': 1,
            'kind': 'pdf_annotation',
            'pageNumber': 1,
            'rects': [
              [0.1, 0.1, 0.3, 0.3],
            ],
            'quote': '',
            'imagePath': png.path,
          },
        ),
      ],
    );

    final archive = '${dir.path}/backup.zip';
    final exported = await FullBackup.export(
      user: source,
      notes: sourceNotes,
      destinationPath: archive,
      reviewRegionsDirectory: sourceRegions,
    );
    expect(exported.regions, 1);

    final target = await UserStore.open(
      overridePath: '${dir.path}/target-user.json',
    );
    final targetNotes = await NotesStore.open(
      overridePath: '${dir.path}/target-notes.db',
    );
    final targetRegions = Directory('${dir.path}/target-regions');
    final imported = await FullBackup.import(
      user: target,
      notes: targetNotes,
      sourcePath: archive,
      reviewRegionsDirectory: targetRegions,
    );
    expect(imported.regions, 1);
    expect(
      await File('${targetRegions.path}/region-1.png').readAsBytes(),
      _pngBytes,
    );
    final restored = (await targetNotes.noteByUuid(note.uuid))!;
    expect(
      restored.anchors.single.context!['imagePath'],
      '${targetRegions.path}/region-1.png',
    );
    await sourceNotes.close();
    await targetNotes.close();
  });

  test(
    'a referenced PNG that is not on this device is reported, not fatal',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'particle-backup-missing-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(overridePath: '${dir.path}/user.json');
      final notes = await NotesStore.open(overridePath: '${dir.path}/notes.db');
      addTearDown(notes.close);
      Map<String, Object?> context(String imagePath) => {
        'schema': 1,
        'kind': 'pdf_annotation',
        'pageNumber': 1,
        'imagePath': imagePath,
        'rects': [
          [0.1, 0.1, 0.2, 0.2],
        ],
      };
      // A name copied from another device, a path that is not a PNG, and one
      // that sits in the trash: none may block the backup.
      await notes.create(
        title: 'Foreign path',
        anchors: [
          NoteAnchorInput.review(
            '2026/review.pdf',
            context: context('/Users/other/Library/regions/region-9-1.png'),
          ),
        ],
      );
      await notes.create(
        title: 'Not a png',
        anchors: [
          NoteAnchorInput.review('2026/review.pdf', context: context('x')),
        ],
      );
      final trashed = await notes.create(
        title: 'Trashed',
        anchors: [
          NoteAnchorInput.review(
            '2026/review.pdf',
            context: context('gone.png'),
          ),
        ],
      );
      await notes.delete(trashed.id);
      final regions = Directory('${dir.path}/regions');
      await regions.create();
      final archive = '${dir.path}/backup.zip';

      final exported = await FullBackup.export(
        user: user,
        notes: notes,
        destinationPath: archive,
        reviewRegionsDirectory: regions,
      );
      expect(exported.notes, 3);
      expect(exported.regions, 0);
      expect(exported.missingRegions, 3);
      expect(File(archive).existsSync(), isTrue);

      // The archive must not name files it does not contain, and the
      // annotations say that their screenshot is missing.
      final target = await NotesStore.open(
        overridePath: '${dir.path}/target-notes.db',
      );
      addTearDown(target.close);
      await FullBackup.import(
        user: await UserStore.open(
          overridePath: '${dir.path}/target-user.json',
        ),
        notes: target,
        sourcePath: archive,
        reviewRegionsDirectory: Directory('${dir.path}/target-regions'),
      );
      final restored = await target.allForExport(includeDeleted: true);
      expect(restored, hasLength(3));
      for (final note in restored) {
        final restoredContext = note.anchors.single.context!;
        expect(restoredContext.containsKey('imagePath'), isFalse);
        expect(restoredContext['imageStale'], isTrue);
      }

      // A second backup of the restored data works as well.
      final again = await FullBackup.export(
        user: user,
        notes: target,
        destinationPath: '${dir.path}/again.zip',
        reviewRegionsDirectory: regions,
      );
      expect(again.missingRegions, 0);
    },
  );

  test('full backup round-trips settings, favorites and notes', () async {
    final dir = await Directory.systemTemp.createTemp('particle-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final source = await UserStore.open(
      overridePath: '${dir.path}/source-user.json',
    );
    await source.setSettings(source.settings.copyWith(textScale: 1.2));
    await source.addRecent('X(3872)', 'all');
    final sourceNotes = await NotesStore.open(
      overridePath: '${dir.path}/source-notes.db',
    );
    await sourceNotes.create(
      title: 'Backup note',
      bodyMarkdown: 'A note with **markdown**.',
      tags: const ['backup'],
    );

    final archive = '${dir.path}/backup.zip';
    final exported = await FullBackup.export(
      user: source,
      notes: sourceNotes,
      destinationPath: archive,
    );
    expect(exported.notes, 1);
    expect(File(archive).existsSync(), isTrue);

    final target = await UserStore.open(
      overridePath: '${dir.path}/target-user.json',
    );
    final targetNotes = await NotesStore.open(
      overridePath: '${dir.path}/target-notes.db',
    );
    final imported = await FullBackup.import(
      user: target,
      notes: targetNotes,
      sourcePath: archive,
    );
    expect(imported.full, isTrue);
    expect(imported.notes, 1);
    final restored = await targetNotes.allForExport();
    expect(restored.single.title, 'Backup note');
    expect(target.settings.textScale, 1.2);
    await sourceNotes.close();
    await targetNotes.close();
  });
  group('restoring an untrusted backup', () {
    late Directory dir;
    late UserStore user;
    late NotesStore notes;
    late Directory cache;
    late Directory regions;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('particle-restore-test-');
      user = await UserStore.open(overridePath: '${dir.path}/user.json');
      notes = await NotesStore.open(overridePath: '${dir.path}/notes.db');
      cache = Directory('${dir.path}/cache');
      regions = Directory('${dir.path}/regions');
    });

    tearDown(() async {
      await notes.close();
      await dir.delete(recursive: true);
    });

    final pdfBytes = utf8.encode('%PDF-1.7\nfake body');

    Future<String> writeBackup(
      Map<String, List<int>> members, {
      bool withNote = true,
    }) async {
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            'backup.json',
            utf8.encode(
              jsonEncode({
                'format': FullBackup.format,
                'formatVersion': 2,
                'user': <String, Object?>{},
                'notes': {
                  'schema': 'particle-library.notes.v2',
                  'notes': [
                    if (withNote)
                      {
                        'uuid': 'restore-note',
                        'title': 'Restore note',
                        'bodyMarkdown': 'body',
                        'anchors': <Object?>[],
                        'tags': <Object?>[],
                        'collections': <Object?>[],
                      },
                  ],
                },
              }),
            ),
          ),
        );
      for (final entry in members.entries) {
        archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
      }
      final path = '${dir.path}/restore.zip';
      await File(path).writeAsBytes(ZipEncoder().encode(archive));
      return path;
    }

    Future<FullBackupImport> restore(String path) => FullBackup.import(
      user: user,
      notes: notes,
      sourcePath: path,
      reviewRegionsDirectory: regions,
      reviewCacheDirectory: cache,
    );

    Future<List<String>> filesIn(Directory directory) async =>
        directory.existsSync()
        ? [
            for (final entity in directory.listSync(recursive: true))
              if (entity is File) entity.path.split('/').last,
          ]
        : <String>[];

    test('genuine PDF and PNG members are restored', () async {
      final result = await restore(
        await writeBackup({
          'reviews/rpp2026-rev-a.pdf': pdfBytes,
          'regions/region-1-1.png': _pngBytes,
        }),
      );
      expect(result.pdfs, 1);
      expect(result.regions, 1);
      expect(
        await File('${cache.path}/rpp2026-rev-a.pdf').readAsBytes(),
        pdfBytes,
      );
    });

    test('a member that is not a PDF rejects the whole backup', () async {
      final path = await writeBackup({
        'reviews/rpp2026-rev-a.pdf': pdfBytes,
        'reviews/rpp2026-rev-b.pdf': utf8.encode('<html>not a pdf</html>'),
      });
      await expectLater(restore(path), throwsA(isA<FormatException>()));
      // Nothing was written: not the notes, not the genuine PDF.
      expect(await notes.allForExport(includeDeleted: true), isEmpty);
      expect(await filesIn(cache), isEmpty);
    });

    test('a member that is not a PNG rejects the whole backup', () async {
      final path = await writeBackup({
        'regions/region-1-1.png': utf8.encode('%PDF-1.7 pretending'),
      });
      await expectLater(restore(path), throwsA(isA<FormatException>()));
      expect(await notes.allForExport(includeDeleted: true), isEmpty);
      expect(await filesIn(regions), isEmpty);
    });

    test('a cached review or screenshot is never replaced', () async {
      await cache.create(recursive: true);
      await regions.create(recursive: true);
      final localPdf = utf8.encode('%PDF-1.7\nlocal copy');
      final localPng = [..._pngBytes, 9, 9];
      await File('${cache.path}/rpp2026-rev-a.pdf').writeAsBytes(localPdf);
      await File('${regions.path}/region-1-1.png').writeAsBytes(localPng);

      final result = await restore(
        await writeBackup({
          'reviews/rpp2026-rev-a.pdf': pdfBytes,
          'regions/region-1-1.png': _pngBytes,
        }),
      );
      expect(result.pdfs, 0);
      expect(result.regions, 0);
      expect(
        await File('${cache.path}/rpp2026-rev-a.pdf').readAsBytes(),
        localPdf,
      );
      expect(
        await File('${regions.path}/region-1-1.png').readAsBytes(),
        localPng,
      );
    });

    test('members are only written under their own name in the cache', () async {
      // The zip writer folds backslashes into path separators, so these arrive
      // as ".../escape.pdf" and ".../dir.pdf": only the last path segment is
      // ever used, and hidden names are refused.
      await restore(
        await writeBackup({
          'reviews/../escape.pdf': pdfBytes,
          'reviews/..\\escape2.pdf': pdfBytes,
          'reviews/.hidden.pdf': pdfBytes,
          'reviews/sub\\dir.pdf': pdfBytes,
          'reviews/rpp2026-rev-ok.pdf': pdfBytes,
        }),
      );
      final names = (await filesIn(cache))..sort();
      expect(names, [
        'dir.pdf',
        'escape.pdf',
        'escape2.pdf',
        'rpp2026-rev-ok.pdf',
      ]);
      expect(File('${dir.path}/escape.pdf').existsSync(), isFalse);
      expect(File('${dir.path}/escape2.pdf').existsSync(), isFalse);
      expect(Directory('${cache.path}/sub').existsSync(), isFalse);
    });

    test('a plain JSON backup is still accepted', () async {
      final path = '${dir.path}/backup.json';
      await File(path).writeAsString(
        jsonEncode({
          'format': FullBackup.format,
          'formatVersion': 2,
          'notes': {
            'schema': 'particle-library.notes.v2',
            'notes': <Object?>[],
          },
        }),
      );
      final result = await restore(path);
      expect(result.full, isTrue);
    });
  });
}
