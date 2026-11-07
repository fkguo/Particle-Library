import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/app/update_checker.dart';
import 'package:pdgapp/domain/labels.dart';

void main() {
  group('the page the update dialog opens', () {
    test('only https addresses with a host are offered', () {
      expect(
        isSafeUpdateUrl('https://github.com/fkguo/Particle-Library'),
        isTrue,
      );
      expect(
        isSafeUpdateUrl('http://github.com/fkguo/Particle-Library'),
        isFalse,
      );
      expect(isSafeUpdateUrl('javascript:alert(1)'), isFalse);
      expect(isSafeUpdateUrl('file:///etc/passwd'), isFalse);
      expect(isSafeUpdateUrl('https:///nohost'), isFalse);
      expect(isSafeUpdateUrl('not a url'), isFalse);
    });

    Future<void> openDialog(WidgetTester tester, String url) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateAvailableDialog(
                context,
                const AppStrings(TextLang.en),
                UpdateInfo(version: '9.9.9', url: url, notes: 'Notes here'),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
    }

    testWidgets('the host is shown and the button works for https', (
      tester,
    ) async {
      await openDialog(tester, 'https://example.org/releases/9.9.9');
      expect(find.textContaining('example.org'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('the open button is disabled for a plain-http address', (
      tester,
    ) async {
      await openDialog(tester, 'http://example.org/releases/9.9.9');
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'the macOS update button asks Sparkle instead of opening GitHub',
      (tester) async {
        final calls = <String>[];
        const channel = MethodChannel('pdg.update');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await openDialog(tester, 'https://example.org/releases/9.9.9');
        expect(find.text('Update now'), findsOneWidget);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(calls, ['checkForUpdates']);
      },
      skip: !Platform.isMacOS,
    );
  });
}
