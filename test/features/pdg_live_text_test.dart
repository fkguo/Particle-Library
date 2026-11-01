import 'package:flutter/gestures.dart';
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

  testWidgets('a summary review title becomes a tappable link', (tester) async {
    var tapped = false;
    const title = 'Spectroscopy of Light Meson Resonances';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PdgLiveText(
            'See the review on "$title".',
            links: {title: PdgLink(label: title, onTap: () => tapped = true)},
          ),
        ),
      ),
    );
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    TapGestureRecognizer? recognizer;
    selectable.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text == title) {
        recognizer = span.recognizer as TapGestureRecognizer?;
      }
      return true;
    });
    expect(recognizer, isNotNull);
    recognizer!.onTap!();
    expect(tapped, isTrue);
  });

  testWidgets('a See also math fragment becomes a tappable link', (
    tester,
  ) async {
    const body = r'{{\mathit \pi}_{{{1}}}{(1600)}}';
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PdgLiveText(
            'The state is \$$body\$. See also \$$body\$.',
            mathLinks: {
              body: PdgMathLink(
                label: 'pi_1(1600)',
                onTap: () => tapped = true,
              ),
            },
          ),
        ),
      ),
    );
    expect(find.byType(Math), findsNWidgets(2));
    await tester.tap(find.byType(Math).first);
    expect(tapped, isFalse);
    await tester.tap(find.byType(Math).last);
    expect(tapped, isTrue);
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
