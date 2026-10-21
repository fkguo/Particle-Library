import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/common/snack_bars.dart';

void main() {
  test('action snack bars are only created by the shared helper', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final normalizedPath = entity.path.replaceAll('\\', '/');
      final isHelper = normalizedPath.endsWith(
        'features/common/snack_bars.dart',
      );
      if (!isHelper && source.contains('SnackBarAction(')) {
        offenders.add('${entity.path}: raw SnackBarAction');
      }
      if (source.contains('showCloseIcon: true')) {
        offenders.add('${entity.path}: showCloseIcon: true');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Action snack bars must go through showUndoSnackBar or '
          'showActionSnackBar so they all auto-dismiss consistently.',
    );
  });

  testWidgets('undo snack bar is non-persistent and has no close icon', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await pumpHost(tester, messengerKey);

    showUndoSnackBar(
      messengerKey.currentState!,
      message: 'Note deleted',
      undoLabel: 'Undo',
      onUndo: () {},
    );
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.persist, isFalse);
    expect(snackBar.showCloseIcon, isFalse);
    expect(snackBar.duration, actionSnackBarDuration);
    expect(find.text('Note deleted'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('undo snack bar dismisses itself after the shared duration', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await pumpHost(tester, messengerKey);

    showUndoSnackBar(
      messengerKey.currentState!,
      message: 'Note deleted',
      undoLabel: 'Undo',
      onUndo: () {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsOneWidget);

    await tester.pump(actionSnackBarDuration);
    await tester.pumpAndSettle();
    expect(find.text('Note deleted'), findsNothing);
  });

  testWidgets('undo action runs and dismisses the bar', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await pumpHost(tester, messengerKey);
    var undone = false;

    showUndoSnackBar(
      messengerKey.currentState!,
      message: 'Note deleted',
      undoLabel: 'Undo',
      onUndo: () => undone = true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('Note deleted'), findsNothing);
  });

  testWidgets('a new undo bar replaces the previous one', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await pumpHost(tester, messengerKey);

    showUndoSnackBar(
      messengerKey.currentState!,
      message: 'First deleted',
      undoLabel: 'Undo',
      onUndo: () {},
    );
    await tester.pumpAndSettle();
    showUndoSnackBar(
      messengerKey.currentState!,
      message: 'Second deleted',
      undoLabel: 'Undo',
      onUndo: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('First deleted'), findsNothing);
    expect(find.text('Second deleted'), findsOneWidget);
  });
}

Future<void> pumpHost(
  WidgetTester tester,
  GlobalKey<ScaffoldMessengerState> messengerKey,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      scaffoldMessengerKey: messengerKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}
