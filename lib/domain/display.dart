import 'labels.dart';
import 'models.dart';

/// The unified screen/copy representation of a PDG value.
///
/// `display_value_text` never contains the power of ten or the percent sign.
/// This object reconstructs the official display without applying the power to
/// the already-interpreted stored `value`, and without adding a second percent
/// sign. [rawDisplayText] keeps the untouched source string.
class DisplayQuantity {
  const DisplayQuantity({
    required this.text,
    required this.numberText,
    required this.unitText,
    required this.rawDisplayText,
    required this.rawValueText,
    required this.limitType,
    required this.powerOfTen,
    required this.inPercent,
    required this.confidenceLevel,
    required this.hasNumericValue,
  });

  final String text;
  final String numberText;
  final String unitText;
  final String rawDisplayText;
  final String rawValueText;
  final String? limitType;
  final int powerOfTen;
  final bool inPercent;
  final double? confidenceLevel;
  final bool hasNumericValue;

  bool get isLimit => limitType == 'U' || limitType == 'L';
  bool get isRange => limitType == 'R' || limitType == 'X';

  String get textWithConfidence {
    if (confidenceLevel == null) return text;
    final cl = _compactNumber(confidenceLevel!);
    return '$text (CL $cl%)';
  }

  factory DisplayQuantity.fromSummary(Summary summary) =>
      DisplayQuantity._build(
        displayText: summary.displayValueText,
        rawValueText: summary.valueText,
        unitText: summary.unitText,
        powerOfTen: summary.displayPowerOfTen,
        inPercent: summary.displayInPercent,
        limitType: summary.limitType,
        value: summary.value,
        confidenceLevel: summary.confidenceLevel,
      );

  factory DisplayQuantity.fromValue(MeasurementValue value) =>
      DisplayQuantity._build(
        displayText: value.displayValueText,
        rawValueText: value.valueText,
        unitText: value.unitText,
        powerOfTen: value.displayPowerOfTen,
        inPercent: value.displayInPercent,
        limitType: value.limitType,
        value: value.value,
        confidenceLevel: null,
      );

  factory DisplayQuantity._build({
    required String displayText,
    required String? rawValueText,
    required String unitText,
    required int powerOfTen,
    required bool inPercent,
    required String? limitType,
    required double? value,
    required double? confidenceLevel,
  }) {
    final hasRaw = rawValueText != null && rawValueText.trim().isNotEmpty;
    var number = displayText.trim();
    final rawText = (rawValueText ?? '').trim();
    // A complex pole must never be shortened to its real part: PDG stores the
    // full value in `value_text` but sometimes puts only the mass in
    // `display_value_text` (e.g. the T_cc(3875)+ pole). The raw text wins
    // whenever it contains a pole, even if the display text has one too.
    if (isComplexPole(rawText) || number.isEmpty) {
      number = rawText;
    }
    if (number.isEmpty && value != null) {
      number = _compactNumber(value);
    }

    var hasNumeric = value != null;
    // A source display text can carry its own exponent (e.g. "(1637+-4)E-3")
    // while display_power_of_ten holds the listing-level exponent. The two
    // are relative, so the visible exponent is their sum.
    int? embeddedPower;
    if (number.isNotEmpty) {
      final exponent = RegExp(r'\s*[Ee]([+-]?[0-9]+)\s*$').firstMatch(number);
      if (exponent != null) {
        embeddedPower = int.tryParse(exponent.group(1)!);
        number = number.substring(0, exponent.start).trimRight();
      }
    }
    final effectivePower = inPercent
        ? (embeddedPower ?? 0)
        : powerOfTen + (embeddedPower ?? 0);

    if (number.isNotEmpty) {
      number = number.replaceAll('+-', ' ± ');
      if (effectivePower != 0 && (!inPercent || effectivePower != -2)) {
        number = _withPowerOfTen(number, effectivePower);
      }
      if (!inPercent && (limitType == 'U' || limitType == 'L')) {
        final wantsUpper = limitType == 'U';
        final first = number.isEmpty ? '' : number.substring(0, 1);
        if (first != '<' && first != '>' && first != '≤' && first != '≥') {
          number = '${wantsUpper ? '<' : '>'} $number';
        }
      }
      if (inPercent) {
        if (!number.endsWith('%') && !number.contains('%')) {
          number = '$number%';
        }
      }
      number = number.replaceAllMapped(
        RegExp(r'([0-9.)])\s*[Ee]([+-]?[0-9]+)'),
        (match) => '${match.group(1)}${_timesTen(int.parse(match.group(2)!))}',
      );
      number = number.replaceAll('--', '–');
    }

    var unit = unitText;
    if (inPercent && unit.trim() == '%') unit = '';
    if (number.endsWith('%') && unit.trim() == '%') unit = '';
    final unitTrimmed = unit.trim();
    if (unitTrimmed.isNotEmpty && number.trim().endsWith(unitTrimmed)) {
      unit = '';
    }

    final text = [
      if (number.isNotEmpty) number,
      if (unit.isNotEmpty) prettyUnit(unit),
    ].join(' ');

    return DisplayQuantity(
      text: text.isEmpty ? (hasRaw ? rawValueText.trim() : '—') : text,
      numberText: number,
      unitText: unit,
      rawDisplayText: displayText,
      rawValueText: rawValueText ?? '',
      limitType: limitType,
      powerOfTen: powerOfTen,
      inPercent: inPercent,
      confidenceLevel: confidenceLevel,
      hasNumericValue: hasNumeric,
    );
  }
}

