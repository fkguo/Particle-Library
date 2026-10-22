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
  group('FloatingPanelHost.dismiss', () {
    Future<OverlayState> pumpOverlay(WidgetTester tester) async {
      final key = GlobalKey<OverlayState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Overlay(
            key: key,
            initialEntries: [OverlayEntry(builder: (_) => const SizedBox())],
          ),
        ),
      );
      return key.currentState!;
    }

    OverlayEntry panelEntry() => OverlayEntry(
      builder: (_) => const Positioned(left: 0, top: 0, child: Text('panel')),
    );

    testWidgets('removes a live entry and forgets it', (tester) async {
      final overlay = await pumpOverlay(tester);
      final entry = panelEntry();
      FloatingPanelHost.register(entry, overlay);
      overlay.insert(entry);
      await tester.pump();
      expect(find.text('panel'), findsOneWidget);

      FloatingPanelHost.dismiss(entry);
      await tester.pump();
      expect(find.text('panel'), findsNothing);

      // A forgotten entry must not come back when dialogs hand control back.
      FloatingPanelHost.resumeAll();
      await tester.pump();
      expect(find.text('panel'), findsNothing);
    });

    testWidgets('an owner can dismiss an entry closeAll already removed', (
      tester,
    ) async {
      final overlay = await pumpOverlay(tester);
      final entry = panelEntry();
      FloatingPanelHost.register(entry, overlay);
      overlay.insert(entry);
      await tester.pump();

      // "Save and open" from a capture dialog closes every panel behind the
      // owning editor's back; the editor later disposes and dismisses its
      // stale handle.
      FloatingPanelHost.closeAll();
      await tester.pump();
      expect(find.text('panel'), findsNothing);

      expect(() => FloatingPanelHost.dismiss(entry), returnsNormally);
    });

    testWidgets('an owner can dismiss an entry that is suspended', (
      tester,
    ) async {
      final overlay = await pumpOverlay(tester);
      final entry = panelEntry();
      FloatingPanelHost.register(entry, overlay);
      overlay.insert(entry);
      await tester.pump();

      FloatingPanelHost.suspendAll();
      await tester.pump();
      expect(() => FloatingPanelHost.dismiss(entry), returnsNormally);

      FloatingPanelHost.resumeAll();
      await tester.pump();
      expect(find.text('panel'), findsNothing);
    });
  });
}
