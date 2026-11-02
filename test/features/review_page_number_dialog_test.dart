import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reviews/page_number_dialog.dart';

class _DialogHost extends StatefulWidget {
  const _DialogHost();

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  int? result;

  Future<void> _open() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => const PageNumberDialog(
        initialPage: 3,
        title: 'Page',
        cancelLabel: 'Cancel',
        goLabel: 'Go',
      ),
    );
    if (mounted) setState(() => result = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(onPressed: _open, child: const Text('open')),
          Text(result == null ? 'none' : 'result: $result'),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('page dialog returns the entered page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _DialogHost()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('result: 7'), findsOneWidget);
  });

  testWidgets('controller is alive while the dialog animates out', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _DialogHost()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller;
    expect(controller, isNotNull);

    await tester.tap(find.text('Cancel'));
    // The dialog route is still reversing here; the text field may still read
    // the controller. Disposing it as soon as showDialog returns is too early.
    await tester.pump();
    expect(controller!.text, '3');

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