String _withPowerOfTen(String number, int power) {
  final trimmed = number.trim();
  final base = trimmed.contains('±') && !trimmed.startsWith('(')
      ? '($trimmed)'
      : trimmed;
  return '$base${_timesTen(power)}';
}

String _timesTen(int power) {
  final superscript = _superscriptInt(power);
  return '×10$superscript';
}

String _superscriptInt(int value) {
  const digits = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '-': '⁻',
    '+': '⁺',
  };
  return value.toString().split('').map((c) => digits[c] ?? c).join();
}

String _compactNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toString();
  if (text.contains('e')) {
    final parts = text.split('e');
    final exponent = int.tryParse(parts[1]);
    if (exponent != null) return '${parts[0]}${_timesTen(exponent)}';
  }
  return text;
}

/// Raw numeric source value, shown in the record inspector. Never used as a
/// display value for a limit/range row.
String formatConfidence(double value) {
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String rawNumber(double? value) {
  if (value == null) return 'NULL';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Strict "official preferred summary" selection from the design (§5).
///
/// - exactly one listing summary row: that row;
/// - more than one row but exactly one Summary-Table row: that row;
/// - otherwise there is no unique preferred row and every candidate stays
///   visible. A single row carrying a limit is still that one row.
class SummarySelection {
  const SummarySelection({required this.candidates, required this.preferred});

  final List<Summary> candidates;
  final Summary? preferred;

  bool get isEmpty => candidates.isEmpty;
  bool get isAmbiguous => candidates.isNotEmpty && preferred == null;
  bool get isUnique => preferred != null;
  int get count => candidates.length;

  List<Summary> get otherCandidates => candidates
      .where((row) => row.id != preferred?.id)
      .toList(growable: false);

  List<Summary> get summaryTableRows =>
      candidates.where((row) => row.inSummaryTable).toList(growable: false);
}

SummarySelection selectBestSummary(List<Summary> rows) {
  if (rows.isEmpty) {
    return const SummarySelection(candidates: [], preferred: null);
  }
  if (rows.length == 1) {
    return SummarySelection(
      candidates: List.unmodifiable(rows),
      preferred: rows.first,
    );
  }
  final tableRows = rows
      .where((row) => row.inSummaryTable)
      .toList(growable: false);
  if (tableRows.length == 1) {
    return SummarySelection(
      candidates: List.unmodifiable(rows),
      preferred: tableRows.first,
    );
  }
  return SummarySelection(candidates: List.unmodifiable(rows), preferred: null);
}

String inclusionLabel(bool? value, String kind, TextLang lang) {
  final name = kind == 'average' ? 'average' : 'fit';
  final status = value == null
      ? pick(lang, '未注明', 'not stated')
      : value
      ? pick(lang, '是', 'yes')
      : pick(lang, '否', 'no');
  return pick(lang, '$name 标志：$status', '$name flag: $status');
}

String scaleFactorNote(double? factor, TextLang lang) {
  if (factor == null || (factor - 1.0).abs() < 1e-12) return '';
  return pick(
    lang,
    '误差调整因子（原样记录，不再乘入误差）：${_compactNumber(factor)}',
    'Error scale factor (recorded, not re-applied): ${_compactNumber(factor)}',
  );
}

/// Units are stored exactly as published. The display helper only turns the
/// documented `**` exponent spelling into a readable form; the raw field stays
/// available in the inspector.
String prettyUnit(String unit) {
  if (unit.isEmpty) return unit;
  return unit
      .replaceAll('hbar', 'ℏ')
      .replaceAll('**-1/2', '⁻¹ᐟ²')
      .replaceAll('**1/2', '¹ᐟ²')
      .replaceAll('**-1', '⁻¹')
      .replaceAll('**-2', '⁻²')
      .replaceAll('**2', '²')
      .replaceAll('**3', '³');
}

/// True when [text] carries a complex pole, in either PDG spelling:
/// `(445 ± 25)- i(278 +22-18)` or `517- i 240`.
final RegExp _complexPolePattern = RegExp(
  r'(\bi\s*\()|([-\u2212]\s*i\s*[-+]?\d)',
);

bool isComplexPole(String text) => _complexPolePattern.hasMatch(text);

/// Values whose source text uses asymmetric errors, ranges or a complex
/// notation need a math line; simple values keep the tabular selectable text.
bool displayNumberNeedsMath(String number) {
  if (number.contains('--') || isComplexPole(number)) return true;
  if (RegExp(r'[Ee][+-]?[0-9]+').hasMatch(number)) return true;
  return RegExp(r'\+\s*[0-9]+(?:\.[0-9]+)?\s*-\s*[0-9]+(?:\.[0-9]+)?')
      .hasMatch(number);
}

/// Converts the PDG display spelling of a complex value to LaTeX.
///
/// Examples:
/// - `(445 ± 25)- i(278 +22-18)` -> `(445 \pm 25)- i(278^{+22}_{-18})`
/// - `(400--1200)-i(300--500)` -> en dashes in math mode
/// - `5.3 +0.9-0.7` -> `5.3^{+0.9}_{-0.7}`
String displayNumberLatex(String number) {
  var text = number
      .replaceAll('±', r'\pm ')
      .replaceAllMapped(RegExp(r'-\s*i\s*'), (match) => r' - i\,')
      .replaceAllMapped(
        RegExp(r'\+\s*([0-9]+(?:\.[0-9]+)?)\s*-\s*([0-9]+(?:\.[0-9]+)?)'),
        (match) => '\\;{}^{+${match.group(1)}}_{-${match.group(2)}}',
      )
      .replaceAllMapped(
        RegExp(r'([0-9.)])\s*[Ee]([+-]?[0-9]+)'),
        (match) => '${match.group(1)}\\times 10^{${match.group(2)}}',
      )
      .replaceAll('×10', r'\times 10')
      .replaceAll('%', r'\%');
  const superscript = {
    '⁰': '0',
    '¹': '1',
    '²': '2',
    '³': '3',
    '⁴': '4',
    '⁵': '5',
    '⁶': '6',
    '⁷': '7',
    '⁸': '8',
    '⁹': '9',
    '⁻': '-',
    '⁺': '+',
  };
  text = text.replaceAllMapped(
    RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+'),
    (match) =>
        '^{${match.group(0)!.split('').map((c) => superscript[c] ?? c).join()}}',
  );
  text = text.replaceAll(RegExp(r' +'), ' ');
  text = text.replaceAll(RegExp(r'\s+\\;'), r'\;');
  text = text.replaceAll(RegExp(r'\s+\^\{'), '^{');
  return text.trim();
}
