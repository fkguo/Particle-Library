import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdgapp/app/app_scope.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/app/bootstrap.dart';
import 'package:pdgapp/data/review_annotation_notes.dart';
import 'package:pdgapp/features/reviews/review_viewer_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real page right-click has one annotation menu', (tester) async {
    final temp = await getTemporaryDirectory();
    await temp.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final pdf = File('${temp.path}/hybrid-page-$stamp.pdf');
    await pdf.writeAsBytes(_pdf());
    final services = await AppBootstrap.load(
      notesStoreOverridePath: '${temp.path}/hybrid-page-$stamp.sqlite',
    ).timeout(const Duration(seconds: 60));
    final notes = services.notes;
    expect(notes, isNotNull);
    final region = await ReviewAnnotationNotes.create(
      notes!,
      fileName: pdf.uri.pathSegments.last,
      pageNumber: 1,
      rects: const [Rect.fromLTWH(0.08, 0.08, 0.30, 0.20)],
      text: '',
      color: 'yellow',
      reviewTitle: 'Hybrid Page',
    );
    final textHighlight = await ReviewAnnotationNotes.create(
      notes,
      fileName: pdf.uri.pathSegments.last,
      pageNumber: 1,
      rects: const [Rect.fromLTWH(0.55, 0.10, 0.30, 0.06)],
      text: 'Hybrid page line 10',
      color: 'blue',
      reviewTitle: 'Hybrid Page',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(
          services: services,
          child: ReviewViewerPage(
            title: 'Hybrid Page',
            path: pdf.path,
            officialUrl: '',
          ),
        ),
      ),
    );
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      if (find.byType(PdfViewer).evaluate().isNotEmpty) break;
    }
    expect(find.byType(PdfViewer), findsOneWidget);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer.controller!;
    for (var i = 0; i < 200 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(controller.isReady, isTrue);
    for (var i = 0; i < 100; i++) {
      try {
        if (controller.layout.pageLayouts.isNotEmpty) break;
      } catch (_) {}
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final page = controller.layout.pageLayouts.first;
    await tester.pump(const Duration(milliseconds: 400));

    // A medium window opens the inspector as an end drawer with the same
    // Contents / Annotations / Notes tabs.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Annotation sidebar').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Annotations'), findsWidgets);
    expect(find.text('Contents'), findsWidgets);
    await tester.tap(find.text('Notes').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Hybrid page line 10'), findsWidgets);
    await tester.tap(find.text('Annotations').first);
    await tester.pump(const Duration(milliseconds: 300));
    // The drawer closes from the chevron in its own header.
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Annotations'), findsNothing);

    // Annotate mode adds one contextual strip and shrinks the page viewport;
    // leaving it restores full-height reading.
    final readingViewport = tester.getRect(find.byType(PdfViewer));
    await tester.tap(find.byIcon(Icons.draw_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Done'), findsOneWidget);
    final annotateViewport = tester.getRect(find.byType(PdfViewer));
    expect(annotateViewport.height, lessThan(readingViewport.height));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Done'), findsNothing);
    expect(
      tester.getRect(find.byType(PdfViewer)).height,
      closeTo(readingViewport.height, 1),
    );
    final hitKey = Key('region-hit-${region.id}');
    final hitCenter = tester.getCenter(find.byKey(hitKey));
    final beforeUnselectedDrag = await ReviewAnnotationNotes.load(
      notes,
      pdf.uri.pathSegments.last,
      reviewTitle: 'Hybrid Page',
    );
    await tester.dragFrom(hitCenter, const Offset(35, 25));
    await tester.pump(const Duration(milliseconds: 400));
    final selectedKey = Key('selected-region-${region.id}');
    expect(
      find.byKey(selectedKey),
      findsNothing,
      reason: 'unselected region drag must not select it',
    );
    final afterUnselectedDrag = await ReviewAnnotationNotes.load(
      notes,
      pdf.uri.pathSegments.last,
      reviewTitle: 'Hybrid Page',
    );
    expect(afterUnselectedDrag, hasLength(2));
    final regionBefore = beforeUnselectedDrag.firstWhere(
      (annotation) => annotation.id == region.id,
    );
    final regionAfter = afterUnselectedDrag.firstWhere(
      (annotation) => annotation.id == region.id,
    );
    expect(regionAfter.rects.single, regionBefore.rects.single);

    final docCenter = Offset(
      page.left + 0.23 * page.width,
      page.top + 0.18 * page.height,
    );
    final global = controller.documentToGlobal(docCenter);
    expect(global, isNotNull);
    await tester.tapAt(global!, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select All'), findsNothing);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PopupMenuItem<String>), findsNothing);

    await tester.tapAt(global);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(selectedKey), findsOneWidget);

    final viewerRect = tester.getRect(find.byType(PdfViewer));
    final background = viewerRect.bottomRight - const Offset(20, 20);
    await tester.tapAt(background);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(selectedKey), findsNothing);

    await tester.tapAt(global);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(selectedKey), findsOneWidget);
    final beforeTouch = tester.getRect(find.byKey(selectedKey));
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(selectedKey)),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(30, 24));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 400));
    final afterTouch = tester.getRect(find.byKey(selectedKey));
    expect(afterTouch.topLeft, beforeTouch.topLeft);

    final beforeMove = tester.getRect(find.byKey(selectedKey));
    await tester.drag(
      find.byKey(selectedKey),
      const Offset(-28, -22),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final afterMove = tester.getRect(find.byKey(selectedKey));
    expect(afterMove.topLeft, isNot(beforeMove.topLeft));

    final beforeResize = tester.getRect(find.byKey(selectedKey));
    await tester.dragFrom(
      beforeResize.bottomRight - const Offset(3, 3),
      const Offset(-22, -18),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final afterResize = tester.getRect(find.byKey(selectedKey));
    expect(afterResize.width, lessThan(beforeResize.width));

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    final textHitKey = Key('text-hit-${textHighlight.id}-0');
    expect(find.byKey(textHitKey), findsOneWidget);
    final textHitCenter = tester.getCenter(find.byKey(textHitKey));
    await tester.tapAt(textHitCenter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('pdfrxAnchorBPositioned')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(textHitCenter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(textHitCenter, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select All'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(
      () => controller.textSelectionDelegate.selectAllText(),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final textPoint = controller.documentToGlobal(
      Offset(page.left + page.width * 0.5, page.top + page.height * 0.10),
    );
    expect(textPoint, isNotNull);
    await tester.tapAt(textPoint!, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select All'), findsNothing);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(textHitCenter);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(textHitCenter);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Uint8List _pdf() {
  final stream = StringBuffer('BT /F1 14 Tf 30 TL 60 540 Td ');
  for (var line = 0; line < 15; line++) {
    stream.write('(Hybrid page line ${line + 1}) Tj T* ');
  }
  stream.write('ET');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}
