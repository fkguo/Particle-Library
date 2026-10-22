import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/pdg_notes.dart';
import '../reference/reference_page.dart';

/// pdgLive uses the plain-TeX font switch `{\mit i}` for the imaginary unit.
/// flutter_math has no `\mit`, and math letters are italic already, so the
/// switch is reduced to the letter itself.
String normalizePdgLiveMath(String body) {
  var out = body.replaceAllMapped(
    RegExp(r'\{\s*\\mit\s+([A-Za-z])\s*\}'),
    (match) => match.group(1)!,
  );
  out = out.replaceAllMapped(
    RegExp(r'\\mit\s+([A-Za-z])'),
    (match) => match.group(1)!,
  );
  return out;
}

/// A citation found in a pdgLive note.
@immutable
class PdgCitation {
  const PdgCitation({this.localId, this.inspireRecid, this.reference});

  /// Local PDG reference id when the key exists in the snapshot.
  final int? localId;

  /// INSPIRE record linked from the pdgLive page.
  final int? inspireRecid;

  /// Bibliographic record from the patch when the key is not in the snapshot.
  final PdgNoteReference? reference;
}

/// Renders a pdgLive note: `$...$` LaTeX becomes typeset math, and citation
/// labels become links (local PDG reference first, INSPIRE otherwise).
class PdgLiveText extends StatelessWidget {
  const PdgLiveText(
    this.text, {
    super.key,
    this.style,
    this.citations = const <String, PdgCitation>{},
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final Map<String, PdgCitation> citations;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base =
        (style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: style?.color ?? palette.textPrimary);
    final spans = <InlineSpan>[];
    var index = 0;
    while (index < text.length) {
      final start = text.indexOf(r'$', index);
      if (start < 0) {
        spans.addAll(_plainSpans(context, text.substring(index), base));
        break;
      }
      if (start > index) {
        spans.addAll(_plainSpans(context, text.substring(index, start), base));
      }
      final end = text.indexOf(r'$', start + 1);
      if (end < 0) {
        spans.addAll(_plainSpans(context, text.substring(start), base));
        break;
      }
      final body = text.substring(start + 1, end);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Math.tex(
            normalizePdgLiveMath(body),
            mathStyle: MathStyle.text,
            textStyle: base,
            onErrorFallback: (_) => Text(
              body,
              style: base,
              // Fall back to the source when flutter_math cannot parse it.
            ),
          ),
        ),
      );
      index = end + 1;
    }
    final span = TextSpan(children: spans, style: base);
    return selectable
        ? SelectableText.rich(span, style: base)
        : Text.rich(span, style: base);
  }

  List<InlineSpan> _plainSpans(
    BuildContext context,
    String chunk,
    TextStyle base,
  ) {
    if (chunk.isEmpty) return const <InlineSpan>[];
    final palette = context.palette;
    final labels = citations.keys.where((label) => label.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final spans = <InlineSpan>[];
    var index = 0;
    while (index < chunk.length) {
      String? hit;
      for (final label in labels) {
        if (chunk.startsWith(label, index)) {
          hit = label;
          break;
        }
      }
      if (hit != null) {
        final citation = citations[hit]!;
        spans.add(
          TextSpan(
            text: hit,
            style: base.copyWith(
              color: palette.accent,
              decoration: TextDecoration.underline,
              decorationColor: palette.accent,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openCitation(context, citation),
          ),
        );
        index += hit.length;
        continue;
      }
      var next = chunk.length;
      for (final label in labels) {
        final found = chunk.indexOf(label, index + 1);
        if (found >= 0 && found < next) next = found;
      }
      if (next <= index) {
        next = index + 1;
      }
      spans.add(TextSpan(text: chunk.substring(index, next)));
      index = next;
    }
    return spans;
  }

  void _openCitation(BuildContext context, PdgCitation citation) {
    final local = citation.localId;
    if (local != null) {
      AppNav.openReference(context, local);
      return;
    }
    final reference = citation.reference;
    if (reference != null) {
      AppNav.push<void>(context, ReferencePage.patch(patch: reference));
      return;
    }
    final recid = citation.inspireRecid;
    if (recid == null) return;
    unawaited(
      launchUrl(
        Uri.parse('https://inspirehep.net/literature/$recid'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
