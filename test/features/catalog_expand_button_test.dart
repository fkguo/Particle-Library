import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/catalog/catalog_expand_button.dart';

void main() {
  testWidgets('expand button has a 48dp target and exposes its state', (
    tester,
  ) async {
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

    final semantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(CatalogExpandButton),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.expanded != null,
        ),
      ),
    );
    expect(semantics.properties.expanded, isFalse);
    expect(tester.getSize(find.byType(IconButton)).height, 48);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('expanded state is visible to accessibility services', (
    tester,
  ) async {
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
    final semantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(CatalogExpandButton),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.expanded != null,
        ),
      ),
    );
    expect(semantics.properties.expanded, isTrue);
  });
}
