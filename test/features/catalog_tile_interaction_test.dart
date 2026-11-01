import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/common/ui.dart';

void main() {
  testWidgets('a tappable MetaChip wins over the surrounding row InkWell', (
    tester,
  ) async {
    var rowTaps = 0;
    var chipTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InkWell(
            onTap: () => rowTaps++,
            child: MetaChip(
              '31 entries',
              icon: Icons.expand_more,
              onTap: () => chipTaps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('31 entries'));
    await tester.pump();
    expect(chipTaps, 1);
    expect(rowTaps, 0);
  });
}
