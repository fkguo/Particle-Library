import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/display.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/domain/models.dart';

Summary summary({
  int id = 1,
  String display = '1.23',
  String? valueText = '1.23',
  String unit = '',
  int power = 0,
  bool percent = false,
  String? limit,
  String valueType = 'AC',
  bool inSummaryTable = false,
  double? value = 1.23,
}) {
  return Summary({
    'id': id,
    'pdgid_id': 1,
    'pdgid': 'S000',
    'edition': '2026',
    'value_type': valueType,
    'in_summary_table': inSummaryTable ? 1 : 0,
    'confidence_level': null,
    'limit_type': limit,
    'comment': null,
    'value': value,
    'value_text': valueText,
    'error_positive': null,
    'error_negative': null,
    'scale_factor': null,
    'unit_text': unit,
    'display_value_text': display,
    'display_power_of_ten': power,
    'display_in_percent': percent ? 1 : 0,
    'sort': id,
  });
}

void main() {
  test('a truncated complex pole keeps the imaginary part', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: '3874.75+-0.10',
        valueText: '(3874.75+-0.10) - i (0.024+0.001-0.007)',
        unit: 'MeV',
        value: null,
      ),
    );
    // The full pole is shown verbatim: never truncate to the real part.
    expect(quantity.numberText, '(3874.75 ± 0.10) - i (0.024+0.001-0.007)');
    expect(displayNumberNeedsMath(quantity.numberText), isTrue);
  });

  test('percent display does not stack the implied -2 power again', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: '3.936+-0.030',
        power: -2,
        percent: true,
        value: 0.03936,
      ),
    );
    expect(quantity.text, '3.936 ± 0.030%');
    expect(quantity.text.contains('10'), isFalse);
  });

  test('percent stored as unit % is not doubled', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(display: '12.5', unit: '%', percent: false),
    );
    expect(quantity.text, '12.5 %');
  });

  test('large power is restored once from the display fields', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: '>14000',
        valueText: '> 14000 E30',
        unit: 'years',
        power: 30,
        limit: 'U',
        value: 1.4e34,
      ),
    );
    expect(quantity.text, '>14000×10³⁰ years');
    expect(quantity.isLimit, isTrue);
  });

  test('negative signed display keeps the ± conversion', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(display: '1864.84+-0.04', unit: 'MeV'),
    );
    expect(quantity.text, '1864.84 ± 0.04 MeV');
  });

  test('best summary follows the strict official rule', () {
    final one = selectBestSummary([summary(id: 1)]);
    expect(one.preferred?.id, 1);

    final multipleOneTable = selectBestSummary([
      summary(id: 1, inSummaryTable: true, valueType: 'FC'),
      summary(id: 2, inSummaryTable: false, valueType: 'AC'),
    ]);
    expect(multipleOneTable.preferred?.id, 1);
    expect(multipleOneTable.isAmbiguous, isFalse);

    final multipleNoTable = selectBestSummary([
      summary(id: 1, valueType: 'FC'),
      summary(id: 2, valueType: 'AC'),
    ]);
    expect(multipleNoTable.preferred, isNull);
    expect(multipleNoTable.isAmbiguous, isTrue);
    expect(multipleNoTable.candidates.length, 2);

    final multipleTables = selectBestSummary([
      summary(id: 1, inSummaryTable: true),
      summary(id: 2, inSummaryTable: true),
    ]);
    expect(multipleTables.preferred, isNull);
    expect(multipleTables.candidates.length, 2);
  });

  test('summary value_type and measurement inclusion flags stay distinct', () {
    expect(valueTypeLabel('FC', TextLang.zh), contains('拟合'));
    expect(valueTypeLabel('FC', TextLang.zh), isNot(contains('用于')));
    expect(valueTypeLabel('AC', TextLang.zh), contains('平均'));
    expect(valueTypeShortLabel('AC', TextLang.en), 'PDG Average');
    expect(valueTypeShortLabel('FC', TextLang.en), 'PDG Fit');
    expect(valueTypeShortLabel('AC', TextLang.zh), contains('平均'));
    expect(valueTypeShortLabel('FC', TextLang.zh), contains('拟合'));
    expect(inclusionLabel(true, 'fit', TextLang.zh), contains('fit 标志'));
    expect(
      inclusionLabel(true, 'fit', TextLang.zh),
      isNot(contains('OUR FIT')),
    );
    expect(
      inclusionLabel(false, 'average', TextLang.zh),
      contains('average 标志'),
    );
    expect(inclusionLabel(null, 'average', TextLang.zh), contains('未注明'));
  });

  test('embedded and header exponents are combined', () {
    final lifetime = DisplayQuantity.fromSummary(
      summary(
        display: '(1637+-4)E-3',
        valueText: '(1637+-4)E-3',
        unit: 's',
        power: -12,
        value: 1.637e-12,
      ),
    );
    expect(lifetime.text, '(1637 ± 4)×10⁻¹⁵ s');
    expect(
      displayNumberLatex(lifetime.numberText),
      r'(1637 \pm 4)\times 10^{-15}',
    );

    final old = DisplayQuantity.fromSummary(
      summary(
        display: '(222.0+-2.0)E-2',
        valueText: '(222.0+-2.0)E-2',
        power: -6,
        value: 2.22e-6,
      ),
    );
    expect(old.text, '(222.0 ± 2.0)×10⁻⁸');
  });

  test('power of ten wraps a multi-term value', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: '10.89+-0.01+-0.08',
        valueText: '(10.89+-0.01+-0.08) E-2',
        power: -2,
        value: 0.1089,
      ),
    );
    expect(quantity.text, '(10.89 ± 0.01 ± 0.08)×10⁻²');
    expect(
      displayNumberLatex(quantity.numberText),
      r'(10.89 \pm 0.01 \pm 0.08)\times 10^{-2}',
    );
  });

  test('unit already in number is not repeated', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: 'none 1-9 GeV',
        valueText: 'none 1-9 GeV',
        unit: 'GeV',
        value: null,
      ),
    );
    expect(quantity.text, 'none 1-9 GeV');
  });

  test('E exponents become times ten', () {
    expect(displayNumberNeedsMath('(9 ± 5)E-5'), isTrue);
    expect(displayNumberLatex('(9 ± 5)E-5'), r'(9 \pm 5)\times 10^{-5}');
    final quantity = DisplayQuantity.fromSummary(
      summary(display: '(9+-5)E-5', valueText: '(9+-5)E-5', value: 9e-5),
    );
    expect(quantity.text, '(9 ± 5)×10⁻⁵');
  });

  test('a pole without parentheses keeps the full value', () {
    final quantity = DisplayQuantity.fromSummary(
      summary(
        display: '517- i 240',
        valueText: '517- i 240',
        unit: 'MeV',
        value: null,
      ),
    );
    expect(quantity.numberText, '517- i 240');
    expect(displayNumberNeedsMath(quantity.numberText), isTrue);
  });

  test('complex values and units get readable math', () {
    expect(displayNumberNeedsMath('5.3 +0.9-0.7'), isTrue);
    expect(displayNumberLatex('5.3 +0.9-0.7'), r'5.3\;{}^{+0.9}_{-0.7}');
    expect(
      displayNumberLatex('(445 ± 25)- i(278 +22-18)'),
      r'(445 \pm 25) - i\,(278\;{}^{+22}_{-18})',
    );
    expect(prettyUnit('GeV**-1'), 'GeV⁻¹');
    expect(prettyUnit('MeV/c**2'), 'MeV/c²');
    expect(displayNumberNeedsMath('1864.84 ± 0.04'), isFalse);
  });

  test('confidence levels keep meaningful decimals', () {
    expect(formatConfidence(90), '90');
    expect(formatConfidence(99.85), '99.85');
    expect(formatConfidence(97.6999969482422), '97.7');
    expect(formatConfidence(100), '100');
  });

  test('raw NULL and raw zero are distinct', () {
    expect(rawNumber(null), 'NULL');
    expect(rawNumber(0), '0');
    expect(rawNumber(0.0), '0');
  });
}
