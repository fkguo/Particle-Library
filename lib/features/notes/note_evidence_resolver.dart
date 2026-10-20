import '../../data/pdg_database.dart';
import '../../domain/display.dart';
import '../../domain/models.dart';
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
    // A measurement is a paper-level object; the useful "current" comparison
    // is the current PDG summary (average/fit) for the same quantity. Keeping
    // the measurement row itself would compare it with an identical frozen
    // value and would never reveal a change in the PDG consensus.
    final entry = await _database.entryByPdgid(pdgid);
    if (entry == null) return null;
    final summaries = await _database.summariesForEntry(
      entry.id,
      edition: _database.currentEdition,
    );
    final selection = selectBestSummary(summaries);
    final preferred = selection.preferred;
    if (preferred == null) return null;
    return _fromSummary(preferred);
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
    return _fromSummary(summary);
  }

  Future<CurrentEvidence> _fromSummary(Summary summary) async {
    final display = DisplayQuantity.fromSummary(summary);
    final quantityLabel = await _database.descriptionForPdgid(summary.pdgid);
    return CurrentEvidence(
      value: summary.value?.toString(),
      errPlus: summary.errorPositive?.toString(),
      errMinus: summary.errorNegative?.toString(),
      unit: summary.unitText,
      edition: _database.currentEdition,
      limitType: _limitType(summary.limitType),
      valueText: display.text,
      quantityLabel: quantityLabel,
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
