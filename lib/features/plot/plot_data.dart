import '../../domain/display.dart';
import '../../domain/models.dart';

/// One numeric point in a plot.
class PlotPoint {
  const PlotPoint({
    required this.x,
    required this.xLabel,
    required this.y,
    required this.summary,
    this.errorPlus,
    this.errorMinus,
    this.current = false,
  });

  final double x;
  final String xLabel;
  final double y;
  final Summary summary;
  final double? errorPlus;
  final double? errorMinus;
  final bool current;
}

/// A named series; a trend can have one per `value_type`, and a multi-particle
/// comparison can have many.
class PlotSeries {
  const PlotSeries({
    required this.label,
    required this.unit,
    required this.points,
    this.valueType = '',
    this.skippedAmbiguous = 0,
    this.skippedLimits = 0,
    this.skippedMissing = 0,
    this.unitMismatch = false,
  });

  final String label;
  final String unit;
  final List<PlotPoint> points;

  /// PDG `value_type` (`AC`, `FC`, ...), used to label a selectable trend.
  final String valueType;
  final int skippedAmbiguous;
  final int skippedLimits;
  final int skippedMissing;
  final bool unitMismatch;
}

/// A chart-ready set of series plus the rows that could not be plotted.
class PlotData {
  const PlotData({
    required this.series,
    this.skippedAmbiguous = 0,
    this.skippedLimits = 0,
    this.skippedMissing = 0,
    this.unitMismatch = false,
  });

  final List<PlotSeries> series;
  final int skippedAmbiguous;
  final int skippedLimits;
  final int skippedMissing;
  final bool unitMismatch;

  bool get hasTrend => series.any((item) => item.points.length >= 2);

  List<PlotPoint> get points =>
      series.isEmpty ? const <PlotPoint>[] : series.first.points;

  /// View one of the available PDG value types as a standalone trend.
  PlotData selectSeries(int index) {
    final item = series[index];
    return PlotData(
      series: <PlotSeries>[item],
      skippedAmbiguous: item.skippedAmbiguous,
      skippedLimits: item.skippedLimits,
      skippedMissing: item.skippedMissing,
      unitMismatch: item.unitMismatch,
    );
  }
}

/// Builds a trend from the pdgdata history rows of one series.
///
/// PDG editions can publish both an `AC` (PDG Average) and an `FC` (PDG Fit)
/// value for the same quantity. Those are separate trends, not an ambiguous
/// single value: group by `value_type` first, then select one preferred row
/// within each group. Editions with limits, no numeric value, or multiple
/// candidates of the same type are still skipped.
PlotData buildEditionTrend(
  List<Summary> summaries, {
  required String label,
  String? currentEdition,
}) {
  final byEditionAndType = <String, Map<String, List<Summary>>>{};
  for (final row in summaries) {
    final edition = row.edition;
    if (edition == null || edition.isEmpty) continue;
    final type = row.valueType;
    (byEditionAndType[edition] ??= <String, List<Summary>>{})
        .putIfAbsent(type, () => <Summary>[])
        .add(row);
  }
  final editions = byEditionAndType.keys.toList()
    ..sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return ai.compareTo(bi);
      return a.compareTo(b);
    });

  final types = <String>{
    for (final byType in byEditionAndType.values) ...byType.keys,
  }.toList();
  const preferredOrder = <String>['AC', 'FC'];
  types.sort((a, b) {
    final ai = preferredOrder.indexOf(a);
    final bi = preferredOrder.indexOf(b);
    if (ai >= 0 || bi >= 0) {
      final av = ai < 0 ? preferredOrder.length : ai;
      final bv = bi < 0 ? preferredOrder.length : bi;
      final order = av.compareTo(bv);
      if (order != 0) return order;
    }
    return a.compareTo(b);
  });

  final series = <PlotSeries>[];
  var totalAmbiguous = 0;
  var totalLimits = 0;
  var totalMissing = 0;
  var anyUnitMismatch = false;

  for (final type in types) {
    final points = <PlotPoint>[];
    final units = <String>{};
    var skippedAmbiguous = 0;
    var skippedLimits = 0;
    var skippedMissing = 0;
    for (final edition in editions) {
      final rows = byEditionAndType[edition]?[type];
      if (rows == null || rows.isEmpty) continue;
      final selection = selectBestSummary(rows);
      final summary = selection.preferred;
      if (summary == null) {
        skippedAmbiguous++;
        continue;
      }
      if (summary.limitType != null) {
        skippedLimits++;
        continue;
      }
      final year = int.tryParse(edition);
      final value = summary.value;
      if (year == null || value == null || !value.isFinite) {
        skippedMissing++;
        continue;
      }
      final percent = summary.displayInPercent;
      final scale = percent ? 100.0 : 1.0;
      final plotValue = value * scale;
      final unit = percent ? '%' : summary.unitText.trim();
      if (unit.isNotEmpty) units.add(unit);
      final plus = summary.errorPositive;
      final minus = summary.errorNegative;
      points.add(
        PlotPoint(
          x: year.toDouble(),
          xLabel: edition,
          y: plotValue,
          summary: summary,
          errorPlus: plus != null && plus.isFinite && plus > 0
              ? plus * scale
              : null,
          errorMinus: minus != null && minus.isFinite && minus > 0
              ? minus * scale
              : null,
          current: edition == currentEdition,
        ),
      );
    }

    final unitMismatch = units.length > 1;
    if (unitMismatch) anyUnitMismatch = true;
    totalAmbiguous += skippedAmbiguous;
    totalLimits += skippedLimits;
    totalMissing += skippedMissing;
    if (points.isEmpty || unitMismatch) continue;
    final unit = units.length == 1 ? units.first : '';
    series.add(
      PlotSeries(
        label: label,
        unit: unit,
        points: List.unmodifiable(points),
        valueType: type,
        skippedAmbiguous: skippedAmbiguous,
        skippedLimits: skippedLimits,
        skippedMissing: skippedMissing,
        unitMismatch: unitMismatch,
      ),
    );
  }

  return PlotData(
    series: series,
    skippedAmbiguous: totalAmbiguous,
    skippedLimits: totalLimits,
    skippedMissing: totalMissing,
    unitMismatch: anyUnitMismatch,
  );
}
