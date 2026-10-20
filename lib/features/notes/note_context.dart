import '../../domain/models.dart';

/// Version of the structured anchor context written by capture actions.
const int noteContextVersion = 1;

/// Builds the structured context captured from one measurement card.
///
/// The numeric fields are copied from the same source row that the current
/// value is derived from; [displayText] is for display only and is never used
/// for change detection.
Map<String, Object?> measurementNoteContext({
  required Measurement measurement,
  required MeasurementValue? value,
  required String displayText,
  required String edition,
  Reference? reference,
  String? quantityLabel,
}) {
  return <String, Object?>{
    'ctxVersion': noteContextVersion,
    'kind': 'measurement',
    'measurementId': measurement.id,
    'pdgid': measurement.pdgid,
    'propertyId': null,
    'quantityLabel': quantityLabel?.trim().isNotEmpty == true
        ? quantityLabel!.trim()
        : measurement.pdgid,
    'valueType': 'measurement',
    'value': _decimal(value?.value),
    'errPlus': _decimal(value?.errorPositive),
    'errMinus': _decimal(value?.errorNegative),
    'statPlus': _decimal(value?.statErrorPositive),
    'statMinus': _decimal(value?.statErrorNegative),
    'systPlus': _decimal(value?.systErrorPositive),
    'systMinus': _decimal(value?.systErrorNegative),
    'unit': value?.unitText ?? '',
    'limitType': _limitType(value?.limitType),
    'cl': value?.limitType == null ? null : measurement.confidenceLevel,
    'edition': edition,
    'technique': measurement.technique,
    'referenceDoi': _optional(reference?.doi),
    'referenceDocumentId': _optional(reference?.documentId),
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'valueText': displayText,
  };
}

/// Builds the structured context captured from one PDG summary row.
Map<String, Object?> summaryNoteContext(
  Summary summary, {
  required String displayText,
  required String edition,
  String? quantityLabel,
}) {
  return <String, Object?>{
    'ctxVersion': noteContextVersion,
    'kind': 'pdg_summary',
    'measurementId': null,
    'pdgid': summary.pdgid,
    'propertyId': summary.pdgid,
    'summaryRowId': summary.id,
    'quantityLabel': quantityLabel?.trim().isNotEmpty == true
        ? quantityLabel!.trim()
        : summary.pdgid,
    'valueType': summary.valueType,
    'value': _decimal(summary.value),
    'errPlus': _decimal(summary.errorPositive),
    'errMinus': _decimal(summary.errorNegative),
    'statPlus': null,
    'statMinus': null,
    'systPlus': null,
    'systMinus': null,
    'unit': summary.unitText,
    'limitType': _limitType(summary.limitType),
    'cl': summary.confidenceLevel,
    'edition': summary.edition?.trim().isNotEmpty == true
        ? summary.edition!.trim()
        : edition,
    'technique': null,
    'referenceDoi': null,
    'referenceDocumentId': null,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'valueText': displayText,
  };
}

String? _decimal(double? value) => value?.toString();

String? _optional(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? _limitType(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  if (value == 'U') return 'upper';
  if (value == 'L') return 'lower';
  return null;
}
