import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/features/notes/notes_format.dart';
import 'package:pdgapp/notes/note_evidence.dart';
import 'package:pdgapp/notes/notes.dart';

NoteAnchor _anchor({
  String targetKind = NoteTargetKinds.pdgid,
  String targetKey = 'S032M',
  String label = 'D0 (S032M)',
  NoteAnchorStatus status = NoteAnchorStatus.exact,
}) {
  return NoteAnchor(
    id: 'anchor-1',
    noteId: 'note-1',
    targetKind: targetKind,
    targetKey: targetKey,
    snapshotHash: 'hash-1',
    targetLabel: label,
    status: status,
    context: null,
    createdAt: DateTime.utc(2026, 10, 18, 8),
  );
}

NoteRecord _note({
  String title = 'D0 笔记',
  String bodyMarkdown = '**D0** 的寿命讨论。',
  String bodyPlain = 'D0 的寿命讨论。',
  List<NoteAnchor> anchors = const <NoteAnchor>[],
  List<String> tags = const <String>[],
  DateTime? updatedAt,
}) {
  return NoteRecord(
    id: 'note-1',
    uuid: 'uuid-1',
    title: title,
    bodyMarkdown: bodyMarkdown,
    bodyPlain: bodyPlain,
    createdAt: DateTime.utc(2026, 10, 18, 8),
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 18, 9),
    revision: 1,
    anchors: anchors,
    tags: [for (final tag in tags) NoteTag(tag)],
  );
}

