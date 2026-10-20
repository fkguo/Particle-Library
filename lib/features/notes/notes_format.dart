import 'dart:convert';

import '../../app/app_strings.dart';
import '../../notes/note_evidence.dart';
import '../../notes/notes.dart';

/// Visible title for a note: the title, else the first body line, else a
/// localized placeholder.
String noteDisplayTitle(NoteRecord note, AppStrings strings) {
  final title = note.title.trim();
  if (title.isNotEmpty) return title;
  final firstLine = note.bodyPlain
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) return strings.notesUntitled;
  return _truncate(firstLine, 60);
}

/// One-line plain-text preview of the stored Markdown body.
String noteBodyPreview(NoteRecord note, {int maxLength = 160}) {
  final text = note.bodyPlain.replaceAll(RegExp(r'\s+'), ' ').trim();
  return _truncate(text, maxLength);
}

/// Localized “updated …” label for list rows.
///
/// [now] is injectable so the formatting can be tested deterministically.
String noteUpdatedLabel(
  DateTime updatedAt,
  AppStrings strings, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final local = updatedAt.toLocal();
  final difference = current.difference(local);
  if (!difference.isNegative) {
    if (difference.inMinutes < 1) return strings.notesJustNow;
    if (difference.inMinutes < 60) {
      return strings.notesMinutesAgo(difference.inMinutes);
    }
    if (difference.inHours < 24 && _sameDay(current, local)) {
      return strings.notesHoursAgo(difference.inHours);
    }
  }
  if (_sameDay(current, local)) {
    return strings.notesUpdated(
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}',
    );
  }
  final yesterday = DateTime(
    current.year,
    current.month,
    current.day,
  ).subtract(const Duration(days: 1));
  if (_sameDay(yesterday, local)) return strings.notesYesterday;
  return strings.notesUpdated(
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}',
  );
}

/// Human label of one stored anchor; falls back to a readable form of the
/// canonical target key when the frozen label is empty.
String anchorDisplayLabel(NoteAnchor anchor) {
  final label = anchor.targetLabel.trim();
  if (label.isNotEmpty) return label;
  if (anchor.targetKind == NoteTargetKinds.pdgid) {
    return anchor.targetKey;
  }
  final key = anchor.targetKey;
  if (key.startsWith('doi:')) return key.substring(4);
  if (key.startsWith('doc:')) return 'document ${key.substring(4)}';
  return anchor.targetId;
}

/// Label of the first anchor, used as an anchor preview in note lists.
String noteAnchorPreview(NoteRecord note) =>
    note.anchors.isEmpty ? '' : anchorDisplayLabel(note.anchors.first);

/// Splits the editor's tag field.
///
/// Commas/semicolons separate tags, and `#tag` tokens are accepted as well.
/// Tags without `#` keep spaces, so the historical comma-separated form still
/// works. Hashtags are extracted even when several appear in one part.
List<String> parseNoteTags(String input) {
  final tags = <String>[];
  final seen = <String>{};
  for (final part in input.split(RegExp(r'[,，;；]'))) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final hashes = RegExp(r'#([^\s#,;]+)')
        .allMatches(trimmed)
        .map((match) => match.group(1)!.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (hashes.isNotEmpty) {
      for (final tag in hashes) {
        if (seen.add(tag)) tags.add(tag);
      }
      continue;
    }
    if (seen.add(trimmed)) tags.add(trimmed);
  }
  return tags;
}

/// Whether [note] matches a note-list query across body and note metadata.
///
/// The store does this in SQL for global search; a collection-filtered list is
/// already loaded with anchors/tags, so it uses this matcher instead.
bool noteMatchesQuery(NoteRecord note, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  bool matches(String value) => value.toLowerCase().contains(needle);
  if (matches(note.title) ||
      matches(note.bodyPlain) ||
      matches(note.bodyMarkdown)) {
    return true;
  }
  if (note.anchors.any((a) => matches(a.targetKey) || matches(a.targetLabel))) {
    return true;
  }
  if (note.tagNames.any(matches)) return true;
  return note.collections.any((c) => matches(c.name));
}

/// A reference anchor resolved enough to ask INSPIRE for a citation key.
class ReferenceAnchorTarget {
  const ReferenceAnchorTarget({this.doi, this.documentId});

  final String? doi;
  final String? documentId;
}

