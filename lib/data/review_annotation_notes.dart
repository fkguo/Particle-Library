import 'dart:math';
import 'dart:ui';

import '../features/reviews/review_index.dart';
import '../notes/notes_models.dart';
import '../notes/notes_store.dart';
import 'review_annotations.dart';

/// Stores PDF highlights as ordinary notes with a `review` anchor.
///
/// The note body is the searchable source of truth for the quote and comment;
/// [ReviewAnnotation] is only the viewer projection. Geometry stays in the
/// anchor context and never reaches the notes search index.
class ReviewAnnotationNotes {
  ReviewAnnotationNotes._();

  static Future<void>? _migration;

  /// One-time migration of the legacy `review_annotations.json` sidecar.
  ///
  /// The source file is renamed, never deleted. A failed migration leaves it
  /// in place so the next open can retry.
  static Future<void> ensureMigrated(NotesStore notes) {
    final running = _migration;
    if (running != null) return running;
    final future = _migrate(notes);
    _migration = future;
    return future.catchError((Object error, StackTrace stack) {
      if (identical(_migration, future)) _migration = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// Visible for migration tests; production uses [ensureMigrated].
  static Future<void> migrate(NotesStore notes, ReviewAnnotationStore legacy) =>
      _migrate(notes, legacy);

  static Future<void> _migrate(
    NotesStore notes, [
    ReviewAnnotationStore? legacyStore,
  ]) async {
    final legacy = legacyStore ?? await ReviewAnnotationStore.open();
    if (!await legacy.file.exists()) return;
    final loaded = await legacy.loadDetailed();
    final records = loaded.annotations;
    var duplicateIds = false;
    final seenIds = <String>{};
    for (final record in records) {
      if (!seenIds.add(record.id)) {
        duplicateIds = true;
        continue;
      }
      final uuid = 'legacy-anno-${record.id}';
      if (await notes.noteByUuid(uuid, includeDeleted: true) != null) {
        continue;
      }
      await _createNote(
        notes,
        fileName: record.fileName,
        pageNumber: record.pageNumber,
        rects: record.rects,
        text: record.text,
        comment: record.note,
        color: record.color,
        reviewTitle: _titleFromFile(record.fileName),
        uuid: uuid,
        createdAt: record.createdAt,
        imagePath: record.imagePath,
        imageStale: record.imageStale,
        tags: record.tags,
      );
    }
    // Keep the sidecar for a retry if malformed/duplicate records were
    // dropped; valid records are already imported idempotently.
    if (loaded.rejected == 0 && !duplicateIds) {
      await legacy.archive();
    }
  }

  /// All notes anchored to [fileName], including annotation notes. The
  /// inspector's Notes tab lists these; the Annotations tab projects the
  /// subset that carries page geometry.
  static Future<List<NoteRecord>> notesFor(NotesStore notes, String fileName) =>
      notes.notesForTarget(NoteTargetKinds.review, _reviewKey(fileName));

  static Future<List<ReviewAnnotation>> load(
    NotesStore notes,
    String fileName, {
    required String reviewTitle,
  }) async {
    final key = _reviewKey(fileName);
    final records = await notes.notesForTarget(NoteTargetKinds.review, key);
    final result = <ReviewAnnotation>[];
    for (final note in records) {
      NoteAnchor? anchor;
      for (final candidate in note.anchors) {
        if (candidate.targetKind == NoteTargetKinds.review &&
            candidate.targetKey == key) {
          anchor = candidate;
          break;
        }
      }
      if (anchor == null) continue;
      final annotation = _fromNote(note, anchor, fileName);
      if (annotation != null) result.add(annotation);
    }
    result.sort((a, b) {
      final page = a.pageNumber.compareTo(b.pageNumber);
      return page != 0 ? page : a.createdAt.compareTo(b.createdAt);
    });
    return result;
  }

  static Future<ReviewAnnotation> create(
    NotesStore notes, {
    required String fileName,
    required int pageNumber,
    required List<Rect> rects,
    required String text,
    required String color,
    required String reviewTitle,
    String comment = '',
    String? imagePath,
    bool imageStale = false,
    Iterable<String> tags = const <String>[],
  }) => _createNote(
    notes,
    fileName: fileName,
    pageNumber: pageNumber,
    rects: rects,
    text: text,
    comment: comment,
    color: color,
    reviewTitle: reviewTitle,
    imagePath: imagePath,
    imageStale: imageStale,
    tags: tags,
  );

  static Future<void> updateComment(
    NotesStore notes,
    ReviewAnnotation annotation,
    String comment, {
    Iterable<String>? tags,
  }) async {
    final noteId = annotation.noteId;
    if (noteId == null) return;
    final note = await notes.noteById(noteId);
    if (note == null) return;
    final reviewKey = _reviewKey(annotation.fileName);
    final reviewTitle = _reviewTitleFor(note, annotation);
    final currentComment = _commentFor(note, annotation);
    final oldBody = _body(
      quote: annotation.text,
      comment: currentComment,
      reviewKey: reviewKey,
      annotationId: annotation.id,
      pageNumber: annotation.pageNumber,
      reviewTitle: reviewTitle,
    );
    final body = _body(
      quote: annotation.text,
      comment: comment,
      reviewKey: reviewKey,
      annotationId: annotation.id,
      pageNumber: annotation.pageNumber,
      reviewTitle: reviewTitle,
    );
    // Do not overwrite prose the user added in the full note editor. The
    // comment remains authoritative in the anchor context; only an untouched
    // generated body is rewritten.
    final generatedBodyUntouched = note.bodyMarkdown.trim() == oldBody.trim();
    final commentChanged = currentComment != comment.trim();
    final nextBody = !commentChanged
        ? null
        : generatedBodyUntouched
        ? body
        : _projectComment(note.bodyMarkdown, comment);
    final anchors = <NoteAnchorInput>[];
    for (final anchor in note.anchors) {
      final isReviewAnchor =
          anchor.targetKind == NoteTargetKinds.review &&
          anchor.targetKey == reviewKey;
      anchors.add(
        NoteAnchorInput(
          targetKind: anchor.targetKind,
          targetKey: anchor.targetKey,
          snapshotHash: anchor.snapshotHash.isEmpty
              ? null
              : anchor.snapshotHash,
          targetLabel: anchor.targetLabel,
          status: anchor.status,
          context: isReviewAnchor
              ? {...?anchor.context, 'comment': comment}
              : anchor.context,
        ),
      );
    }
    await notes.update(
      note.id,
      bodyMarkdown: nextBody,
      anchors: anchors,
      tags: tags,
      expectedRevision: note.revision,
    );
  }

  static Future<ReviewAnnotation?> updateRange(
    NotesStore notes,
    ReviewAnnotation annotation, {
    required List<Rect> rects,
    required String text,
    String? imagePath,
    bool? imageStale,
  }) async {
    final noteId = annotation.noteId;
    if (noteId == null) return null;
    final note = await notes.noteById(noteId);
    if (note == null) return null;
    final reviewKey = _reviewKey(annotation.fileName);
    final reviewTitle = _reviewTitleFor(note, annotation);
    final currentComment = _commentFor(note, annotation);
    final oldBody = _body(
      quote: annotation.text,
      comment: currentComment,
      reviewKey: reviewKey,
      annotationId: annotation.id,
      pageNumber: annotation.pageNumber,
      reviewTitle: reviewTitle,
    );
    final body = _body(
      quote: text,
      comment: currentComment,
      reviewKey: reviewKey,
      annotationId: annotation.id,
      pageNumber: annotation.pageNumber,
      reviewTitle: reviewTitle,
    );
    final anchors = <NoteAnchorInput>[];
    for (final anchor in note.anchors) {
      final isReviewAnchor =
          anchor.targetKind == NoteTargetKinds.review &&
          anchor.targetKey == reviewKey;
      anchors.add(
        NoteAnchorInput(
          targetKind: anchor.targetKind,
          targetKey: anchor.targetKey,
          snapshotHash: anchor.snapshotHash.isEmpty
              ? null
              : anchor.snapshotHash,
          targetLabel: anchor.targetLabel,
          status: anchor.status,
          context: isReviewAnchor
              ? {
                  ...?anchor.context,
                  'rects': [
                    for (final rect in rects)
                      [rect.left, rect.top, rect.right, rect.bottom],
                  ],
                  'quote': text,
                  'imagePath': ?imagePath,
                  if (imageStale != null)
                    'imageStale': imageStale ? true : null,
                }
              : anchor.context,
        ),
      );
    }
    final generatedBodyUntouched = note.bodyMarkdown.trim() == oldBody.trim();
    final generatedTitle = _title(
      annotation.pageNumber,
      annotation.text,
      reviewTitle: reviewTitle,
    );
    final title = note.title.trim().isEmpty || note.title == generatedTitle
        ? _title(annotation.pageNumber, text, reviewTitle: reviewTitle)
        : note.title;
    await notes.update(
      note.id,
      title: title,
      bodyMarkdown: generatedBodyUntouched ? body : null,
      anchors: anchors,
      expectedRevision: note.revision,
    );
    return ReviewAnnotation(
      id: annotation.id,
      fileName: annotation.fileName,
      pageNumber: annotation.pageNumber,
      rects: List.unmodifiable(rects),
      text: text,
      note: annotation.note,
      color: annotation.color,
      createdAt: annotation.createdAt,
      noteId: annotation.noteId,
      imagePath: imagePath ?? annotation.imagePath,
      imageStale: imageStale ?? annotation.imageStale,
      tags: note.tagNames,
    );
  }

  static Future<void> delete(
    NotesStore notes,
    ReviewAnnotation annotation,
  ) async {
    final noteId = annotation.noteId;
    if (noteId != null) await notes.delete(noteId);
  }

  static Future<ReviewAnnotation> _createNote(
    NotesStore notes, {
    required String fileName,
    required int pageNumber,
    required List<Rect> rects,
    required String text,
    required String comment,
    required String color,
    required String reviewTitle,
    String? uuid,
    DateTime? createdAt,
    String? imagePath,
    bool imageStale = false,
    Iterable<String> tags = const <String>[],
  }) async {
    final id = _newAnnotationId(pageNumber);
    final reviewKey = _reviewKey(fileName);
    final body = _body(
      quote: text,
      comment: comment,
      reviewKey: reviewKey,
      annotationId: id,
      pageNumber: pageNumber,
      reviewTitle: reviewTitle,
    );
    final title = _title(pageNumber, text, reviewTitle: reviewTitle);
    final context = <String, Object?>{
      'schema': 1,
      'kind': 'pdf_annotation',
      'annotationId': id,
      'reviewTitle': reviewTitle,
      'pageNumber': pageNumber,
      'rects': [
        for (final rect in rects)
          [rect.left, rect.top, rect.right, rect.bottom],
      ],
      'color': color,
      'quote': text,
      'comment': comment,
      'imagePath': ?imagePath,
      if (imageStale) 'imageStale': true,
    };
    final note = await notes.create(
      title: title,
      bodyMarkdown: body,
      uuid: uuid,
      createdAt: createdAt,
      tags: tags,
      anchors: [
        NoteAnchorInput.review(
          reviewKey,
          targetLabel: '$reviewTitle · p.$pageNumber',
          context: context,
        ),
      ],
    );
    return ReviewAnnotation(
      id: id,
      fileName: fileName,
      pageNumber: pageNumber,
      rects: List.unmodifiable(rects),
      text: text,
      note: comment,
      color: color,
      createdAt: note.createdAt,
      noteId: note.id,
      imagePath: imagePath,
      imageStale: imageStale,
      tags: note.tagNames,
    );
  }

  static ReviewAnnotation? _fromNote(
    NoteRecord note,
    NoteAnchor anchor,
    String fileName,
  ) {
    final context = anchor.context;
    if (context == null) return null;
    final page = _asInt(context['pageNumber']);
    final text = context['quote']?.toString() ?? '';
    final id = context['annotationId']?.toString().trim();
    if (page == null || page <= 0 || id == null || id.isEmpty) return null;
    final rawRects = context['rects'];
    if (rawRects is! List) return null;
    final rects = <Rect>[];
    for (final raw in rawRects) {
      if (raw is! List || raw.length != 4) continue;
      final values = [for (final value in raw) _asDouble(value)];
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
      pageNumber: page,
      rects: List.unmodifiable(rects),
      text: text,
      note:
          context['comment']?.toString() ?? _commentFromBody(note.bodyMarkdown),
      color: context['color']?.toString() ?? 'yellow',
      createdAt: note.createdAt,
      noteId: note.id,
      imagePath: context['imagePath']?.toString(),
      imageStale: context['imageStale'] == true,
      tags: note.tagNames,
    );
  }

  static String _commentFor(NoteRecord note, ReviewAnnotation annotation) {
    for (final anchor in note.anchors) {
      if (anchor.targetKind != NoteTargetKinds.review) continue;
      final comment = anchor.context?['comment'];
      if (comment != null) return comment.toString();
    }
    return annotation.note;
  }

  static String _reviewTitleFor(NoteRecord note, ReviewAnnotation annotation) {
    final suffix = ' · p.${annotation.pageNumber}';
    for (final anchor in note.anchors) {
      if (anchor.targetKind != NoteTargetKinds.review) continue;
      final label = anchor.targetLabel.trim();
      if (label.endsWith(suffix)) {
        final title = label.substring(0, label.length - suffix.length).trim();
        if (title.isNotEmpty) return title;
      }
      final contextTitle = anchor.context?['reviewTitle']?.toString().trim();
      if (contextTitle != null && contextTitle.isNotEmpty) {
        return contextTitle;
      }
    }
    return _titleFromFile(annotation.fileName);
  }

  static String _body({
    required String quote,
    required String comment,
    required String reviewKey,
    required String annotationId,
    required int pageNumber,
    required String reviewTitle,
  }) {
    final quoted = quote
        .split('\n')
        .map((line) => '> ${line.trimRight()}')
        .join('\n');
    final sourceLabel = '$reviewTitle · p.$pageNumber';
    final sourceTarget = 'review:$reviewKey#$annotationId';
    final trailing = comment.trim();
    return [
      quoted,
      if (trailing.isNotEmpty) '',
      if (trailing.isNotEmpty) trailing,
      '',
      '[${_escapeLabel(sourceLabel)}]($sourceTarget)',
    ].join('\n');
  }

  static String _projectComment(String body, String comment) {
    const startMarker = '<!-- annotation-comment:start -->';
    const endMarker = '<!-- annotation-comment:end -->';
    var before = body;
    var after = '';
    final start = before.indexOf(startMarker);
    if (start >= 0) {
      final end = before.indexOf(endMarker, start + startMarker.length);
      if (end >= 0) {
        after = before.substring(end + endMarker.length).trim();
        before = before.substring(0, start);
      } else {
        before = before.substring(0, start);
      }
    }
    // Migrate the old single-marker projection without deleting prose the user
    // appended after its quoted comment.
    before = before.replaceAll(
      RegExp(r'\n*<!-- annotation-comment -->\n> [^\n]*\n?'),
      '',
    );
    final parts = <String>[
      if (before.trim().isNotEmpty) before.trimRight(),
      if (comment.trim().isNotEmpty)
        '$startMarker\n> ${comment.trim()}\n$endMarker',
      if (after.isNotEmpty) after,
    ];
    return parts.isEmpty ? '' : '${parts.join('\n\n')}\n';
  }

  static String _commentFromBody(String body) {
    final lines = body.split('\n');
    final result = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '<!-- annotation-comment -->' ||
          trimmed == '<!-- annotation-comment:start -->' ||
          trimmed == '<!-- annotation-comment:end -->') {
        continue;
      }
      if (trimmed.startsWith('>')) continue;
      if (RegExp(r'^\[.*\]\(review:[^)]+\)$').hasMatch(trimmed)) continue;
      result.add(line);
    }
    return result.join('\n').trim();
  }

  static String _reviewKey(String fileName) => '$reviewEdition/$fileName';

  static String _title(int page, String text, {String reviewTitle = ''}) {
    final snippet = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final review = reviewTitle.trim();
    final head = review.isEmpty ? 'p.$page' : '$review · p.$page';
    if (snippet.isEmpty) return head;
    final runes = snippet.runes.toList(growable: false);
    final short = runes.length > 40
        ? '${String.fromCharCodes(runes.take(39))}…'
        : snippet;
    return '$head · “$short”';
  }

  static String _titleFromFile(String fileName) {
    final name = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    return name;
  }

  static String _escapeLabel(String value) => value.replaceAll('[', '\\[');

  static int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static double? _asDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static String _newAnnotationId(int page) =>
      '${DateTime.now().microsecondsSinceEpoch}-$page-${Random().nextInt(1 << 31)}';
}
