import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/domain/quantum_numbers.dart';
import 'package:pdgapp/features/common/description_text.dart';

void main() {
  test('description math keeps parity pairs but converts charge signs', () {
    expect(normalizeDescriptionMath(r'J^{PC} = 0^{-+}'), r'J^{PC} = 0^{-+}');
    expect(normalizeDescriptionMath(r'J^{PC} = 1^{+-}'), r'J^{PC} = 1^{+-}');
    expect(normalizeDescriptionMath(r'W^{+-}'), r'W^{\pm}');
  });

  testWidgets('the compact quantum line is typeset without ±/∓', (
    tester,
  ) async {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '1',
      g: '-',
      j: '0',
      p: '-',
      c: '+',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DescriptionText(quantum.latex, semanticsLabel: quantum.plain),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);
    // The parity pair itself is checked at the LaTeX-conversion level in
    // test/domain/text_fidelity_test.dart; this widget test only proves the
    // generated line goes through DescriptionText's math path.
  });

  testWidgets('the catalog quantum line wraps instead of truncating', (
    tester,
  ) async {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '0,1',
      j: '1',
      p: '-',
      c: '-',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: DescriptionText(
              quantum.latex,
              semanticsLabel: quantum.plain,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((widget) => widget.textSpan != null);
    expect(richTexts, isNotEmpty);
    expect(richTexts.first.maxLines, isNull);
    expect(find.byType(Math), findsNWidgets(quantum.tokens.length));
  });

  testWidgets('math-bearing rows survive a long scrollable list', (
    tester,
  ) async {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '1',
      g: '-',
      j: '0',
      p: '-',
      c: '+',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView.builder(
            itemCount: 60,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Row $index'),
                  DescriptionText(quantum.latex, semanticsLabel: quantum.plain),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DescriptionText), findsWidgets);
  });
}
