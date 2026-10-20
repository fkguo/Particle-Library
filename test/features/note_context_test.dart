import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/features/notes/note_context.dart';

void main() {
  test('measurement context carries structured values and references', () {
    final measurement = Measurement({
      'id': 42,
      'pdgid_id': 7,
      'pdgid': 'S008EPL',
      'pdgreference_id': 3,
      'technique': 'J/psi X',
      'confidence_level': 0.9,
    });
    final value = MeasurementValue({
      'id': 1,
      'pdgmeasurement_id': 42,
      'column_name': 'VALUE',
      'value': 3871.64,
      'error_positive': 0.06,
      'error_negative': 0.06,
      'stat_error_positive': 0.02,
      'stat_error_negative': 0.02,
      'syst_error_positive': 0.04,
      'syst_error_negative': 0.04,
      'unit_text': 'MeV',
      'display_value_text': '3871.64',
    });
    final reference = Reference({
      'id': 3,
      'document_id': 'BESIII-2024',
      'doi': '10.1103/PhysRevD.99.000001',
    });

    final context = measurementNoteContext(
      measurement: measurement,
      value: value,
      displayText: '3871.64 ± 0.06 MeV',
      edition: '2026',
      reference: reference,
      quantityLabel: 'chi_c1(3872) mass',
    );

    expect(context['ctxVersion'], 1);
    expect(context['kind'], 'measurement');
    expect(context['value'], '3871.64');
    expect(context['errPlus'], '0.06');
    expect(context['statPlus'], '0.02');
    expect(context['systMinus'], '0.04');
    expect(context['limitType'], isNull);
    expect(context['referenceDoi'], '10.1103/PhysRevD.99.000001');
    expect(context['referenceDocumentId'], 'BESIII-2024');
    expect(context['valueText'], '3871.64 ± 0.06 MeV');
  });

  test('summary context preserves property, type, limit and edition', () {
    final summary = Summary({
      'id': 9,
      'pdgid_id': 7,
      'pdgid': 'S008EPL',
      'edition': '2024',
      'value_type': 'OUR AVERAGE',
      'value': 3871.64,
      'error_positive': 0.06,
      'error_negative': 0.06,
      'unit_text': 'MeV',
      'limit_type': 'U',
      'confidence_level': 0.95,
      'display_value_text': '3871.64',
    });

    final context = summaryNoteContext(
      summary,
      displayText: '< 3871.64 MeV',
      edition: '2026',
      quantityLabel: 'chi_c1(3872) mass',
    );

    expect(context['kind'], 'pdg_summary');
    expect(context['propertyId'], 'S008EPL');
    expect(context['summaryRowId'], 9);
    expect(context['valueType'], 'OUR AVERAGE');
    expect(context['limitType'], 'upper');
    expect(context['cl'], 0.95);
    expect(context['edition'], '2024');
  });
}
