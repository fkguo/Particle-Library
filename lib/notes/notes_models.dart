/// Domain models for local user notes.
///
/// Notes are stored in a dedicated SQLite database (`ParticleDesk/user.db`),
/// never in the read-only PDG snapshot and never in `user_store.json`.
library;

/// Canonical `note_anchors.target_kind` values.
///
/// The full anchor key exposed to the rest of the app is
/// `$targetKind:$targetKey`:
///
/// * `pdgid:S032M`
/// * `reference:doi:10.1103/physrevd.98.030001`
/// * `reference:doc:123`
abstract final class NoteTargetKinds {
  static const String pdgid = 'pdgid';
  static const String reference = 'reference';
  static const String measurement = 'measurement';
  static const String note = 'note';
  static const String review = 'review';
}

/// Anchoring state of a note to a PDG object or reference.
///
/// [exact] is the only state treated as resolved. [fuzzy] and [unresolved] are
/// surfaced by [NotesStore.unresolved] so P1 can offer a re-anchor flow. A
/// legacy/database value of `resolved` is read as [exact].
enum NoteAnchorStatus {
  exact('exact'),
  fuzzy('fuzzy'),
  unresolved('unresolved');

  const NoteAnchorStatus(this.wireName);

  /// Value stored in `note_anchors.status`.
  final String wireName;

  bool get isResolved => this == NoteAnchorStatus.exact;

  /// Reads a status, defaulting unknown values to [unresolved] rather than
  /// making a whole note unreadable.
  static NoteAnchorStatus fromWireName(String? value) {
    if (value == 'resolved') return NoteAnchorStatus.exact;
    for (final status in NoteAnchorStatus.values) {
      if (status.wireName == value) return status;
    }
    return NoteAnchorStatus.unresolved;
  }
}

/// Read-only identity of a target used by batch count queries.
///
/// Equality includes [snapshotHash]; a `null`/empty hash means "any snapshot".
/// [kind] is trimmed and lower-cased, [key] is trimmed.
String _requireReferenceValue(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return trimmed;
}

class NoteTarget {
  NoteTarget({required String kind, required String key, String? snapshotHash})
    : kind = kind.trim().toLowerCase(),
      key = key.trim(),
      snapshotHash = _normalizeSnapshotHash(snapshotHash);

  static String? _normalizeSnapshotHash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  factory NoteTarget.pdgid(String pdgid, {String? snapshotHash}) => NoteTarget(
    kind: NoteTargetKinds.pdgid,
    key: pdgid.trim(),
    snapshotHash: snapshotHash,
  );

  factory NoteTarget.referenceDoi(String doi, {String? snapshotHash}) =>
      NoteTarget(
        kind: NoteTargetKinds.reference,
        key: 'doi:${_requireReferenceValue(doi, 'doi').toLowerCase()}',
        snapshotHash: snapshotHash,
      );

  factory NoteTarget.referenceDoc(String documentId, {String? snapshotHash}) =>
      NoteTarget(
        kind: NoteTargetKinds.reference,
        key: 'doc:${_requireReferenceValue(documentId, 'documentId')}',
        snapshotHash: snapshotHash,
      );

  factory NoteTarget.measurement(String key, {String? snapshotHash}) =>
      NoteTarget(
        kind: NoteTargetKinds.measurement,
        key: key.trim(),
        snapshotHash: snapshotHash,
      );

  factory NoteTarget.note(String uuid) =>
      NoteTarget(kind: NoteTargetKinds.note, key: uuid.trim());

  /// A review PDF identified by `<edition>/<file>`.
  factory NoteTarget.review(String reviewKey) => NoteTarget(
    kind: NoteTargetKinds.review,
    key: _requireReferenceValue(reviewKey, 'reviewKey'),
  );

  final String kind;
  final String key;
  final String? snapshotHash;

  /// Canonical external key, e.g. `pdgid:S032M`.
  String get targetId => '$kind:$key';

  @override
  bool operator ==(Object other) =>
      other is NoteTarget &&
      other.kind == kind &&
      other.key == key &&
      other.snapshotHash == snapshotHash;

  @override
  int get hashCode => Object.hash(kind, key, snapshotHash);

  @override
  String toString() =>
      'NoteTarget($targetId${snapshotHash == null ? '' : '@$snapshotHash'})';
}

/// An input anchor supplied to [NotesStore.create] or [NotesStore.update].
///
/// [targetLabel] is a frozen, human-readable label captured at note time (for
/// example `D0 (S032M)` or a reference title). [snapshotHash] ties the anchor
/// to the verified PDG snapshot; an empty/null hash means the target is not
/// snapshot-specific.
class NoteAnchorInput {
  const NoteAnchorInput({
    required this.targetKind,
    required this.targetKey,
    this.snapshotHash,
    this.targetLabel = '',
    this.status = NoteAnchorStatus.exact,
    this.context,
  });

