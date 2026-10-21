import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../domain/display.dart';
import 'ui.dart';

class DisplayValueView extends StatelessWidget {
  const DisplayValueView(
    this.quantity, {
    super.key,
    this.fontSize = 24,
    this.showLimitBadge = false,
    this.color,
  });

  final DisplayQuantity quantity;
  final double fontSize;
  final bool showLimitBadge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.maybeOf(context)?.strings;
    final base = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      color: color ?? palette.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (!quantity.hasNumericValue &&
        quantity.rawValueText.isEmpty &&
        quantity.text == '—') {
      return Text('—', style: base?.copyWith(color: palette.textSecondary));
    }
    final number = quantity.numberText;
    final mathNumber = displayNumberNeedsMath(number);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 5,
      runSpacing: 2,
      children: [
        if (mathNumber)
          Semantics(
            label: quantity.text,
            child: ExcludeSemantics(
              child: Math.tex(
                displayNumberLatex(number),
                mathStyle: MathStyle.text,
                textStyle: base,
                onErrorFallback: (_) => SelectableText(number, style: base),
              ),
            ),
          )
        else
          SelectableText(number, style: base),
        if (quantity.unitText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              prettyUnit(quantity.unitText),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
        if (showLimitBadge && (quantity.isLimit || quantity.isRange))
          MetaChip(
            quantity.isRange
                ? (strings?.limitRange ?? 'Range/excluded range')
                : (quantity.limitType == 'U'
                      ? (strings?.limitUpper ?? 'Upper limit')
                      : (strings?.limitLower ?? 'Lower limit')),
            tone: BadgeTone.warning,
          ),
      ],
    );
  }
}

class SummaryValueLine extends StatelessWidget {
  const SummaryValueLine({
    super.key,
    required this.quantity,
    this.fontSize = 22,
  });

  final DisplayQuantity quantity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DisplayValueView(quantity, fontSize: fontSize),
        if (quantity.confidenceLevel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'CL ${formatConfidence(quantity.confidenceLevel!)}%',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
      ],
    );
  }
}
