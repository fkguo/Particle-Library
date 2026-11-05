import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../common/description_text.dart';
import '../common/display_value.dart';
import 'plot_data.dart';

class TrendChartButton extends StatelessWidget {
  const TrendChartButton({super.key, required this.data, required this.title});

  final PlotData data;
  final String title;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final enabled = data.hasTrend;
    return Tooltip(
      message: enabled
          ? strings.seriesTrendTitle
          : data.unitMismatch
          ? strings.seriesTrendUnitMismatch
          : strings.seriesTrendNoData,
      child: TextButton.icon(
        onPressed: enabled
            ? () => showTrendDialog(context, data: data, title: title)
            : null,
        icon: const Icon(Icons.show_chart, size: 18),
        label: Text(strings.seriesTrendChart),
      ),
    );
  }
}

Future<void> showTrendDialog(
  BuildContext context, {
  required PlotData data,
  required String title,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TrendDialog(data: data, title: title),
  );
}

class TrendDialog extends StatefulWidget {
  const TrendDialog({super.key, required this.data, required this.title});

  final PlotData data;
  final String title;

  @override
  State<TrendDialog> createState() => _TrendDialogState();
}

class _TrendDialogState extends State<TrendDialog> {
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.data.series.length; i++) {
      if (widget.data.series[i].points.length >= 2) {
        _selected = i;
        break;
      }
    }
  }

  String _seriesLabel(PlotSeries series, AppStrings strings) {
    final type = series.valueType.isEmpty
        ? strings.seriesTrendAllValues
        : valueTypeShortLabel(series.valueType, strings.lang);
    return '$type · ${series.points.length}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(820.0, math.max(360.0, screen.width - 64));
    final chartHeight = math.min(320.0, math.max(220.0, screen.height * 0.38));
    final data = widget.data.series.isEmpty
        ? widget.data
        : widget.data.selectSeries(_selected);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: math.max(320.0, screen.height * 0.86),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart, size: 20, color: palette.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DescriptionText(
                        widget.title,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  strings.seriesTrendSubtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: 10),
                if (widget.data.series.length > 1) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < widget.data.series.length; i++)
                        ChoiceChip(
                          label: Text(
                            _seriesLabel(widget.data.series[i], strings),
                          ),
                          selected: i == _selected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _selected = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (!data.hasTrend)
                  _NoTrend(data: data)
                else ...[
                  SizedBox(
                    height: chartHeight,
                    width: double.infinity,
                    child: PlotChart(
                      data: data,
                      title: strings.seriesTrendTitle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SkippedNotes(data: data),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: palette.divider),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final point in data.points)
                            _PointRow(point: point),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.seriesTrendClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoTrend extends StatelessWidget {
  const _NoTrend({required this.data});
  final PlotData data;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Text(
      data.unitMismatch
          ? strings.seriesTrendUnitMismatch
          : strings.seriesTrendNoData,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: palette.textSecondary),
    );
  }
}

class _SkippedNotes extends StatelessWidget {
  const _SkippedNotes({required this.data});
  final PlotData data;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final notes = <String>[
      if (data.skippedAmbiguous > 0)
        '${data.skippedAmbiguous} ${strings.seriesTrendAmbiguous}',
      if (data.skippedLimits > 0)
        '${data.skippedLimits} ${strings.seriesTrendLimits}',
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Text(
      notes.join(' · '),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: palette.textSecondary),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});
  final PlotPoint point;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final quantity = DisplayQuantity.fromSummary(point.summary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              'PDG ${point.xLabel}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: DisplayValueView(quantity, fontSize: 14)),
          if (point.current)
            Text(
              strings.seriesTrendCurrent,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: palette.accent),
            ),
        ],
      ),
    );
  }
}

class PlotChart extends StatefulWidget {
  const PlotChart({super.key, required this.data, required this.title});

  final PlotData data;
  final String title;

  @override
  State<PlotChart> createState() => _PlotChartState();
}

