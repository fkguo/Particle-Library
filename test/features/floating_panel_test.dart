import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/common/floating_panel.dart';

void main() {
  testWidgets('a floating panel can be moved, resized and closed', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingPanel(
                title: 'PDG lookup',
                initialRect: const Rect.fromLTWH(100, 100, 400, 300),
                onClose: () => closed = true,
                child: const Text('results'),
              ),
            ],
          ),
        ),
      ),
    );

    final before = tester.getRect(find.byType(FloatingPanel));
    await tester.drag(find.text('PDG lookup'), const Offset(50, 40));
    await tester.pump();
    final moved = tester.getRect(find.byType(FloatingPanel));
    expect(moved.left, greaterThan(before.left + 30));
    expect(moved.top, greaterThan(before.top + 20));

    await tester.drag(find.byIcon(Icons.open_in_full), const Offset(60, 50));
    await tester.pump();
    final resized = tester.getRect(find.byType(FloatingPanel));
    expect(resized.width, greaterThan(moved.width + 30));
    expect(resized.height, greaterThan(moved.height + 20));

    expect(find.text('results'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });
}
