import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/features/plot/plot_data.dart';

Summary row(
  String edition, {
  double? value = 1,
  double? plus = 0.1,
  double? minus = 0.1,
  bool table = true,
  String? limit,
  String unit = 'MeV',
  bool percent = false,
  String type = 'AC',
}) {
  return Summary({
    'id': edition.hashCode,
    'pdgid_id': 1,
    'pdgid': 'X',
    'edition': edition,
    'value_type': type,
    'in_summary_table': table,
    'value': value,
    'error_positive': plus,
    'error_negative': minus,
    'unit_text': unit,
    'display_value_text': '$value',
    'display_power_of_ten': 0,
    'display_in_percent': percent,
    'limit_type': limit,
  });
}

void main() {
  test('trend uses one preferred summary per edition and sorts years', () {
    final data = buildEditionTrend(
      [row('2024', value: 3), row('2022', value: 1), row('2026', value: 5)],
      label: 'W MASS',
      currentEdition: '2026',
    );
    expect(data.hasTrend, isTrue);
    final points = data.points;
    expect(points.map((p) => p.x).toList(), [2022, 2024, 2026]);
    expect(points.map((p) => p.y).toList(), [1, 3, 5]);
    expect(points.last.current, isTrue);
    expect(data.series.single.unit, 'MeV');
  });

  test('ambiguous, limit and missing editions are skipped', () {
    final data = buildEditionTrend(
      [
        row('2022', value: 1),
        row('2023', value: 2, table: false),
        row('2023', value: 3, table: false),
        row('2024', value: null),
        row('2025', value: 4, limit: 'U'),
        row('2026', value: 5),
      ],
      label: 'X',
      currentEdition: '2026',
    );
    expect(data.points.map((p) => p.x), [2022, 2026]);
    expect(data.skippedAmbiguous, 1);
    expect(data.skippedMissing, 1);
    expect(data.skippedLimits, 1);
  });

  test('percent values are plotted as percent', () {
    final data = buildEditionTrend(
      [
        row(
          '2024',
          value: 0.10,
          plus: 0.01,
          minus: 0.01,
          unit: '',
          percent: true,
        ),
        row(
          '2026',
          value: 0.12,
          plus: 0.02,
          minus: 0.02,
          unit: '',
          percent: true,
        ),
      ],
      label: 'BR',
      currentEdition: '2026',
    );
    expect(data.points.map((p) => p.y), [10, 12]);
    expect(data.points.first.errorPlus, closeTo(1, 1e-9));
    expect(data.series.single.unit, '%');
  });

  test('PDG Average and PDG Fit become separate selectable trends', () {
    final data = buildEditionTrend(
      [
        row('2022', value: 1, type: 'FC'),
        row('2022', value: 2, type: 'AC'),
        row('2024', value: 3, type: 'FC'),
        row('2024', value: 4, type: 'AC'),
        row('2026', value: 5, type: 'FC'),
        row('2026', value: 6, type: 'AC'),
      ],
      label: 'X',
      currentEdition: '2026',
    );
    expect(data.hasTrend, isTrue);
    expect(data.series.map((series) => series.valueType), ['AC', 'FC']);
    expect(data.points.map((point) => point.y), [2, 4, 6]);
    final fit = data.selectSeries(1);
    expect(fit.points.map((point) => point.y), [1, 3, 5]);
    expect(fit.series.single.valueType, 'FC');
  });

  test('unit changes are not silently merged', () {
    final data = buildEditionTrend(
      [row('2024', unit: 'MeV'), row('2026', unit: 'GeV')],
      label: 'X',
      currentEdition: '2026',
    );
    expect(data.unitMismatch, isTrue);
    expect(data.hasTrend, isFalse);
    expect(data.series, isEmpty);
  });
}
