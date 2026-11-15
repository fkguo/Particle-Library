import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/data/pdg_notes.dart';
import 'package:pdgapp/features/common/description_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, PdgGroupHeader> headers;
  setUpAll(() async {
    headers = await PdgNotes.groupHeaders();
  });

  for (final node in const [
    'MXXX005',
    'MXXX020',
    'MXXX035',
    'MXXX040',
    'MXXX045',
    'MXXX046',
    'MXXX049',
    'MXXX025',
    'MXXX030',
    'MXXX050',
    'BXXX005',
    'BXXX010',
    'BXXX020',
    'BXXX025',
    'BXXX030',
    'BXXX035',
    'BXXX040',
    'BXXX043',
    'BXXX045',
    'BXXX012',
  ]) {
    testWidgets('PDG Live group $node renders', (tester) async {
      final header = headers[node];
      expect(header, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DescriptionText(header!.title),
                  if (header.content.isNotEmpty)
                    DescriptionText(header.content),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
