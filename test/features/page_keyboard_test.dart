import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/app/navigation.dart';
import 'package:pdgapp/features/common/page.dart';

void main() {
  testWidgets('nested PageScaffold does not subtract keyboard inset twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final hub = NavigationHub();
    final controller = NavigationController(
      hub: hub,
      rootBuilder: (_) => const SizedBox.shrink(),
    );
    addTearDown(() {
      controller.dispose();
      hub.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          // Mimic AppShell's global top bar and bottom navigation.
          appBar: AppBar(toolbarHeight: 48),
          bottomNavigationBar: const SizedBox(height: 58),
          body: NavigationScope(
            controller: controller,
            child: Navigator(
              key: controller.navigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => PageScaffold(
                  title: const Text('Note'),
                  body: Column(
                    children: [
                      const Text('Header'),
                      Expanded(child: TextField(maxLines: null)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(PageScaffold),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.resizeToAvoidBottomInset, isFalse);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    // With one keyboard inset the editor still has a useful body; a second
    // subtraction collapses it to a sliver.
    expect(tester.getSize(field).height, greaterThan(150));
  });

  testWidgets('a landscape phone page body spans the full width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(952, 440);
    tester.view.devicePixelRatio = 1;
    // iPhone landscape: notch/corner safe area on the left and right.
    tester.view.padding = const FakeViewPadding(
      left: 62,
      right: 62,
      top: 0,
      bottom: 21,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const PageScaffold(
          maxWidth: double.infinity,
          title: Text('Wide'),
          body: SizedBox.expand(key: Key('page-body')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('page-body')));
    // No side gutter: the page body uses the full screen width.
    expect(rect.left, 0);
    expect(rect.width, 952);
  });
}
