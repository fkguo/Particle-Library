import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/domain/quantum_numbers.dart';
import 'package:pdgapp/features/common/description_text.dart';

void main() {
  testWidgets('the compact quantum line is typeset by DescriptionText', (
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
          body: DescriptionText(
            quantum.latex,
            maxLines: 1,
            semanticsLabel: quantum.plain,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);
  });
}
