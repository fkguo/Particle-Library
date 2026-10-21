import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/review_annotation_notes.dart';
import 'package:pdgapp/data/review_annotations.dart';
import 'package:pdgapp/notes/notes.dart';

void main() {
  late Directory dir;
  late NotesStore notes;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('review-notes-');
    notes = await NotesStore.open(overridePath: '${dir.path}/user.db');
  });

  tearDown(() async {
    await notes.close();
    await dir.delete(recursive: true);
  });

  test('a PDF highlight is a searchable review-anchored note', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'rpp2026-rev-qcd.pdf',
      pageNumber: 12,
      rects: const [Rect.fromLTRB(0.1, 0.2, 0.5, 0.25)],
      text: 'the selected sentence',
      color: 'green',
      reviewTitle: 'Quantum chromodynamics',
      comment: 'worth revisiting',
      imagePath: '/tmp/region.png',
    );

    expect(annotation.noteId, isNotNull);
    final note = await notes.noteById(annotation.noteId!);
    expect(note, isNotNull);
    expect(note!.title, contains('p.12'));
    expect(note.bodyMarkdown, contains('> the selected sentence'));
    expect(note.bodyMarkdown, contains('worth revisiting'));
    expect(note.bodyPlain, contains('the selected sentence'));

    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'rpp2026-rev-qcd.pdf',
      reviewTitle: 'Quantum chromodynamics',
    );
    expect(loaded, hasLength(1));
    expect(loaded.single.id, annotation.id);
    expect(loaded.single.note, 'worth revisiting');
    expect(loaded.single.color, 'green');
    expect(loaded.single.rects.single.left, closeTo(0.1, 1e-9));
    expect(loaded.single.imagePath, '/tmp/region.png');

    final hits = await notes.search('selected sentence');
    expect(hits.map((hit) => hit.id), contains(note.id));
  });

  test('annotation comments and tags are editable together', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'rpp2026-rev-qcd.pdf',
      pageNumber: 4,
      rects: const [Rect.fromLTRB(0.1, 0.2, 0.4, 0.3)],
      text: 'a selected formula',
      color: 'blue',
      reviewTitle: 'Quantum chromodynamics',
      tags: const ['important'],
    );
    expect(annotation.tags, ['important']);
    await ReviewAnnotationNotes.updateComment(
      notes,
      annotation,
      'check this again',
      tags: const ['important', 'qcd'],
    );
    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'rpp2026-rev-qcd.pdf',
      reviewTitle: 'Quantum chromodynamics',
    );
    expect(loaded.single.note, 'check this again');
    expect(loaded.single.tags, ['important', 'qcd']);
  });

  test(
    'new comment stays searchable after the note body is expanded',
    () async {
      final annotation = await ReviewAnnotationNotes.create(
        notes,
        fileName: 'review.pdf',
        pageNumber: 2,
        rects: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.2)],
        text: 'quoted',
        color: 'yellow',
        reviewTitle: 'Review',
      );
      final note = (await notes.noteById(annotation.noteId!))!;
      await notes.update(
        note.id,
        bodyMarkdown: '${note.bodyMarkdown}\n\nMy own prose.',
      );
      await ReviewAnnotationNotes.updateComment(
        notes,
        annotation,
        'searchable after expansion',
      );
      final loaded = (await ReviewAnnotationNotes.load(
        notes,
        'review.pdf',
        reviewTitle: 'Review',
      )).single;
      expect(loaded.note, 'searchable after expansion');
      final stored = (await notes.noteById(annotation.noteId!))!;
      expect(stored.bodyMarkdown, contains('My own prose.'));
      expect(stored.bodyMarkdown, contains('searchable after expansion'));
      final hits = await notes.search('searchable after expansion');
      expect(hits.map((hit) => hit.id), contains(annotation.noteId));
    },
  );

  test('comment edits update the note body and survive reload', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'review.pdf',
      pageNumber: 2,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.2, 0.2)],
      text: 'quoted',
      color: 'yellow',
      reviewTitle: 'Review',
    );
    await ReviewAnnotationNotes.updateComment(notes, annotation, 'new comment');
    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'review.pdf',
      reviewTitle: 'Review',
    );
    expect(loaded.single.note, 'new comment');
    expect(loaded.single.text, 'quoted');
  });

  test('adjusting a highlight range updates the stored anchor', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'review.pdf',
      pageNumber: 3,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.2)],
      text: 'old quote',
      color: 'blue',
      reviewTitle: 'Review',
      tags: const ['important'],
      imagePath: '/tmp/region.png',
      imageStale: true,
    );
    final updated = await ReviewAnnotationNotes.updateRange(
      notes,
      annotation,
      rects: const [Rect.fromLTRB(0.2, 0.25, 0.8, 0.35)],
      text: 'new longer quote',
    );
    expect(updated, isNotNull);
    expect(updated!.tags, ['important']);
    expect(updated.imagePath, '/tmp/region.png');
    expect(updated.imageStale, isTrue);
    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'review.pdf',
      reviewTitle: 'Review',
    );
    expect(loaded.single.text, 'new longer quote');
    expect(loaded.single.rects.single.right, closeTo(0.8, 1e-9));
    expect(loaded.single.color, 'blue');
    expect(loaded.single.tags, ['important']);
    expect(loaded.single.imagePath, '/tmp/region.png');
    expect(loaded.single.imageStale, isTrue);
  });

  test('comment and range edits keep the human review title in body', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'rpp2026-rev-qcd.pdf',
      pageNumber: 12,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.2)],
      text: 'gluon',
      color: 'green',
      reviewTitle: 'Quantum chromodynamics',
    );
    await ReviewAnnotationNotes.updateComment(
      notes,
      annotation,
      'searchable comment',
    );
    var note = await notes.noteById(annotation.noteId!);
    expect(note!.bodyMarkdown, contains('Quantum chromodynamics'));
    expect(note.bodyMarkdown, contains('searchable comment'));
    await ReviewAnnotationNotes.updateRange(
      notes,
      annotation,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.5, 0.2)],
      text: 'gluon exchange',
    );
    note = await notes.noteById(annotation.noteId!);
    expect(note!.title, contains('Quantum chromodynamics'));
    expect(note.bodyMarkdown, contains('gluon exchange'));
  });

  test('range adjustment preserves a user-renamed highlight title', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'review.pdf',
      pageNumber: 3,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.2)],
      text: 'old quote',
      color: 'yellow',
      reviewTitle: 'Review',
    );
    await notes.update(annotation.noteId!, title: 'My custom title');
    await ReviewAnnotationNotes.updateRange(
      notes,
      annotation,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.5, 0.2)],
      text: 'new quote',
    );
    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'review.pdf',
      reviewTitle: 'Review',
    );
    expect(loaded.single.text, 'new quote');
    final note = await notes.noteById(annotation.noteId!);
    expect(note!.title, 'My custom title');
  });

  test('legacy JSON migrates once and is archived', () async {
    final legacy = ReviewAnnotationStore(File('${dir.path}/annotations.json'));
    await legacy.save([
      ReviewAnnotation(
        id: 'old-1',
        fileName: 'rpp2026-rev-qcd.pdf',
        pageNumber: 4,
        rects: const [Rect.fromLTRB(0.1, 0.1, 0.4, 0.2)],
        text: 'legacy quote',
        note: 'legacy comment',
        color: 'blue',
        createdAt: DateTime(2026, 10, 1),
      ),
    ]);
    await ReviewAnnotationNotes.migrate(notes, legacy);
    expect(await legacy.file.exists(), isFalse);
    final loaded = await ReviewAnnotationNotes.load(
      notes,
      'rpp2026-rev-qcd.pdf',
      reviewTitle: 'QCD',
    );
    expect(loaded, hasLength(1));
    expect(loaded.single.text, 'legacy quote');
    expect(loaded.single.note, 'legacy comment');
    expect(loaded.single.createdAt, DateTime(2026, 10, 1).toUtc());

    final second = await ReviewAnnotationNotes.load(
      notes,
      'rpp2026-rev-qcd.pdf',
      reviewTitle: 'QCD',
    );
    expect(second, hasLength(1));
  });

  test(
    'editing a highlight comment preserves prose added to the note',
    () async {
      final annotation = await ReviewAnnotationNotes.create(
        notes,
        fileName: 'review.pdf',
        pageNumber: 2,
        rects: const [Rect.fromLTRB(0.1, 0.1, 0.2, 0.2)],
        text: 'quoted',
        color: 'yellow',
        reviewTitle: 'Review',
      );
      final note = await notes.noteById(annotation.noteId!);
      await notes.update(
        note!.id,
        bodyMarkdown: '${note.bodyMarkdown}\n\nmy synthesis',
      );
      await ReviewAnnotationNotes.updateComment(
        notes,
        annotation,
        'new comment',
      );
      final reloaded = await ReviewAnnotationNotes.load(
        notes,
        'review.pdf',
        reviewTitle: 'Review',
      );
      expect(reloaded.single.note, 'new comment');
      final saved = await notes.noteById(note.id);
      expect(saved!.bodyMarkdown, contains('my synthesis'));
      expect(saved.bodyMarkdown, contains('new comment'));
      // Append prose after the managed comment block, then edit the comment
      // again: both the tail and the newest comment must survive.
      await notes.update(
        note.id,
        bodyMarkdown: '${saved.bodyMarkdown}\n\nTAIL AFTER COMMENT',
      );
      await ReviewAnnotationNotes.updateComment(
        notes,
        annotation,
        'second comment',
      );
      final savedAgain = (await notes.noteById(note.id))!;
      expect(savedAgain.bodyMarkdown, contains('TAIL AFTER COMMENT'));
      expect(savedAgain.bodyMarkdown, contains('second comment'));
      expect(savedAgain.bodyMarkdown, isNot(contains('new comment')));
    },
  );

  test('deleting the annotation soft-deletes its note', () async {
    final annotation = await ReviewAnnotationNotes.create(
      notes,
      fileName: 'review.pdf',
      pageNumber: 2,
      rects: const [Rect.fromLTRB(0.1, 0.1, 0.2, 0.2)],
      text: 'quoted',
      color: 'yellow',
      reviewTitle: 'Review',
    );
    await ReviewAnnotationNotes.delete(notes, annotation);
    expect(
      await ReviewAnnotationNotes.load(
        notes,
        'review.pdf',
        reviewTitle: 'Review',
      ),
      isEmpty,
    );
  });
}
