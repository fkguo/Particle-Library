import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/review_annotations.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('one malformed record does not discard the rest', () async {
    final dir = await Directory.systemTemp.createTemp('review-annotations-');
    final file = File('${dir.path}/annotations.json');
    await file.writeAsString(
      '[{"id":"ok","fileName":"review.pdf","pageNumber":2,'
      '"rects":[[0.1,0.2,0.3,0.25]],"text":"ok","note":"",'
      '"color":"yellow","createdAt":"2026-10-18T12:00:00Z"},'
      '{"id":"bad","pageNumber":"three"}]',
    );
    final store = ReviewAnnotationStore(file);
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'ok');
    await dir.delete(recursive: true);
  });

  test('a corrupt store is quarantined instead of silently emptied', () async {
    final dir = await Directory.systemTemp.createTemp('review-annotations-');
    final file = File('${dir.path}/annotations.json');
    await file.writeAsString('{not json');
    final store = ReviewAnnotationStore(file);
    expect(await store.load(), isEmpty);
    expect(await file.exists(), isFalse);
    final quarantined = dir
        .listSync()
        .whereType<File>()
        .where((item) => item.path.contains('.corrupt-'))
        .toList();
    expect(quarantined, hasLength(1));
    await dir.delete(recursive: true);
  });

  test('PDF y-up selection rects become Flutter top-left rects', () {
    final page = _FakePdfPage(600, 800, PdfPageRotation.none);
    final rect = normalizePdfSelectionRect(PdfRect(10, 700, 100, 650), page);
    expect(rect.left, closeTo(10 / 600, 1e-9));
    expect(rect.top, closeTo(100 / 800, 1e-9));
    expect(rect.right, closeTo(100 / 600, 1e-9));
    expect(rect.bottom, closeTo(150 / 800, 1e-9));
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  test('word fragments merge into line spans for display', () {
    final merged = mergeRectsForDisplay(const [
      Rect.fromLTRB(0.1, 0.1, 0.2, 0.15),
      Rect.fromLTRB(0.205, 0.1, 0.3, 0.15),
      Rect.fromLTRB(0.1, 0.2, 0.2, 0.25),
    ]);
    expect(merged, hasLength(2));
    expect(merged.first.left, 0.1);
    expect(merged.first.right, 0.3);
    expect(merged.first.top, 0.1);
    expect(merged.last.top, 0.2);
  });

  test('review annotations round-trip normalized rectangles', () async {
    final dir = await Directory.systemTemp.createTemp('review-annotations-');
    final store = ReviewAnnotationStore(File('${dir.path}/annotations.json'));
    final annotation = ReviewAnnotation(
      id: 'a1',
      fileName: 'review.pdf',
      pageNumber: 3,
      rects: const [Rect.fromLTRB(0.1, 0.2, 0.4, 0.25)],
      text: 'selected sentence',
      note: 'remember this',
      color: 'yellow',
      createdAt: DateTime(2026, 10, 18, 12),
      imagePath: '/tmp/region.png',
      imageStale: true,
    );
    await store.save([annotation]);
    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.pageNumber, 3);
    expect(loaded.single.rects.single.left, closeTo(0.1, 1e-9));
    expect(loaded.single.note, 'remember this');
    expect(loaded.single.imagePath, '/tmp/region.png');
    expect(loaded.single.imageStale, isTrue);
    await dir.delete(recursive: true);
  });
}

class _FakePdfPage implements PdfPage {
  _FakePdfPage(this.width, this.height, this.rotation);

  @override
  final double width;

  @override
  final double height;

  @override
  final PdfPageRotation rotation;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
