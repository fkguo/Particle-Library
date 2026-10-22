import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/features/notes/note_editor.dart';
import 'package:pdgapp/features/notes/notes_markdown_preview.dart';
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
    Size size = const Size(900, 700),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
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
    expect(find.textContaining('D0 (S032M)'), findsOneWidget);

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

  testWidgets('removing an anchor can be undone before or after autosave', (
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
    await tester.pumpAndSettle();
    expect(find.text('Link removed'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    final saved = await store.noteById(note.id);
    expect(saved!.anchors, hasLength(1));
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
  testWidgets('phone header does not jump when the save status changes', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Jump check',
      bodyMarkdown: 'initial body',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              height: 700,
              child: NoteEditor(
                store: store,
                strings: const AppStrings(TextLang.en),
                note: note,
                changeSignal: changes,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final previewButton = find.byIcon(Icons.visibility_outlined);
    final before = tester.getTopLeft(previewButton);

    await tester.enterText(find.byType(TextField).at(1), 'edited body text');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(tester.getTopLeft(previewButton), before);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsWidgets);
    // The status label and spinner change width, but the action row must not
    // move: the status has its own line in the compact header.
    expect(tester.getTopLeft(previewButton), before);
  });

  testWidgets('a landscape phone gives the body editor most of the height', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Landscape note',
      bodyMarkdown: 'first line\nsecond line\nthird line',
    );
    await pumpEditor(tester, note: note, size: const Size(952, 438));

    final body = find.byType(TextField).at(1);
    expect(tester.getSize(body).height, greaterThan(150));
    // Secondary metadata is hidden when height is scarce; the body wins.
    expect(find.text('Collections'), findsNothing);
    expect(find.text('Anchors'), findsNothing);
    expect(find.byType(NotesMarkdownPreview), findsNothing);
    // Title and toolbar share one row, so the body gains the second row.
    final titleCenter = tester.getCenter(find.byType(TextField).first);
    final previewCenter = tester.getCenter(
      find.byIcon(Icons.visibility_outlined),
    );
    expect((titleCenter.dy - previewCenter.dy).abs(), lessThan(6));
  });

  testWidgets('a keyboard-height landscape still leaves a usable editor', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Tight',
      bodyMarkdown: 'first line\nsecond line',
    );
    // 952x260 is what is left on a landscape phone with the keyboard open.
    await pumpEditor(tester, note: note, size: const Size(952, 260));

    final body = find.byType(TextField).at(1);
    expect(tester.getSize(body).height, greaterThan(80));
    // The toolbar and the tag field yield to the text field.
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
  });

  testWidgets('shrinking for the keyboard keeps the same field elements', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Focus check',
      bodyMarkdown: 'body text',
    );
    await pumpEditor(tester, note: note, size: const Size(952, 438));
    final titleElement = tester.element(find.byType(TextField).first);
    final bodyElement = tester.element(find.byType(TextField).at(1));

    // The keyboard opens and the page shrinks. Nothing may be recreated:
    // recreating the text fields drops focus and closes the keyboard.
    await pumpEditor(tester, note: note, size: const Size(952, 260));
    expect(tester.element(find.byType(TextField).first), same(titleElement));
    expect(tester.element(find.byType(TextField).at(1)), same(bodyElement));
  });

  testWidgets('a save after an unseen external append merges it', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Target',
      bodyMarkdown: 'first paragraph',
    );
    await pumpEditor(tester, note: note);
    await tester.pump();

    // Append externally without notifying the editor (worst case).
    await store.update(
      note.id,
      bodyMarkdown: 'first paragraph\n\n[Source](review:2026/x.pdf)',
    );

    await tester.enterText(
      find.byType(TextField).at(1),
      'first paragraph local edit',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();

    final saved = await store.noteById(note.id);
    expect(saved!.bodyMarkdown, contains('local edit'));
    expect(saved.bodyMarkdown, contains('[Source]'));
  });

  testWidgets('a re-created editor loads an append made while closed', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Target',
      bodyMarkdown: 'first paragraph',
    );
    await pumpEditor(tester, note: note);
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump();

    await store.update(
      note.id,
      bodyMarkdown: 'first paragraph\n\n[Source](review:2026/x.pdf)',
    );

    await pumpEditor(tester, note: note);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any(
        (field) => (field.controller?.text ?? '').contains('[Source]'),
      ),
      isTrue,
    );
  });

  testWidgets('an external append is merged into the open note', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Target',
      bodyMarkdown: 'first paragraph',
    );
    await pumpEditor(tester, note: note);
    await tester.pump();

    await store.update(
      note.id,
      bodyMarkdown: 'first paragraph\n\n[Source](review:2026/x.pdf)',
      anchors: <NoteAnchorInput>[
        NoteAnchorInput.review('2026/x.pdf', targetLabel: 'Source page'),
      ],
    );
    changes.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any(
        (field) => (field.controller?.text ?? '').contains('[Source]'),
      ),
      isTrue,
    );
    expect(find.textContaining('Source page'), findsWidgets);
  });

  testWidgets('a portrait keyboard resize keeps the body field focused', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Portrait note',
      bodyMarkdown: 'body text',
      anchors: <NoteAnchorInput>[
        NoteAnchorInput.pdgid(
          'S032M',
          snapshotHash: 'hash-1',
          targetLabel: 'D0 (S032M)',
        ),
      ],
    );
    await pumpEditor(tester, note: note, size: const Size(430, 932));
    final bodyFinder = find.byType(TextField).at(1);
    final bodyElement = tester.element(bodyFinder);
    final focusNode = tester.widget<TextField>(bodyFinder).focusNode!;
    await tester.tap(bodyFinder);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    // The keyboard takes the available height below the 480 dp threshold; the
    // anchors block has to disappear without moving the body field.
    await pumpEditor(tester, note: note, size: const Size(430, 460));
    expect(tester.element(find.byType(TextField).at(1)), same(bodyElement));
    expect(focusNode.hasFocus, isTrue);
    expect(find.text('Anchors'), findsNothing);
  });
}
