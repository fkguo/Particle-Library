import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_scope.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/app/settings_controller.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/pdg_repository.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/features/reference/inspire_search_field.dart';
import 'package:pdgapp/search/search_service.dart';
import 'package:pdgapp/user/user_store.dart';

void main() {
  late DirectSqlExecutor executor;
  late AppServices services;
  late Directory tempDir;

  setUpAll(() async {
    final snapshot = File('assets/pdgall-2026.0.sqlite');
    if (!snapshot.existsSync()) {
      fail('Snapshot asset missing; this suite needs the real pdgall file.');
    }
    executor = await DirectSqlExecutor.open(snapshot.path);
    final db = await PdgDatabase.open(
      executor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
    tempDir = await Directory.systemTemp.createTemp('pdgapp-inspire-field-');
    final store = await UserStore.open(
      overridePath: '${tempDir.path}/user.json',
    );
    services = AppServices(
      database: db,
      repository: PdgRepository(db),
      search: SearchService(db),
      userStore: store,
      settings: SettingsController(store, systemLocale: const Locale('en')),
      snapshotHash: SnapshotContract.expectedSha256,
      snapshotPath: snapshot.path,
      copiedFromBundle: true,
    );
  });

  tearDownAll(() async {
    await executor.dispose();
    await tempDir.delete(recursive: true);
  });

  testWidgets('inline hint completes with Tab and the menu selects a query', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    var searches = 0;
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(
          services: services,
          child: Scaffold(
            body: InspireSearchField(
              controller: controller,
              focusNode: focus,
              hintText: 'hint',
              searchTooltip: 'search',
              history: () => ['Weinberg, Steven', 'muon'],
              onSearch: () => searches++,
              onClearHistory: () => cleared++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Wein');
    await tester.pump();
    expect(find.text('berg, Steven'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, 'Weinberg, Steven');

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('muon').last);
    await tester.pumpAndSettle();
    expect(controller.text, 'muon');
    expect(searches, 1);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear INSPIRE search history'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });
}
