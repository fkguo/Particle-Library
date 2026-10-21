import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/full_backup.dart';
import 'package:pdgapp/notes/notes.dart';
import 'package:pdgapp/user/user_store.dart';

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
    await png.writeAsBytes(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
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
      <int>[0x89, 0x50, 0x4e, 0x47, 1, 2, 3],
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
    'full backup fails instead of silently dropping a referenced PNG',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'particle-backup-missing-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final user = await UserStore.open(overridePath: '${dir.path}/user.json');
      final notes = await NotesStore.open(overridePath: '${dir.path}/notes.db');
      await notes.create(
        title: 'Missing image',
        anchors: [
          NoteAnchorInput.review(
            '2026/review.pdf',
            context: {
              'schema': 1,
              'kind': 'pdf_annotation',
              'pageNumber': 1,
              'imagePath': 'missing.png',
              'rects': [
                [0.1, 0.1, 0.2, 0.2],
              ],
            },
          ),
        ],
      );
      final regions = Directory('${dir.path}/regions');
      await regions.create();
      final archive = '${dir.path}/backup.zip';
      await expectLater(
        FullBackup.export(
          user: user,
          notes: notes,
          destinationPath: archive,
          reviewRegionsDirectory: regions,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(File(archive).existsSync(), isFalse);
      await notes.close();
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
}
