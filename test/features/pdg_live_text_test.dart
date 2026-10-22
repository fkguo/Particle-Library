import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/common/pdg_live_text.dart';

void main() {
  testWidgets('pdgLive math is typeset and citation labels become links', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PdgLiveText(
            r'There is ${{\mathit B}}$ evidence ( DU 2018A ).',
            citations: {'DU 2018A': PdgCitation(localId: 7, inspireRecid: 42)},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final links = <String>[];
    selectable.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null && span.text != null) {
        links.add(span.text!);
      }
      return true;
    });
    expect(links, contains('DU 2018A'));
  });

  test('the mit font switch becomes the plain letter', () {
    expect(normalizePdgLiveMath(r'-{\mit i}(102)'), '-i(102)');
    expect(normalizePdgLiveMath(r'\mit i'), 'i');
  });

  testWidgets('the M252 rename body is typeset, not left as source', (
    tester,
  ) async {
    const body = r'{{\mathit D}_{{{0}}}^{*}{(2400)}}';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: PdgLiveText('was \$$body\$')),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(body), findsNothing);
  });
}
