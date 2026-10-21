import '../core/app_paths.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

/// One highlight/note attached to a cached review PDF.
///
/// Rects are stored normalized to the PDF page (0..1), so they survive zoom,
/// window changes and different display scales.
class ReviewAnnotation {
  const ReviewAnnotation({
    required this.id,
    required this.fileName,
    required this.pageNumber,
    required this.rects,
    required this.text,
    required this.note,
    required this.color,
    required this.createdAt,
    this.noteId,
    this.imagePath,
    this.imageStale = false,
    this.tags = const <String>[],
  });

  final String id;
  final String fileName;
  final int pageNumber;
  final List<Rect> rects;
  final String text;
  final String note;
  final String color;
  final DateTime createdAt;

  /// Owning note id, when this annotation is stored in the notes database.
  final String? noteId;

  /// Rendered PNG for a region annotation, when available.
  final String? imagePath;

  /// True when the region geometry changed but the PNG could not be refreshed.
  final bool imageStale;

  /// Tags mirrored from the owning note.
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'pageNumber': pageNumber,
    'rects': [
      for (final rect in rects) [rect.left, rect.top, rect.right, rect.bottom],
    ],
    'text': text,
    'note': note,
    'color': color,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (imagePath != null) 'imagePath': imagePath,
    if (imageStale) 'imageStale': true,
    'tags': tags,
  };

  static ReviewAnnotation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = Map<String, Object?>.from(raw);
    final id = data['id']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final rawPage = data['pageNumber'];
    final pageNumber = rawPage is num ? rawPage.toInt() : 0;
    final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    final rawRects = data['rects'];
    if (id.isEmpty ||
        fileName.isEmpty ||
        pageNumber <= 0 ||
        createdAt == null ||
        rawRects is! List) {
      return null;
    }
    final rects = <Rect>[];
    for (final item in rawRects) {
      if (item is! List || item.length != 4) continue;
      final values = <double?>[
        for (final value in item) value is num ? value.toDouble() : null,
      ];
      if (values.any((value) => value == null)) continue;
      final rect = Rect.fromLTRB(
        values[0]!,
        values[1]!,
        values[2]!,
        values[3]!,
      );
      if (rect.width > 0 && rect.height > 0) rects.add(rect);
    }
    if (rects.isEmpty) return null;
    return ReviewAnnotation(
      id: id,
      fileName: fileName,
      pageNumber: pageNumber,
      rects: List.unmodifiable(rects),
      text: data['text']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
      color: data['color']?.toString() ?? 'yellow',
      createdAt: createdAt.toLocal(),
      noteId: data['noteId']?.toString(),
      imagePath: data['imagePath']?.toString(),
      imageStale: data['imageStale'] == true,
      tags: [
        for (final tag in (data['tags'] as List? ?? const <Object?>[]))
          if (tag?.toString().trim().isNotEmpty ?? false) tag.toString().trim(),
      ],
    );
  }
}

/// Converts a pdfrx page-space selection rectangle to a normalized rect in
/// Flutter (top-left origin, rotated page space).
///
/// pdfrx's [PdfRect] uses PDF coordinates with a y-up axis and may include page
/// rotation. Using [PdfRect.toRect] here is essential; treating top/bottom
/// directly as Flutter top/bottom produces negative heights and drops every
/// highlight.
Rect normalizePdfSelectionRect(PdfRect bounds, PdfPage page) {
  final pageSpace = bounds.toRect(page: page);
  return Rect.fromLTRB(
    pageSpace.left / page.width,
    pageSpace.top / page.height,
    pageSpace.right / page.width,
    pageSpace.bottom / page.height,
  );
}

class ReviewAnnotationStore {
  ReviewAnnotationStore(this.file);

  final File file;

  static Future<ReviewAnnotationStore> open() async {
    final support = await appSupportDirectory();
    final target = File('${support.path}/ParticleDesk/review_annotations.json');
    return ReviewAnnotationStore(target);
  }

  /// Marks the legacy JSON as migrated without deleting its contents.
  Future<void> archive() async {
    if (!await file.exists()) return;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File('${file.path}.migrated-$stamp');
    if (await target.exists()) return;
    await file.rename(target.path);
  }

  Future<List<ReviewAnnotation>> load() async =>
      (await loadDetailed()).annotations;

  /// Loads valid records and reports how many raw records were rejected.
  ///
  /// The migration must not archive a sidecar when any record was dropped.
  Future<({List<ReviewAnnotation> annotations, int rejected})>
  loadDetailed() async {
    if (!await file.exists()) {
      return (annotations: const <ReviewAnnotation>[], rejected: 0);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      await _quarantine();
      return (annotations: const <ReviewAnnotation>[], rejected: 1);
    }
    if (decoded is! List) {
      await _quarantine();
      return (annotations: const <ReviewAnnotation>[], rejected: 1);
    }
    final result = <ReviewAnnotation>[];
    var rejected = 0;
    for (final raw in decoded) {
      try {
        final annotation = ReviewAnnotation.fromJson(raw);
        if (annotation == null) {
          rejected++;
        } else {
          result.add(annotation);
        }
      } catch (_) {
        rejected++;
      }
    }
    return (annotations: result, rejected: rejected);
  }

  Future<void> _quarantine() async {
    if (!await file.exists()) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await file.rename('${file.path}.corrupt-$stamp');
  }

  Future<void> save(Iterable<ReviewAnnotation> annotations) async {
    await file.parent.create(recursive: true);
    final payload = jsonEncode([
      for (final annotation in annotations) annotation.toJson(),
    ]);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(payload, flush: true);
      // File.rename replaces an existing target atomically on macOS.
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }
}

/// Merges per-fragment text-selection rectangles into contiguous spans for
/// display. The stored fragment rectangles are still kept for exact range
/// adjustment.
List<Rect> mergeRectsForDisplay(List<Rect> rects) {
  if (rects.length <= 1) return rects;
  final ordered = [...rects]
    ..sort((a, b) {
      final top = a.top.compareTo(b.top);
      return top != 0 ? top : a.left.compareTo(b.left);
    });
  final rows = <List<Rect>>[];
  for (final rect in ordered) {
    var placed = false;
    for (final row in rows) {
      final reference = row.first;
      final overlap =
          (rect.bottom < reference.bottom ? rect.bottom : reference.bottom) -
          (rect.top > reference.top ? rect.top : reference.top);
      final minHeight = rect.height < reference.height
          ? rect.height
          : reference.height;
      if (overlap >= minHeight * 0.5) {
        row.add(rect);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add(<Rect>[rect]);
  }
  final merged = <Rect>[];
  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
    var current = row.first;
    for (final rect in row.skip(1)) {
      final gap = rect.left - current.right;
      if (gap <= 0.02) {
        current = current.expandToInclude(rect);
      } else {
        merged.add(current);
        current = rect;
      }
    }
    merged.add(current);
  }
  return merged;
}
