import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../app/app_theme.dart';
import '../../domain/latex.dart';

/// Renders a mixed source string with inline typeset mathematics.
///
/// It understands three forms that occur in PDG data:
/// - `$...$` TeX, as used by reference titles;
/// - bare particle names such as `B_s^0`, `D_s()+-`, `K(S)0`;
/// - the snapshot’s TeX-ish text markup such as `D_{{s}}()+-` or `g**nu_{e}`.
///
/// Only recognised tokens are typeset. Unknown text stays literal, the raw
/// string is the semantics label, and pages always keep raw fields/copy paths.
class DescriptionText extends StatelessWidget {
  const DescriptionText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.selectable = false,
    this.citationIds = const <String, int>{},
    this.onCitationTap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;
  final Map<String, int> citationIds;
  final ValueChanged<int>? onCitationTap;

  static final RegExp _citationPattern = RegExp(
    r"\b[A-Z][A-Za-z0-9&.'’\-]*(?:\s+(?:AND|&|ET\s+AL\.?|[A-Z][A-Za-z0-9&.'’\-]*))*\s+(?:19|20)\d{2}[A-Z]?\b",
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base =
        (style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: style?.color ?? palette.textPrimary);
    final spans = <InlineSpan>[];
    for (final segment in segmentPdgText(text)) {
      final latex = segment.latex;
      if (latex != null) {
        spans.add(_mathSpan(latex, latex, base));
      } else {
        spans.addAll(_citationSpans(context, segment.text ?? '', base));
      }
    }
    // SelectableText reserves `maxLines` line boxes even for short text (it
    // reuses EditableText's fixed height), which left large empty gaps under
    // card titles. SelectionArea keeps selection without that reservation.
    final body = Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : overflow,
    );
    final rich = !selectable
        ? body
        : maxLines == null
        ? SelectableText.rich(TextSpan(children: spans), style: base)
        : SelectionArea(child: body);
    return Semantics(
      label: text,
      child: ExcludeSemantics(child: rich),
    );
  }

  List<InlineSpan> _citationSpans(
    BuildContext context,
    String text,
    TextStyle base,
  ) {
    if (citationIds.isEmpty || onCitationTap == null) {
      return [TextSpan(text: text)];
    }
    final result = <InlineSpan>[];
    var cursor = 0;
    for (final match in _citationPattern.allMatches(text)) {
      if (match.start > cursor) {
        result.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final label = match.group(0)!;
      final key = label.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
      final referenceId = citationIds[key];
      if (referenceId == null) {
        result.add(TextSpan(text: label));
      } else {
        final linkStyle = base.copyWith(
          color: context.palette.primary,
          decoration: TextDecoration.underline,
          decorationColor: context.palette.primary.withValues(alpha: 0.35),
        );
        result.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onCitationTap!(referenceId),
                child: Text(label, style: linkStyle),
              ),
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      result.add(TextSpan(text: text.substring(cursor)));
    }
    return result;
  }

  static InlineSpan _mathSpan(String latex, String fallback, TextStyle style) {
    final normalized = latex
        .replaceAll(RegExp(r'\^\{\s*\+\s*-\s*\}'), r'^{\pm}')
        .replaceAll(RegExp(r'\^\{\s*-\s*\+\s*\}'), r'^{\mp}');
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.5),
        child: Math.tex(
          normalized,
          mathStyle: MathStyle.text,
          // Do not inherit a heading's synthetic bold weight: many math fonts
          // have no bold Greek glyphs, so f_0/a_0 would become bold while
          // phi(1020) stayed regular. Keep all math spans on one weight; the
          // surrounding prose keeps its own weight.
          textStyle: style.copyWith(
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.normal,
          ),
          onErrorFallback: (_) => Text(fallback, style: style),
        ),
      ),
    );
  }
}