  factory NoteAnchorInput.pdgid(
    String pdgid, {
    String? snapshotHash,
    String targetLabel = '',
    NoteAnchorStatus status = NoteAnchorStatus.exact,
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.pdgid,
    targetKey: pdgid.trim(),
    snapshotHash: snapshotHash,
    targetLabel: targetLabel,
    status: status,
    context: context,
  );

  factory NoteAnchorInput.referenceDoi(
    String doi, {
    String? snapshotHash,
    String targetLabel = '',
    NoteAnchorStatus status = NoteAnchorStatus.exact,
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.reference,
    targetKey: 'doi:${_requireReferenceValue(doi, 'doi').toLowerCase()}',
    snapshotHash: snapshotHash,
    targetLabel: targetLabel,
    status: status,
    context: context,
  );

  factory NoteAnchorInput.referenceDoc(
    String documentId, {
    String? snapshotHash,
    String targetLabel = '',
    NoteAnchorStatus status = NoteAnchorStatus.exact,
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.reference,
    targetKey: 'doc:${_requireReferenceValue(documentId, 'documentId')}',
    snapshotHash: snapshotHash,
    targetLabel: targetLabel,
    status: status,
    context: context,
  );

  factory NoteAnchorInput.measurement(
    String key, {
    String? snapshotHash,
    String targetLabel = '',
    NoteAnchorStatus status = NoteAnchorStatus.exact,
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.measurement,
    targetKey: key.trim(),
    snapshotHash: snapshotHash,
    targetLabel: targetLabel,
    status: status,
    context: context,
  );

  factory NoteAnchorInput.note(
    String uuid, {
    String targetLabel = '',
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.note,
    targetKey: uuid.trim(),
    targetLabel: targetLabel,
    context: context,
  );

  /// An anchor from one PDF highlight to the review document.
  factory NoteAnchorInput.review(
    String reviewKey, {
    String targetLabel = '',
    Map<String, Object?>? context,
  }) => NoteAnchorInput(
    targetKind: NoteTargetKinds.review,
    targetKey: _requireReferenceValue(reviewKey, 'reviewKey'),
    targetLabel: targetLabel,
    context: context,
  );

  final String targetKind;
  final String targetKey;
  final String? snapshotHash;
  final String targetLabel;
  final NoteAnchorStatus status;
  final Map<String, Object?>? context;

  String get targetId => '$targetKind:$targetKey';
}

/// A persisted anchor row.
class NoteAnchor {
  const NoteAnchor({
    required this.id,
    required this.noteId,
    required this.targetKind,
    required this.targetKey,
    required this.snapshotHash,
    required this.targetLabel,
    required this.status,
    required this.context,
    required this.createdAt,
  });

  final String id;
  final String noteId;
  final String targetKind;
  final String targetKey;

  /// Empty when the anchor is not tied to a specific snapshot.
  final String snapshotHash;
  final String targetLabel;
  final NoteAnchorStatus status;
  final Map<String, Object?>? context;
  final DateTime createdAt;

  String get targetId => '$targetKind:$targetKey';

  bool get isResolved => status.isResolved;

  Map<String, Object?> toJson() => {
    'id': id,
    'noteId': noteId,
    'targetKind': targetKind,
    'targetKey': targetKey,
    'targetId': targetId,
    'snapshotHash': snapshotHash,
    'targetLabel': targetLabel,
    'status': status.wireName,
    'context': context,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// A tag attached to a note.
///
/// Tags are trimmed, empty tags are dropped, and duplicates are removed when a
/// note is written. Storage/return order is lexicographic.
class NoteTag {
  const NoteTag(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is NoteTag && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// A stored note together with its anchors and tags.
class NoteRecord {
  const NoteRecord({
    required this.id,
    required this.uuid,
    required this.title,
    required this.bodyMarkdown,
    required this.bodyPlain,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.deletedAt,
    this.anchors = const <NoteAnchor>[],
    this.tags = const <NoteTag>[],
    this.collections = const <NoteCollection>[],
  });

  final String id;

  /// Stable identity for export/sync. Distinct from [id] (local row identity).
  final String uuid;

  final String title;
  final String bodyMarkdown;

  /// Plain text derived from [bodyMarkdown] at write time.
  final String bodyPlain;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Non-null for a soft-deleted note. Soft-deleted notes are retained for
  /// export/recovery but excluded from recent/search/target queries.
  final DateTime? deletedAt;
  final int revision;
  final List<NoteAnchor> anchors;
  final List<NoteTag> tags;
  final List<NoteCollection> collections;

  bool get isDeleted => deletedAt != null;

  List<String> get tagNames => [for (final tag in tags) tag.name];

  List<String> get collectionNames => [
    for (final collection in collections) collection.name,
  ];

  /// Returns the anchor for a target, if present.
  ///
  /// When [snapshotHash] is omitted, any snapshot matches.
  NoteAnchor? anchorFor(
    String targetKind,
    String targetKey, {
    String? snapshotHash,
  }) {
    final wantKind = targetKind.trim().toLowerCase();
    final wantKey = targetKey.trim();
    final wantHash = snapshotHash?.trim() ?? '';
    for (final anchor in anchors) {
      if (anchor.targetKind != wantKind || anchor.targetKey != wantKey) {
        continue;
      }
      if (wantHash.isNotEmpty && anchor.snapshotHash != wantHash) continue;
      return anchor;
    }
    return null;
  }

  /// JSON-ready representation used by [NotesStore.allForExport].
  Map<String, Object?> toJson() => {
    'id': id,
    'uuid': uuid,
    'title': title,
    'bodyMarkdown': bodyMarkdown,
    'bodyPlain': bodyPlain,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    'revision': revision,
    'anchors': [for (final anchor in anchors) anchor.toJson()],
    'tags': tagNames,
    'collections': [for (final collection in collections) collection.toJson()],
  };
}

/// A user-created collection. Notes and collections are many-to-many.
class NoteCollection {
  const NoteCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// A collection plus its active-note count, returned by
/// [NotesStore.collectionSummaries] for navigation and management.
class NoteCollectionSummary {
  const NoteCollectionSummary({
    required this.collection,
    required this.activeNoteCount,
  });

  final NoteCollection collection;
  final int activeNoteCount;

  String get id => collection.id;
  String get name => collection.name;
}
