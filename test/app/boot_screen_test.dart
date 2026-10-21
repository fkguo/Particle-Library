import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/app/boot_screen.dart';
import 'package:pdgapp/domain/labels.dart';

void main() {
  testWidgets('boot screen follows the saved language', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BootScreen(language: TextLang.en, onRetry: () {}),
      ),
    );
    expect(find.text('Opening the offline PDG data…'), findsOneWidget);
    expect(find.text('正在打开离线 PDG 数据…'), findsNothing);
  });
}
