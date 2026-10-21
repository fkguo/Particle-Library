import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/features/notes/notes_page.dart';
import 'package:pdgapp/notes/notes.dart';

void main() {
  late Directory tempDir;
  late NotesStore store;
  late ValueNotifier<int> changes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdgapp-notes-page-');
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

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    bool notesAvailable = true,
    Object? storeError,
    double wideBreakpoint = 700,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: NotesWorkspace(
            store: notesAvailable ? store : null,
            storeError: storeError,
            strings: const AppStrings(TextLang.en),
            changes: changes,
            wideBreakpoint: wideBreakpoint,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow phone layout does not overflow the Notes header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpWorkspace(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('New note'), findsWidgets);
  });

  testWidgets('landscape phone layout keeps the note list visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.create(title: 'Landscape note', bodyMarkdown: 'body');
    await pumpWorkspace(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Landscape note'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
  });

  testWidgets('rotating Evidence from landscape to portrait stays valid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.create(title: 'Evidence note', bodyMarkdown: 'body');
    await pumpWorkspace(tester);
    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Evidence'), findsWidgets);
  });

  testWidgets('rotating a phone keeps the note list scroll position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var i = 0; i < 30; i++) {
      await store.create(title: 'Scroll note $i', bodyMarkdown: 'body $i');
    }
    await pumpWorkspace(tester);

    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, -320));
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0));

    // Rotation must not recreate the list: the same scrollable keeps its
    // offset while the chrome switches to its dense form.
    tester.view.physicalSize = const Size(932, 430);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    expect(after, closeTo(before, 0.5));

    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels,
      closeTo(before, 0.5),
    );
  });

  testWidgets('lists recent notes, searches CJK text and opens the editor', (
    tester,
  ) async {
    await store.create(
      title: 'D0 寿命',
      bodyMarkdown: '**D0** 的轻子衰变讨论。',
      anchors: <NoteAnchorInput>[
        NoteAnchorInput.pdgid(
          'S032M',
          snapshotHash: 'hash-1',
          targetLabel: 'D0 (S032M)',
        ),
      ],
      tags: <String>['寿命'],
    );
    await store.create(
      title: 'B0 mixing',
      bodyMarkdown: 'mixing parameters and constraints',
    );

    await pumpWorkspace(tester);

    expect(find.text('Recent notes'), findsOneWidget);
    expect(find.text('D0 寿命'), findsOneWidget);
    expect(find.text('B0 mixing'), findsOneWidget);
    expect(find.text('D0 (S032M)'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, '轻子');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('D0 寿命'), findsOneWidget);
    expect(find.text('B0 mixing'), findsNothing);

    await tester.tap(find.text('D0 寿命'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    final titleField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(titleField.controller?.text, 'D0 寿命');
  });

  testWidgets('creates a draft through the shared inline editor', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    expect(find.text('New note'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'New note').first);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(1), 'Fresh note');
    await tester.enterText(find.byType(TextField).at(2), 'autosaved body');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final notes = await store.recent();
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Fresh note');
    expect(notes.single.bodyMarkdown, 'autosaved body');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('shows one new-note affordance on an empty workspace', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    expect(find.widgetWithText(FilledButton, 'New note'), findsOneWidget);
  });

  testWidgets('right-clicking a collection can add existing notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collection = await store.createCollection('Project');
    final note = await store.create(title: 'Existing note');
    await pumpWorkspace(tester);

    await tester.tap(find.text('Project'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Add existing notes…'), findsOneWidget);
    await tester.tap(find.text('Add existing notes…'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(CheckboxListTile)),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(FilledButton, 'Add'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      (await store.noteById(note.id))!.collections.map((c) => c.id),
      contains(collection.id),
    );
  });

  testWidgets('deleting a collection can be undone with its notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collection = await store.createCollection('Project');
    final note = await store.create(
      title: 'Member note',
      collectionIds: [collection.id],
    );
    final trashed = await store.create(
      title: 'Trashed member',
      collectionIds: [collection.id],
    );
    await store.delete(trashed.id);
    await pumpWorkspace(tester);

    await tester.tap(find.text('Project'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await store.collections(), isEmpty);
    expect(find.text('Collection deleted'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect((await store.collections()).map((c) => c.name), contains('Project'));
    expect(
      (await store.noteById(note.id))!.collections.map((c) => c.id),
      contains(collection.id),
    );
  });

  testWidgets('review links opens the note with a broken anchor', (
    tester,
  ) async {
    await store.create(
      title: 'Broken link note',
      anchors: [
        NoteAnchorInput.pdgid(
          'BROKEN',
          targetLabel: 'Broken link',
          status: NoteAnchorStatus.fuzzy,
          context: {
            'ctxVersion': 1,
            'kind': 'pdg_summary',
            'pdgid': 'BROKEN',
            'quantityLabel': 'Broken quantity',
            'summaryRowId': 1,
            'value': '1.0',
            'edition': '2026',
          },
        ),
      ],
    );
    await pumpWorkspace(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Evidence'));
    await tester.pumpAndSettle();
    expect(find.text('Review links (1)'), findsOneWidget);
    await tester.tap(find.text('Review links (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Review unresolved links'), findsOneWidget);
    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();
    expect(find.text('Broken link note'), findsWidgets);
  });

  testWidgets('re-anchoring keeps the old anchor and adds the new one', (
    tester,
  ) async {
    final note = await store.create(
      title: 'Broken link note',
      anchors: [
        NoteAnchorInput.pdgid(
          'BROKEN',
          targetLabel: 'Broken link',
          status: NoteAnchorStatus.fuzzy,
          context: {
            'ctxVersion': 1,
            'kind': 'pdg_summary',
            'pdgid': 'BROKEN',
            'quantityLabel': 'Broken quantity',
            'summaryRowId': 1,
            'value': '1.0',
            'edition': '2026',
          },
        ),
      ],
    );
    await pumpWorkspace(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Evidence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review links (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-anchor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'S032M');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = (await store.noteById(note.id))!;
    expect(saved.anchors, hasLength(2));
    expect(saved.anchors.last.targetKey, 'S032M');
    expect(saved.anchors.first.targetKey, 'BROKEN');
  });

  testWidgets('multi-select adds several notes to a collection', (
    tester,
  ) async {
    final collection = await store.createCollection('Project');
    final first = await store.create(title: 'One');
    final second = await store.create(title: 'Two');
    await pumpWorkspace(tester);

    await tester.tap(find.byTooltip('Select notes'));
    await tester.pump();
    await tester.tap(find.text('One'));
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Add to collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();

    expect(
      (await store.noteById(first.id))!.collections.map((c) => c.id),
      contains(collection.id),
    );
    expect(
      (await store.noteById(second.id))!.collections.map((c) => c.id),
      contains(collection.id),
    );
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('dragging a checked note moves the whole selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collection = await store.createCollection('Project');
    final first = await store.create(title: 'One');
    final second = await store.create(title: 'Two');
    await pumpWorkspace(tester);

    await tester.tap(find.byTooltip('Select notes'));
    await tester.pump();
    await tester.tap(find.text('One'));
    await tester.tap(find.text('Two'));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(tester.getCenter(find.text('Project')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    for (final id in [first.id, second.id]) {
      expect(
        (await store.noteById(id))!.collections.map((c) => c.id),
        contains(collection.id),
      );
    }
  });

  testWidgets('editor does not remove a collection added elsewhere', (
    tester,
  ) async {
    final first = await store.createCollection('One');
    final second = await store.createCollection('Two');
    final note = await store.create(
      title: 'Shared note',
      bodyMarkdown: 'body',
      collectionIds: [first.id],
    );
    await pumpWorkspace(tester);
    await tester.tap(find.text('Shared note'));
    await tester.pumpAndSettle();
    await store.addNoteToCollection(note.id, second.id);

    await tester.enterText(find.byType(TextField).at(2), 'edited body');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final saved = (await store.noteById(note.id))!;
    expect(saved.collections.map((collection) => collection.id).toSet(), {
      first.id,
      second.id,
    });
  });

  testWidgets(
    'existing note reloads the saved revision after Evidence remount',
    (tester) async {
      final note = await store.create(title: 'Existing', bodyMarkdown: 'v1');
      await pumpWorkspace(tester);
      await tester.tap(find.text('Existing').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'v2');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Evidence'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Notes'));
      await tester.pumpAndSettle();

      final body = tester.widget<TextField>(find.byType(TextField).at(2));
      expect(body.controller!.text, 'v2');
      await tester.enterText(find.byType(TextField).at(2), 'v3');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final saved = (await store.noteById(note.id))!;
      expect(saved.bodyMarkdown, 'v3');
    },
  );

  testWidgets('draft survives switching to Evidence and back', (tester) async {
    await pumpWorkspace(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'New note').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Draft survives');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(await store.recent(), hasLength(1));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Evidence'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Draft survives'), findsWidgets);
    await tester.enterText(find.byType(TextField).at(2), ' more text');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(await store.recent(), hasLength(1));
  });

  testWidgets('discards a draft and removes its autosaved note', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'New note').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Temporary draft');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(await store.recent(), hasLength(1));

    await tester.tap(find.byTooltip('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.text('Discard draft'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(await store.recent(), isEmpty);
    expect(find.text('New note'), findsWidgets);
  });

  testWidgets('shows an unavailable panel when the notes store failed', (
    tester,
  ) async {
    await pumpWorkspace(
      tester,
      notesAvailable: false,
      storeError: 'disk unavailable',
    );

    expect(
      find.text(
        'The notes database is unavailable; particle data still works.',
      ),
      findsOneWidget,
    );
    expect(find.text('disk unavailable'), findsOneWidget);
    expect(find.text('New note'), findsNothing);
  });

  testWidgets('New note stays compact at the largest text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpWorkspace(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(FilledButton, 'New note');
    expect(button, findsOneWidget);
    // The 34 dp floor plus 1.3x clamped label: well under a 48 dp bar.
    expect(tester.getSize(button).height, lessThan(48));

    await pumpWorkspace(tester);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'New note')).height,
      lessThan(40),
    );
  });
}
