import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reviews/review_search_shortcuts.dart';

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Widget _host({
  required bool isMac,
  required bool searchOpen,
  required List<String> calls,
}) {
  return MaterialApp(
    home: ReviewSearchShortcuts(
      isMac: isMac,
      searchOpen: searchOpen,
      onFind: () => calls.add('find'),
      onNext: () => calls.add('next'),
      onPrevious: () => calls.add('previous'),
      onClose: () => calls.add('close'),
      child: const Scaffold(body: SizedBox.expand()),
    ),
  );
}

void main() {
  testWidgets('PDF search shortcuts work with Command on macOS', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(_host(isMac: true, searchOpen: true, calls: calls));
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyF, meta: true);
    await _press(tester, LogicalKeyboardKey.keyG, meta: true);
    await _press(tester, LogicalKeyboardKey.keyG, meta: true, shift: true);
    await _press(tester, LogicalKeyboardKey.f3);
    await _press(tester, LogicalKeyboardKey.f3, shift: true);
    await _press(tester, LogicalKeyboardKey.escape);

    expect(calls, ['find', 'next', 'previous', 'next', 'previous', 'close']);
  });

  testWidgets('PDF search shortcuts work with Control off macOS', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _host(isMac: false, searchOpen: true, calls: calls),
    );
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyF, control: true);
    await _press(tester, LogicalKeyboardKey.keyG, control: true);
    await _press(tester, LogicalKeyboardKey.keyG, control: true, shift: true);

    expect(calls, ['find', 'next', 'previous']);
  });

  testWidgets('Escape is only intercepted while search is open', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _host(isMac: true, searchOpen: false, calls: calls),
    );
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.escape);
    expect(calls, isEmpty);

    await _press(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(calls, ['find']);
  });
}