class _PlotChartState extends State<PlotChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    final unit = widget.data.series.isEmpty
        ? ''
        : prettyUnit(widget.data.series.first.unit);
    return Semantics(
      label:
          '${widget.title} · ${widget.data.points.length} ${strings.seriesTrendPoints}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                unit,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final frame = _frameFor(widget.data, size);
                return MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  onHover: (event) {
                    final next = frame.nearest(
                      widget.data.points,
                      event.localPosition,
                    );
                    if (next != _hovered && mounted) {
                      setState(() => _hovered = next);
                    }
                  },
                  onExit: (_) {
                    if (_hovered != null && mounted) {
                      setState(() => _hovered = null);
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PlotPainter(
                            data: widget.data,
                            line: palette.primary,
                            current: palette.accent,
                            grid: palette.divider,
                            text: palette.textSecondary,
                            strong: palette.textPrimary,
                            unit: '',
                            textScaler: MediaQuery.textScalerOf(context),
                            xLabel: strings.seriesTrendXAxis,
                            hoveredIndex: _hovered,
                          ),
                        ),
                      ),
                      if (_hovered != null)
                        _HoverCard(
                          data: widget.data,
                          index: _hovered!,
                          frame: frame,
                          size: size,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({
    required this.data,
    required this.index,
    required this.frame,
    required this.size,
  });

  final PlotData data;
  final int index;
  final _PlotFrame frame;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final point = data.points[index];
    final quantity = DisplayQuantity.fromSummary(point.summary);
    final anchor = frame.point(point);
    const cardWidth = 238.0;
    final left = (anchor.dx + 12)
        .clamp(4.0, math.max(4.0, size.width - cardWidth - 4))
        .toDouble();
    final top = (anchor.dy - 76)
        .clamp(4.0, math.max(4.0, size.height - 96))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: IgnorePointer(
        child: Material(
          elevation: 6,
          color: palette.surface,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'PDG ${point.xLabel}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (point.current) ...[
                      const SizedBox(width: 6),
                      Text(
                        strings.seriesTrendCurrent,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: palette.accent),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                DisplayValueView(quantity, fontSize: 13),
                if ((point.summary.comment ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    point.summary.comment ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlotFrame {
  const _PlotFrame({
    required this.plot,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final Rect plot;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  Offset point(PlotPoint point) => Offset(
    plot.left + (point.x - minX) / (maxX - minX) * plot.width,
    plot.top + (maxY - point.y) / (maxY - minY) * plot.height,
  );

  int? nearest(List<PlotPoint> points, Offset local) {
    var best = -1;
    var bestDistance = 22.0;
    for (var i = 0; i < points.length; i++) {
      final offset = point(points[i]);
      final distance = (offset - local).distance;
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best < 0 ? null : best;
  }
}

_PlotFrame _frameFor(PlotData data, Size size) {
  final points = data.points;
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y - (point.errorMinus ?? 0));
    maxY = math.max(maxY, point.y + (point.errorPlus ?? 0));
  }
  if ((maxX - minX).abs() < 0.5) {
    minX -= 0.5;
    maxX += 0.5;
  }
  final spanY = maxY - minY;
  final padY = spanY == 0 ? math.max(1.0, maxY.abs() * 0.01) : spanY * 0.12;
  minY -= padY;
  maxY += padY;
  const left = 58.0;
  const top = 14.0;
  const right = 12.0;
  const bottom = 36.0;
  final plot = Rect.fromLTRB(
    left,
    top,
    size.width - right,
    size.height - bottom,
  );
  return _PlotFrame(plot: plot, minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.data,
    required this.line,
    required this.current,
    required this.grid,
    required this.text,
    required this.strong,
    required this.unit,
    required this.textScaler,
    required this.xLabel,
    required this.hoveredIndex,
  });

  final PlotData data;
  final Color line;
  final Color current;
  final Color grid;
  final Color text;
  final Color strong;
  final String unit;
  final TextScaler textScaler;
  final String xLabel;
  final int? hoveredIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.series.isEmpty || data.points.isEmpty) return;
    final points = data.points;
    final frame = _frameFor(data, size);
    final plot = frame.plot;
    if (plot.width <= 10 || plot.height <= 10) return;
    final minX = frame.minX;
    final maxX = frame.maxX;
    final minY = frame.minY;
    final maxY = frame.maxY;

    double px(double x) => plot.left + (x - minX) / (maxX - minX) * plot.width;
    double py(double y) => plot.top + (maxY - y) / (maxY - minY) * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const yTicks = 4;
    for (var i = 0; i <= yTicks; i++) {
      final y = minY + (maxY - minY) * i / yTicks;
      final yy = py(y);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      final label = _axisText(_formatNumber(y));
      label.paint(canvas, Offset(4, yy - label.height / 2));
    }

    final labelIndices = <int>{};
    if (points.length <= 7) {
      labelIndices.addAll(List<int>.generate(points.length, (i) => i));
    } else {
      for (var i = 0; i <= 5; i++) {
        labelIndices.add((i * (points.length - 1) / 5).round());
      }
    }
    for (final i in labelIndices) {
      final point = points[i];
      final xx = px(point.x);
      canvas.drawLine(
        Offset(xx, plot.bottom),
        Offset(xx, plot.bottom + 4),
        gridPaint,
      );
      final label = _axisText(point.xLabel);
      label.paint(canvas, Offset(xx - label.width / 2, plot.bottom + 7));
    }
    final axisX = _axisText(xLabel);
    axisX.paint(
      canvas,
      Offset(plot.center.dx - axisX.width / 2, size.height - 14),
    );

    final axisPaint = Paint()
      ..color = text
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axisPaint);

    if (unit.isNotEmpty) {
      final unitText = _axisText(unit);
      unitText.paint(canvas, Offset(4, 0));
    }

    final sorted = List<PlotPoint>.from(points)
      ..sort((a, b) => a.x.compareTo(b.x));
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final point = sorted[i];
      final offset = Offset(px(point.x), py(point.y));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final hovered =
        hoveredIndex != null &&
            hoveredIndex! >= 0 &&
            hoveredIndex! < points.length
        ? points[hoveredIndex!]
        : null;
    if (hovered != null) {
      final hx = px(hovered.x);
      canvas.drawLine(
        Offset(hx, plot.top),
        Offset(hx, plot.bottom),
        Paint()
          ..color = line.withValues(alpha: 0.22)
          ..strokeWidth = 1,
      );
    }

    for (final point in sorted) {
      final x = px(point.x);
      final y = py(point.y);
      final cap = Paint()
        ..color = point.current ? current : line
        ..strokeWidth = 1.4;
      final plus = point.errorPlus;
      final minus = point.errorMinus;
      if (plus != null) {
        final yy = py(point.y + plus);
        canvas.drawLine(Offset(x, y), Offset(x, yy), cap);
        canvas.drawLine(Offset(x - 3, yy), Offset(x + 3, yy), cap);
      }
      if (minus != null) {
        final yy = py(point.y - minus);
        canvas.drawLine(Offset(x, y), Offset(x, yy), cap);
        canvas.drawLine(Offset(x - 3, yy), Offset(x + 3, yy), cap);
      }
      final pointPaint = Paint()
        ..color = point.current ? current : line
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), point.current ? 4.5 : 3.2, pointPaint);
      if (identical(point, hovered)) {
        canvas.drawCircle(
          Offset(x, y),
          8,
          Paint()
            ..color = current
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (point.current) {
        canvas.drawCircle(
          Offset(x, y),
          7,
          Paint()
            ..color = current.withValues(alpha: 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  TextPainter _axisText(String value) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: 10.5, color: text),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: 120);
    return painter;
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) => true;
}

String _formatNumber(double value) {
  if (value == 0) return '0';
  final abs = value.abs();
  if (abs >= 100000 || abs < 0.001) {
    return value.toStringAsExponential(2);
  }
  final text = value.toStringAsPrecision(4);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