void main() {
  const en = AppStrings(TextLang.en);

  test('titles fall back to the first body line and then to untitled', () {
    expect(noteDisplayTitle(_note(), en), 'D0 笔记');
    expect(
      noteDisplayTitle(_note(title: '  ', bodyPlain: '\n\n轻子 衰变\n第二行'), en),
      '轻子 衰变',
    );
    expect(
      noteDisplayTitle(_note(title: '', bodyPlain: ''), en),
      'Untitled note',
    );
    expect(
      noteDisplayTitle(
        _note(title: '', bodyPlain: ''),
        const AppStrings(TextLang.zh),
      ),
      '无标题笔记',
    );
  });

  test('body preview collapses whitespace and truncates by runes', () {
    expect(
      noteBodyPreview(
        _note(bodyPlain: 'first\n\n  second\tthird'),
        maxLength: 80,
      ),
      'first second third',
    );
    final long = noteBodyPreview(_note(bodyPlain: '轻' * 20), maxLength: 5);
    expect(long, '${'轻' * 5}…');
  });

  test('updated labels are local, deterministic and IME-language neutral', () {
    final now = DateTime(2026, 10, 18, 12, 0);
    expect(
      noteUpdatedLabel(DateTime(2026, 10, 18, 11, 59, 40), en, now: now),
      'just now',
    );
    expect(
      noteUpdatedLabel(DateTime(2026, 10, 18, 11, 55), en, now: now),
      '5 min ago',
    );
    expect(
      noteUpdatedLabel(DateTime(2026, 10, 18, 9, 0), en, now: now),
      '3 h ago',
    );
    expect(
      noteUpdatedLabel(DateTime(2026, 10, 17, 18, 0), en, now: now),
      'yesterday',
    );
    expect(
      noteUpdatedLabel(DateTime(2026, 10, 10, 18, 0), en, now: now),
      'Updated 2026-10-10',
    );
    expect(
      noteUpdatedLabel(
        DateTime(2026, 10, 18, 11, 55),
        const AppStrings(TextLang.zh),
        now: now,
      ),
      '5 分钟前',
    );
  });

  test(
    'anchor labels fall back to canonical keys and flag unresolved state',
    () {
      expect(anchorDisplayLabel(_anchor()), 'D0 (S032M)');
      expect(anchorDisplayLabel(_anchor(label: '')), 'S032M');
      expect(
        anchorDisplayLabel(
          _anchor(
            targetKind: NoteTargetKinds.reference,
            targetKey: 'doi:10.1103/physrevd.98.030001',
            label: '',
          ),
        ),
        '10.1103/physrevd.98.030001',
      );
      expect(
        anchorDisplayLabel(
          _anchor(
            targetKind: NoteTargetKinds.reference,
            targetKey: 'doc:42',
            label: '',
          ),
        ),
        'document 42',
      );
      expect(noteAnchorPreview(_note(anchors: [_anchor()])), 'D0 (S032M)');
      expect(noteAnchorPreview(_note()), isEmpty);
    },
  );

  test('tag parsing accepts Chinese separators and drops duplicates', () {
    expect(parseNoteTags(' lifetime, D0，寿命；lifetime '), <String>[
      'lifetime',
      'D0',
      '寿命',
    ]);
    expect(parseNoteTags('   '), isEmpty);
  });

  test('Markdown export keeps title, body, tags and anchors', () {
    final markdown = noteAsMarkdown(
      _note(
        anchors: [
          _anchor(),
          _anchor(
            targetKind: NoteTargetKinds.reference,
            targetKey: 'doc:42',
            label: 'A paper (42)',
            status: NoteAnchorStatus.unresolved,
          ),
        ],
        tags: ['D0', 'lifetime'],
      ),
      untitled: 'Untitled note',
    );
    expect(markdown, startsWith('# D0 笔记'));
    expect(markdown, contains('**D0** 的寿命讨论。'));
    expect(markdown, contains('Tags: D0, lifetime'));
    expect(markdown, contains('- D0 (S032M) — `pdgid:S032M`'));
    expect(markdown, contains('- A paper (42) — `reference:doc:42`'));
    expect(markdown, contains('Updated: 2026-10-18T09:00:00.000Z'));
  });

  test('scope Markdown has front matter and an Evidence table', () {
    final markdown = scopeMarkdown(
      scope: 'Project',
      notes: [_note()],
      evidence: [
        NoteEvidenceRow(
          type: NoteEvidenceType.measurement,
          key: 'm1',
          title: 'D0 MASS | selected',
          sourceTargetId: 'measurement:S032M:42',
          noteIds: {'note-1'},
          status: NoteEvidenceStatus.uncompared,
        ),
      ],
      untitled: 'Untitled note',
      exportedAt: DateTime.utc(2026, 10, 21, 1),
    );
    expect(markdown, startsWith('---\nscope: "Project"'));
    expect(markdown, contains('exported_at: 2026-10-21T01:00:00.000Z'));
    expect(markdown, contains('## Evidence'));
    expect(markdown, contains('| D0 MASS \\| selected | Measurement |'));
    final escaped = scopeMarkdown(
      scope: 'A "quoted" \\ path',
      notes: [_note()],
      evidence: const [],
      untitled: 'Untitled note',
    );
    final slash = String.fromCharCode(92);
    expect(
      escaped,
      contains('scope: "A $slash"quoted$slash" $slash$slash path"'),
    );
  });

  test('reference anchors deduplicate into citation-key targets', () {
    final note = _note(
      anchors: [
        _anchor(
          targetKind: NoteTargetKinds.reference,
          targetKey: 'doi:10.1000/ABC',
          label: 'Paper',
        ),
        _anchor(
          targetKind: NoteTargetKinds.reference,
          targetKey: 'doc:42',
          label: 'Paper',
        ),
      ],
    );
    final targets = referenceTargetsForCiteKeys([note, note]);
    expect(targets, hasLength(2));
    expect(targets.first.doi, '10.1000/ABC');
    expect(targets.last.documentId, '42');
  });

  test('JSON export is versioned and includes anchors and tags', () {
    final json = notesExportJson([
      _note(anchors: [_anchor()], tags: ['lifetime']),
    ], exportedAt: DateTime.utc(2026, 10, 18, 12));
    final decoded = jsonDecode(json) as Map<String, Object?>;
    expect(decoded['schema'], 'particle-library.notes.v2');
    expect(decoded['exportedAt'], '2026-10-18T12:00:00.000Z');
    expect(decoded['count'], 1);
    final notes = decoded['notes'] as List<Object?>;
    final note = notes.single as Map<String, Object?>;
    expect(note['uuid'], 'uuid-1');
    expect(note['tags'], ['lifetime']);
    final anchors = note['anchors'] as List<Object?>;
    final anchor = anchors.single as Map<String, Object?>;
    expect(anchor['targetId'], 'pdgid:S032M');
    expect(anchor['status'], 'exact');
  });
}
