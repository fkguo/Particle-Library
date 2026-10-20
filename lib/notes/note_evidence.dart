import 'notes_models.dart';

/// The three kinds of rows the Notes scope's Evidence view can show.
enum NoteEvidenceType { measurement, pdgSummary, reference }

/// Object-level state for one Evidence row. This is deliberately independent
/// of the whole-database snapshot hash.
enum NoteEvidenceStatus {
  current,
  changed,
  missing,
  fuzzy,
  unresolved,
  uncompared,
}

/// A structured value captured into an anchor context (schema v1).
class CapturedEvidence {
  const CapturedEvidence({
    required this.kind,
    required this.value,
    required this.errPlus,
    required this.errMinus,
    required this.unit,
    required this.edition,
    required this.limitType,
    required this.valueText,
    required this.propertyId,
    required this.valueType,
    required this.summaryRowId,
    required this.measurementId,
    required this.pdgid,
    this.quantityLabel,
    this.technique,
    this.referenceDoi,
    this.referenceDocumentId,
  });

  final String kind;
  final String? value;
  final String? errPlus;
  final String? errMinus;
  final String? unit;
  final String? edition;
  final String? limitType;
  final String? valueText;
  final String? propertyId;
  final String? valueType;
  final int? summaryRowId;
  final int? measurementId;
  final String? pdgid;
  final String? quantityLabel;
  final String? technique;
  final String? referenceDoi;
  final String? referenceDocumentId;

  bool get hasStructuredValue =>
      (value?.trim().isNotEmpty ?? false) ||
      (limitType?.trim().isNotEmpty ?? false);

  static CapturedEvidence? fromContext(Map<String, Object?>? context) {
    if (context == null) return null;
    if (context['ctxVersion'] != 1) return null;
    final kind = context['kind']?.toString() ?? '';
    if (kind != 'measurement' && kind != 'pdg_summary') return null;
    final value = _text(context['value']);
    final limitType = _text(context['limitType']);
    if ((value == null || value.isEmpty) &&
        (limitType == null || limitType.isEmpty)) {
      return null;
    }
    return CapturedEvidence(
      kind: kind,
      value: value,
      errPlus: _text(context['errPlus']),
      errMinus: _text(context['errMinus']),
      unit: _text(context['unit']),
      edition: _text(context['edition']),
      limitType: limitType,
      valueText: _text(context['valueText']),
      propertyId: _text(context['propertyId']),
      valueType: _text(context['valueType']),
      summaryRowId: _int(context['summaryRowId']),
      measurementId: _int(context['measurementId']),
      pdgid: _text(context['pdgid']),
      quantityLabel: _text(context['quantityLabel']),
      technique: _text(context['technique']),
      referenceDoi: _text(context['referenceDoi']),
      referenceDocumentId: _text(context['referenceDocumentId']),
    );
  }
}

/// A current value read from the read-only PDG snapshot.
class CurrentEvidence {
  const CurrentEvidence({
    required this.value,
    required this.errPlus,
    required this.errMinus,
    required this.unit,
    required this.edition,
    required this.limitType,
    required this.valueText,
    this.quantityLabel,
    this.ambiguous = false,
  });

  final String? value;
  final String? errPlus;
  final String? errMinus;
  final String? unit;
  final String edition;
  final String? limitType;
  final String? valueText;
  final String? quantityLabel;
  final bool ambiguous;

  factory CurrentEvidence.fuzzy({
    String? quantityLabel,
    required String edition,
  }) => CurrentEvidence(
    value: null,
    errPlus: null,
    errMinus: null,
    unit: null,
    edition: edition,
    limitType: null,
    valueText: '—',
    quantityLabel: quantityLabel,
    ambiguous: true,
  );
}

/// Resolves current values without exposing the notes store to the PDG layer.
abstract class NoteEvidenceResolver {
  Future<CurrentEvidence?> resolveMeasurement(
    String pdgid,
    int measurementId, {
    String? technique,
    String? referenceDoi,
    String? referenceDocumentId,
    String? quantityLabel,
  });
  Future<CurrentEvidence?> resolveSummary(CapturedEvidence captured);
}

