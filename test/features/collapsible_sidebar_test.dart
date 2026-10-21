import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/common/resize_handle.dart';

void main() {
  testWidgets('collapsible sidebar swaps between panel and rail', (
    tester,
  ) async {
    var expanded = true;
    var expansions = 0;

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              CollapsibleSidebar(
                expanded: expanded,
                width: 300,
                handleOnLeft: true,
                expandIcon: Icons.keyboard_double_arrow_left,
                railIcon: Icons.list_alt,
                tooltip: 'Inspector',
                railTooltip: 'Show inspector',
                onExpand: () => expansions++,
                onDrag: (_) {},
                child: const SizedBox.expand(key: Key('panel')),
              ),
            ],
          ),
        ),
      ),
    );

    await pump();
    expect(find.byKey(const Key('panel')), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsNothing);

    expanded = false;
    await pump();
    expect(find.byKey(const Key('panel')), findsNothing);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_double_arrow_left), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
    expect(expansions, 1);
  });
}
