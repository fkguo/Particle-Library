import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/catalog/catalog_expand_button.dart';

void main() {
  testWidgets(
    'expand button has a 48dp target and an actionable expanded node',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CatalogExpandButton(
              expanded: false,
              tooltip: 'Show more',
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      final data = tester
          .getSemantics(find.byType(CatalogExpandButton))
          .getSemanticsData();
      expect(data.label, 'Show more');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isExpanded.name, 'isFalse');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(find.byType(IconButton)).height, 48);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(taps, 1);
    },
  );

  testWidgets('the actionable node reports the expanded state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CatalogExpandButton(
            expanded: true,
            tooltip: 'Show less',
            onPressed: () {},
          ),
        ),
      ),
    );
    final data = tester
        .getSemantics(find.byType(CatalogExpandButton))
        .getSemanticsData();
    expect(data.label, 'Show less');
    expect(data.flagsCollection.isExpanded.name, 'isTrue');
  });
}