/// One derived Evidence row. It is never persisted.
class NoteEvidenceRow {
  NoteEvidenceRow({
    required this.type,
    required this.key,
    required this.title,
    required this.sourceTargetId,
    required this.noteIds,
    this.captured,
    this.current,
    this.status = NoteEvidenceStatus.uncompared,
    this.detail = '',
  });

  final NoteEvidenceType type;
  final String key;
  final String title;
  final String sourceTargetId;
  final Set<String> noteIds;
  final CapturedEvidence? captured;
  final CurrentEvidence? current;
  NoteEvidenceStatus status;
  final String detail;

  /// A paper measurement is not expected to equal the PDG average/fit.
  /// Keep that numeric comparison informational; exports must not call it
  /// `current`/`changed`.
  NoteEvidenceStatus get displayStatus =>
      type == NoteEvidenceType.measurement &&
          (status == NoteEvidenceStatus.current ||
              status == NoteEvidenceStatus.changed)
      ? NoteEvidenceStatus.uncompared
      : status;

  int get noteCount => noteIds.length;

  String get capturedValue {
    final capturedValue = captured?.valueText?.trim() ?? '';
    if (capturedValue.isNotEmpty) return capturedValue;
    final value = captured?.value;
    if (value == null) return '—';
    return [
      value,
      captured?.unit,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
  }

  String get currentValue {
    final value = current?.valueText?.trim() ?? '';
    if (value.isNotEmpty) return value;
    final raw = current?.value;
    if (raw == null) return '—';
    return [
      raw,
      current?.unit,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
  }
}

/// Builds Evidence from notes. [resolver] is optional so widget tests can run
/// without a PDG snapshot; without it, rows are `uncompared`, never guessed.
Future<List<NoteEvidenceRow>> buildNoteEvidence(
  Iterable<NoteRecord> notes, {
  NoteEvidenceResolver? resolver,
  required String currentEdition,
}) async {
  final rows = <String, NoteEvidenceRow>{};
  for (final note in notes) {
    for (final anchor in note.anchors) {
      if (anchor.targetKind == NoteTargetKinds.measurement) {
        final captured = CapturedEvidence.fromContext(anchor.context);
        final measurementId =
            captured?.measurementId ?? _measurementId(anchor.targetKey);
        final pdgid = captured?.pdgid ?? _measurementPdgid(anchor.targetKey);
        if (measurementId == null || pdgid == null) continue;
        final current = resolver == null
            ? null
            : await resolver.resolveMeasurement(
                pdgid,
                measurementId,
                technique: captured?.technique,
                referenceDoi: captured?.referenceDoi,
                referenceDocumentId: captured?.referenceDocumentId,
                quantityLabel: captured?.quantityLabel,
              );
        final key =
            'measurement:${anchor.targetKey}:${captured?.quantityLabel ?? ''}:'
            '${captured?.value ?? ''}:${captured?.edition ?? ''}';
        final row = rows.putIfAbsent(
          key,
          () => NoteEvidenceRow(
            type: NoteEvidenceType.measurement,
            key: key,
            title:
                current?.quantityLabel ??
                captured?.quantityLabel ??
                captured?.propertyId ??
                (anchor.targetLabel.trim().isEmpty
                    ? 'Measurement ${anchor.targetKey}'
                    : anchor.targetLabel),
            sourceTargetId: anchor.targetId,
            noteIds: <String>{},
            captured: captured,
            current: current,
            detail: anchor.targetLabel,
          ),
        );
        row.noteIds.add(note.id);
        row.status = _mergeStatus(
          row.status,
          _status(anchor, captured, current, resolver),
        );
      } else if (anchor.targetKind == NoteTargetKinds.pdgid) {
        final captured = CapturedEvidence.fromContext(anchor.context);
        if (captured?.kind != 'pdg_summary') continue;
        final current = captured == null || resolver == null
            ? null
            : await resolver.resolveSummary(captured);
        final key =
            'pdg_summary:${anchor.targetKey}:${captured?.propertyId ?? ''}:${captured?.value ?? ''}:${captured?.edition ?? ''}';
        final row = rows.putIfAbsent(
          key,
          () => NoteEvidenceRow(
            type: NoteEvidenceType.pdgSummary,
            key: key,
            title:
                current?.quantityLabel ??
                captured?.quantityLabel ??
                captured?.propertyId ??
                anchor.targetLabel,
            sourceTargetId: anchor.targetId,
            noteIds: <String>{},
            captured: captured,
            current: current,
            detail: anchor.targetLabel,
          ),
        );
        row.noteIds.add(note.id);
        row.status = _mergeStatus(
          row.status,
          _status(anchor, captured, current, resolver),
        );
      } else if (anchor.targetKind == NoteTargetKinds.reference) {
        final key = 'reference:${anchor.targetKey}';
        final row = rows.putIfAbsent(
          key,
          () => NoteEvidenceRow(
            type: NoteEvidenceType.reference,
            key: key,
            title: anchor.targetLabel.trim().isEmpty
                ? anchor.targetKey
                : anchor.targetLabel,
            sourceTargetId: anchor.targetId,
            noteIds: <String>{},
            status: NoteEvidenceStatus.uncompared,
            detail: anchor.targetKey,
          ),
        );
        row.noteIds.add(note.id);
      }
    }
  }
  return rows.values.toList(growable: false);
}

int _statusRank(NoteEvidenceStatus status) => switch (status) {
  NoteEvidenceStatus.unresolved => 5,
  NoteEvidenceStatus.missing => 4,
  NoteEvidenceStatus.fuzzy => 3,
  NoteEvidenceStatus.changed => 2,
  NoteEvidenceStatus.current => 1,
  NoteEvidenceStatus.uncompared => 0,
};

NoteEvidenceStatus _mergeStatus(
  NoteEvidenceStatus existing,
  NoteEvidenceStatus next,
) => _statusRank(next) > _statusRank(existing) ? next : existing;

NoteEvidenceStatus _status(
  NoteAnchor anchor,
  CapturedEvidence? captured,
  CurrentEvidence? current,
  NoteEvidenceResolver? resolver,
) {
  if (anchor.status == NoteAnchorStatus.fuzzy) return NoteEvidenceStatus.fuzzy;
  if (anchor.status == NoteAnchorStatus.unresolved) {
    return NoteEvidenceStatus.unresolved;
  }
  if (resolver == null) return NoteEvidenceStatus.uncompared;
  if (current == null) return NoteEvidenceStatus.missing;
  if (captured == null || !captured.hasStructuredValue) {
    return NoteEvidenceStatus.uncompared;
  }
  if (current.ambiguous) return NoteEvidenceStatus.fuzzy;
  final capturedUnit = captured.unit?.trim() ?? '';
  final currentUnit = current.unit?.trim() ?? '';
  if (capturedUnit.isNotEmpty &&
      currentUnit.isNotEmpty &&
      capturedUnit != currentUnit) {
    return NoteEvidenceStatus.uncompared;
  }
  if (_same(captured.value, current.value) &&
      _same(captured.limitType, current.limitType) &&
      _compatible(captured.errPlus, current.errPlus) &&
      _compatible(captured.errMinus, current.errMinus)) {
    return NoteEvidenceStatus.current;
  }
  return NoteEvidenceStatus.changed;
}

bool _compatible(String? captured, String? current) {
  final left = captured?.trim() ?? '';
  final right = current?.trim() ?? '';
  if (left.isEmpty || right.isEmpty) return true;
  return _same(left, right);
}

bool _same(String? a, String? b) {
  final left = a?.trim() ?? '';
  final right = b?.trim() ?? '';
  if (left.isEmpty || right.isEmpty) return left.isEmpty && right.isEmpty;
  final leftNumber = double.tryParse(left);
  final rightNumber = double.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final difference = (leftNumber - rightNumber).abs();
    final scale = leftNumber.abs() > rightNumber.abs()
        ? leftNumber.abs()
        : rightNumber.abs();
    if (scale == 0) return true;
    return difference <= 1e-12 * scale;
  }
  return left == right;
}

int? _measurementId(String key) {
  final index = key.lastIndexOf(':');
  return index < 0 ? null : int.tryParse(key.substring(index + 1));
}

String? _measurementPdgid(String key) {
  final index = key.lastIndexOf(':');
  return index <= 0 ? null : key.substring(0, index);
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
