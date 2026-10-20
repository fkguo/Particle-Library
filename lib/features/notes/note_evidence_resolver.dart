import '../../data/pdg_database.dart';
import '../../domain/display.dart';
import '../../notes/note_evidence.dart';

/// Resolves Evidence current values from the read-only PDG snapshot.
class PdgEvidenceResolver implements NoteEvidenceResolver {
  PdgEvidenceResolver(this._database);

  final PdgDatabase _database;

  @override
  Future<CurrentEvidence?> resolveMeasurement(
    String pdgid,
    int measurementId,
  ) async {
    final bundle = await _database.measurementById(measurementId);
    if (bundle == null || bundle.measurement.pdgid != pdgid) return null;
    final value = bundle.primaryValue;
    if (value == null) return null;
    final display = DisplayQuantity.fromValue(value);
    return CurrentEvidence(
      value: value.value?.toString(),
      errPlus: value.errorPositive?.toString(),
      errMinus: value.errorNegative?.toString(),
      unit: value.unitText,
      edition: _database.currentEdition,
      limitType: _limitType(value.limitType),
      valueText: display.text,
    );
  }

  @override
  Future<CurrentEvidence?> resolveSummary(CapturedEvidence captured) async {
    final pdgid = captured.pdgid;
    final valueType = captured.valueType;
    final rowId = captured.summaryRowId;
    if (pdgid == null || valueType == null || rowId == null) return null;
    final summary = await _database.currentSummaryForCapture(
      pdgid: pdgid,
      valueType: valueType,
      capturedRowId: rowId,
    );
    if (summary == null) return null;
    final display = DisplayQuantity.fromSummary(summary);
    return CurrentEvidence(
      value: summary.value?.toString(),
      errPlus: summary.errorPositive?.toString(),
      errMinus: summary.errorNegative?.toString(),
      unit: summary.unitText,
      edition: _database.currentEdition,
      limitType: _limitType(summary.limitType),
      valueText: display.text,
    );
  }
}

String? _limitType(String? raw) {
  switch (raw?.trim().toUpperCase()) {
    case 'U':
      return 'upper';
    case 'L':
      return 'lower';
    default:
      return null;
  }
}