/// Unique reference targets in [notes], DOI first.
List<ReferenceAnchorTarget> referenceTargetsForCiteKeys(
  Iterable<NoteRecord> notes,
) {
  final seen = <String>{};
  final result = <ReferenceAnchorTarget>[];
  for (final note in notes) {
    for (final anchor in note.anchors) {
      if (anchor.targetKind != NoteTargetKinds.reference) continue;
      final key = anchor.targetKey.trim();
      String? doi;
      String? documentId;
      if (key.toLowerCase().startsWith('doi:')) {
        doi = key.substring(4).trim();
      } else if (key.toLowerCase().startsWith('doc:')) {
        documentId = key.substring(4).trim();
      }
      if ((doi == null || doi.isEmpty) &&
          (documentId == null || documentId.isEmpty)) {
        continue;
      }
      final identity = 'doi:${doi ?? ''}|doc:${documentId ?? ''}';
      if (seen.add(identity)) {
        result.add(
          ReferenceAnchorTarget(
            doi: doi?.isEmpty ?? true ? null : doi,
            documentId: documentId?.isEmpty ?? true ? null : documentId,
          ),
        );
      }
    }
  }
  return result;
}

/// Markdown archive for one Notes scope: front matter, notes and Evidence.
String scopeMarkdown({
  required String scope,
  required List<NoteRecord> notes,
  required List<NoteEvidenceRow> evidence,
  required String untitled,
  DateTime? exportedAt,
}) {
  final stamp = (exportedAt ?? DateTime.now().toUtc())
      .toUtc()
      .toIso8601String();
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('scope: ${_yaml(scope)}')
    ..writeln('exported_at: $stamp')
    ..writeln('notes: ${notes.length}')
    ..writeln('evidence_rows: ${evidence.length}')
    ..writeln('---')
    ..writeln()
    ..writeln('# $scope')
    ..writeln();
  for (final note in notes) {
    buffer
      ..writeln('---')
      ..writeln()
      ..writeln(noteAsMarkdown(note, untitled: untitled))
      ..writeln();
  }
  if (evidence.isNotEmpty) {
    buffer
      ..writeln('## Evidence')
      ..writeln()
      ..writeln('| Quantity | Type | Captured | PDG current | Status | Notes |')
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final row in evidence) {
      buffer.writeln(
        '| ${_mdCell(row.title)} | ${_typeLabel(row.type)} | '
        '${_mdCell(row.capturedValue)} | ${_mdCell(row.currentValue)} | '
        '${row.displayStatus.name} | ${row.noteCount} |',
      );
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String _mdCell(String value) =>
    value.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('|', '\\|');

String _yaml(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _typeLabel(NoteEvidenceType type) => switch (type) {
  NoteEvidenceType.measurement => 'Measurement',
  NoteEvidenceType.pdgSummary => 'PDG summary',
  NoteEvidenceType.reference => 'Reference',
};

/// Markdown representation used by the editor's copy action.
String noteAsMarkdown(NoteRecord note, {String untitled = 'Untitled note'}) {
  final buffer = StringBuffer();
  final title = note.title.trim();
  buffer.writeln('# ${title.isEmpty ? untitled : title}');
  buffer.writeln();
  final body = note.bodyMarkdown.trimRight();
  if (body.isNotEmpty) {
    buffer.writeln(body);
    buffer.writeln();
  }
  final tags = note.tagNames;
  if (tags.isNotEmpty) {
    buffer.writeln('Tags: ${tags.join(', ')}');
    buffer.writeln();
  }
  final collections = note.collectionNames;
  if (collections.isNotEmpty) {
    buffer.writeln('Collections: ${collections.join(', ')}');
    buffer.writeln();
  }
  if (note.anchors.isNotEmpty) {
    buffer.writeln('Anchors:');
    for (final anchor in note.anchors) {
      final label = anchor.targetLabel.trim();
      buffer.writeln(
        label.isEmpty
            ? '- `${anchor.targetId}`'
            : '- $label — `${anchor.targetId}`',
      );
    }
    buffer.writeln();
  }
  buffer.writeln('Updated: ${note.updatedAt.toUtc().toIso8601String()}');
  return buffer.toString().trimRight();
}

/// Versioned JSON backup copied from the Notes page.
///
/// The top-level registry preserves empty collections and collection
/// timestamps; notes also keep their embedded collection objects so older
/// importers can still recover referenced collections by name.
String notesExportJson(
  Iterable<NoteRecord> notes, {
  DateTime? exportedAt,
  Iterable<NoteCollection> collections = const <NoteCollection>[],
}) {
  final records = notes.toList(growable: false);
  final collectionList = collections.toList(growable: false);
  final payload = <String, Object?>{
    'schema': 'particle-library.notes.v2',
    'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'count': records.length,
    'collections': [
      for (final collection in collectionList) collection.toJson(),
    ],
    'notes': [for (final note in records) note.toJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _truncate(String value, int maxLength) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= maxLength) return value;
  return '${String.fromCharCodes(runes.take(maxLength))}…';
}
