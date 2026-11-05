import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_scope.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/app/settings_controller.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/pdg_repository.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/features/plot/plot_chart.dart';
import 'package:pdgapp/features/plot/plot_data.dart';
import 'package:pdgapp/search/search_service.dart';
import 'package:pdgapp/user/user_store.dart';

Summary _row(String edition, double value) => Summary({
  'id': edition.hashCode,
  'pdgid_id': 1,
  'pdgid': 'X',
  'edition': edition,
  'value_type': 'AC',
  'in_summary_table': true,
  'value': value,
  'error_positive': 0.1,
  'error_negative': 0.1,
  'unit_text': 'MeV',
  'display_value_text': '$value',
  'display_power_of_ten': 0,
  'display_in_percent': false,
});

void main() {
  late DirectSqlExecutor executor;
  late PdgDatabase db;
  late UserStore store;
  late Directory tempDir;
  late AppServices services;

  setUpAll(() async {
    final snapshot = File('assets/pdgall-2026.0.sqlite');
    if (!snapshot.existsSync()) {
      fail('Snapshot asset missing; chart tests need the real pdgall file.');
    }
    executor = await DirectSqlExecutor.open(snapshot.path);
    db = await PdgDatabase.open(
      executor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
    tempDir = await Directory.systemTemp.createTemp('pdgapp-plot-chart-');
    store = await UserStore.open(overridePath: '${tempDir.path}/user.json');
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

  testWidgets('trend value list is newest first', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = buildEditionTrend([
      _row('2022', 1),
      _row('2024', 2),
      _row('2026', 3),
    ], label: 'X');
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: TrendDialog(data: data, title: 'X'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final newest = tester.getTopLeft(find.text('PDG 2026')).dy;
    final middle = tester.getTopLeft(find.text('PDG 2024')).dy;
    final oldest = tester.getTopLeft(find.text('PDG 2022')).dy;
    expect(newest, lessThan(middle));
    expect(middle, lessThan(oldest));
  });

  testWidgets('tapping the chart selects a year and tapping again clears it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final data = buildEditionTrend([
      _row('2022', 1),
      _row('2024', 2),
      _row('2026', 3),
    ], label: 'X');
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 300,
                child: PlotChart(data: data, title: 'X'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PlotChart));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PlotChart),
        matching: find.text('PDG 2024'),
      ),
      findsOneWidget,
    );

    // Tapping outside the chart clears the selected edition.
    final chartBottom = tester.getBottomLeft(find.byType(PlotChart)).dy;
    await tester.tapAt(Offset(400, chartBottom + 40));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PlotChart),
        matching: find.text('PDG 2024'),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(PlotChart));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PlotChart),
        matching: find.text('PDG 2024'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(PlotChart));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PlotChart),
        matching: find.text('PDG 2024'),
      ),
      findsNothing,
    );
  });
}
