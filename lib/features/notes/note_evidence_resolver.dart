import '../../data/pdg_database.dart';
import '../../domain/display.dart';
import '../../domain/models.dart';
import '../../notes/note_evidence.dart';

/// Resolves Evidence current values from the read-only PDG snapshot.
class PdgEvidenceResolver implements NoteEvidenceResolver {
  PdgEvidenceResolver(this._database);

  final PdgDatabase _database;
  final Map<String, Future<CurrentEvidence?>> _quantityCache =
      <String, Future<CurrentEvidence?>>{};
  final Map<int, Future<MeasurementBundle?>> _measurementCache =
      <int, Future<MeasurementBundle?>>{};
  final Map<String, Future<CurrentEvidence?>> _summaryCache =
      <String, Future<CurrentEvidence?>>{};
  final Map<String, Future<String?>> _descriptionCache =
      <String, Future<String?>>{};

  @override
  Future<CurrentEvidence?> resolveMeasurement(
    String pdgid,
    int measurementId, {
    String? technique,
    String? referenceDoi,
    String? referenceDocumentId,
    String? quantityLabel,
  }) async {
    // A measurement is a paper-level object; the useful "current" comparison
    // is the current PDG summary (average/fit) for the same quantity.
    final summary = await _summaryForQuantity(pdgid);
    if (summary == null) return null;

    var ambiguous = false;
    final bundle = await _measurement(measurementId);
    final idMatches = bundle != null && bundle.measurement.pdgid == pdgid;
    if (!idMatches) {
      final candidates = await _database.measurementCandidatesForFingerprint(
        pdgid: pdgid,
        quantityLabel: quantityLabel ?? summary.quantityLabel,
        technique: technique,
        referenceDoi: referenceDoi,
        referenceDocumentId: referenceDocumentId,
      );
      ambiguous = candidates.length > 1;
    }
    if (ambiguous) {
      return CurrentEvidence(
        value: summary.value,
        errPlus: summary.errPlus,
        errMinus: summary.errMinus,
        unit: summary.unit,
        edition: summary.edition,
        limitType: summary.limitType,
        valueText: summary.valueText,
        quantityLabel: summary.quantityLabel,
        ambiguous: true,
      );
    }
    return summary;
  }

  @override
  Future<CurrentEvidence?> resolveSummary(CapturedEvidence captured) async {
    final pdgid = captured.pdgid;
    final valueType = captured.valueType;
    final rowId = captured.summaryRowId;
    if (pdgid == null || valueType == null || rowId == null) return null;
    final key = '$pdgid\u0000$valueType\u0000$rowId';
    return _cached(_summaryCache, key, () async {
      final candidates = await _database.currentSummaryCandidatesForCapture(
        pdgid: pdgid,
        valueType: valueType,
        capturedRowId: rowId,
      );
      if (candidates.isEmpty) return null;
      if (candidates.length > 1) {
        return CurrentEvidence.fuzzy(
          quantityLabel: await _description(pdgid),
          edition: _database.currentEdition,
        );
      }
      return _fromSummary(candidates.single);
    });
  }

  Future<CurrentEvidence?> _summaryForQuantity(String pdgid) {
    return _cached(_quantityCache, pdgid, () async {
      final entry = await _database.entryByPdgid(pdgid);
      if (entry == null) return null;
      final summaries = await _database.summariesForEntry(
        entry.id,
        edition: _database.currentEdition,
      );
      final selection = selectBestSummary(summaries);
      final preferred = selection.preferred;
      if (preferred != null) return _fromSummary(preferred);
      if (selection.candidates.isNotEmpty) {
        return CurrentEvidence.fuzzy(
          quantityLabel: await _description(pdgid),
          edition: _database.currentEdition,
        );
      }
      return null;
    });
  }

  Future<MeasurementBundle?> _measurement(int id) {
    return _cached(_measurementCache, id, () => _database.measurementById(id));
  }

  Future<String?> _description(String pdgid) {
    return _cached(
      _descriptionCache,
      pdgid,
      () => _database.descriptionForPdgid(pdgid),
    );
  }

  Future<T> _cached<T>(
    Map<Object, Future<T>> cache,
    Object key,
    Future<T> Function() load,
  ) {
    return cache.putIfAbsent(key, () async {
      try {
        return await load();
      } catch (_) {
        cache.remove(key);
        rethrow;
      }
    });
  }

  Future<CurrentEvidence> _fromSummary(Summary summary) async {
    final display = DisplayQuantity.fromSummary(summary);
    final quantityLabel = await _description(summary.pdgid);
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
