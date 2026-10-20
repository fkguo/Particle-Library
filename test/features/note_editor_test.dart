import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/features/notes/note_editor.dart';
import 'package:pdgapp/notes/notes.dart';

void main() {
  late Directory tempDir;
  late NotesStore store;
  late ValueNotifier<int> changes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdgapp-note-editor-');
    store = await NotesStore.open(overridePath: '${tempDir.path}/user.db');
    changes = ValueNotifier<int>(0);
  });

  tearDown(() async {
    await store.close();
    changes.dispose();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // WAL/SHM files can linger briefly; the OS temp dir is disposable.
    }
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    NoteRecord? note,
    List<NoteAnchorInput> anchors = const <NoteAnchorInput>[],
    List<String> initialCollectionIds = const <String>[],
    VoidCallback? onDeleted,
    VoidCallback? onCancel,
    bool draft = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              height: 700,
              child: NoteEditor(
                store: store,
                strings: const AppStrings(TextLang.en),
                note: note,
                initialAnchors: anchors,
                initialCollectionIds: initialCollectionIds,
                changeSignal: changes,
                onDeleted: onDeleted,
                onCancel: onCancel,
                draft: draft,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('autosaves after the debounce with title, body and tags', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.enterText(find.byType(TextField).at(0), 'D0 lifetime');
    await tester.enterText(find.byType(TextField).at(1), '**D0** 寿命与轻子衰变。');
    await tester.enterText(find.byType(TextField).at(2), 'lifetime, D0');

    await tester.pump(const Duration(milliseconds: 200));
    expect(await store.recent(), isEmpty);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final notes = await store.recent();
    expect(notes, hasLength(1));
    final note = notes.single;
    expect(note.title, 'D0 lifetime');
    expect(note.bodyMarkdown, '**D0** 寿命与轻子衰变。');
    expect(note.bodyPlain, contains('D0 寿命与轻子衰变'));
    expect(note.tagNames, <String>['D0', 'lifetime']);
    expect(changes.value, greaterThan(0));
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('an existing draft does not re-add a scope collection on every '
      'autosave', (tester) async {
    final first = await store.createCollection('First');
    final second = await store.createCollection('Second');
    final note = await store.create(
      title: 'Existing',
      bodyMarkdown: 'body',
      collectionIds: [first.id],
    );

    await pumpEditor(
      tester,
      note: note,
      initialCollectionIds: [second.id],
      draft: true,
    );
    await tester.enterText(find.byType(TextField).at(1), 'edited body');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final saved = (await store.noteById(note.id))!;
    expect(saved.collections.map((collection) => collection.id).toSet(), {
      first.id,
    });
    final revision = saved.revision;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((await store.noteById(note.id))!.revision, revision);
  });

  testWidgets('a conflict cannot be overwritten by the next autosave', (
    tester,
  ) async {
    final note = await store.create(title: 'Shared', bodyMarkdown: 'mine');
    await pumpEditor(tester, note: note);
    await store.update(
      note.id,
      bodyMarkdown: 'theirs',
      expectedRevision: note.revision,
    );

    await tester.enterText(find.byType(TextField).at(1), 'my newer edit');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(1), 'my newer edit 2');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final saved = (await store.noteById(note.id))!;
    expect(saved.bodyMarkdown, 'theirs');
  });

  testWidgets('postpones autosave while a CJK IME composition is open', (
    tester,
  ) async {
    await pumpEditor(tester);
    final body = find.byType(TextField).at(1);
    await tester.showKeyboard(body);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '轻',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    expect(await store.recent(), isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '轻子',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    final notes = await store.recent();
    expect(notes, hasLength(1));
    expect(notes.single.bodyMarkdown, '轻子');
    expect(notes.single.bodyPlain, '轻子');
  });

  testWidgets('creates a note with the prefilled anchor', (tester) async {
    await pumpEditor(
      tester,
      anchors: <NoteAnchorInput>[
        NoteAnchorInput.pdgid(
          'S032M',
          snapshotHash: 'hash-1',
          targetLabel: 'D0 (S032M)',
        ),
      ],
    );
    expect(find.text('D0 (S032M)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'about D0');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    final notes = await store.recent();
    expect(notes, hasLength(1));
    final anchors = notes.single.anchors;
    expect(anchors, hasLength(1));
    expect(anchors.single.targetId, 'pdgid:S032M');
    expect(anchors.single.targetLabel, 'D0 (S032M)');
  });

  testWidgets('removing a persisted anchor is saved after the debounce', (
    tester,
  ) async {
    final note = await store.create(
      title: 'D0 note',
      bodyMarkdown: 'body',
      anchors: [NoteAnchorInput.pdgid('S032M', targetLabel: 'D0 (S032M)')],
    );
    await pumpEditor(tester, note: note);
    await tester.tap(
      find.byTooltip(const AppStrings(TextLang.en).notesRemoveAnchor),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    final saved = await store.noteById(note.id);
    expect(saved!.anchors, isEmpty);
  });

  testWidgets('removing an anchor then closing immediately flushes it', (
    tester,
  ) async {
    final note = await store.create(
      title: 'D0 note',
      bodyMarkdown: 'body',
      anchors: [NoteAnchorInput.pdgid('S032M', targetLabel: 'D0 (S032M)')],
    );
    await pumpEditor(tester, note: note);
    await tester.tap(
      find.byTooltip(const AppStrings(TextLang.en).notesRemoveAnchor),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    final saved = await store.noteById(note.id);
    expect(saved!.anchors, isEmpty);
  });

  testWidgets('updates an existing note and deletes it after confirmation', (
    tester,
  ) async {
    final note = await store.create(
      title: 'old title',
      bodyMarkdown: 'old body',
      anchors: <NoteAnchorInput>[NoteAnchorInput.pdgid('S032M')],
      tags: <String>['old'],
    );
    var deleted = false;
    await pumpEditor(tester, note: note, onDeleted: () => deleted = true);

    await tester.enterText(find.byType(TextField).at(0), 'new title');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    final updated = (await store.recent()).single;
    expect(updated.title, 'new title');
    expect(updated.revision, 2);

    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(await store.recent(), isEmpty);
  });
}
