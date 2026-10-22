import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/data/pdg_notes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PdgNotes.resetCache);

  test(
    'the shipped notes database carries the M252 rename and summary',
    () async {
      final note = await PdgNotes.forPdgid('M252');
      expect(note, isNotNull);
      expect(note!.was, contains('2400'));
      expect(note.summary, contains('two poles'));
      // Every citation link from the pdgLive page is preserved with its recid.
      expect(
        note.citations.keys,
        containsAll(['AAIJ 2015Y', 'DU 2018A', 'DU 2021']),
      );
      expect(note.citations['DU 2018A'], isNotNull);
    },
  );

  test('citations missing from the official table have a patch reference', () async {
    final reference = await PdgNotes.referenceFor('DU 2018A');
    expect(reference, isNotNull);
    expect(reference!.title, isNotNull);
    expect(reference.title, isNotEmpty);
    expect(reference.year, isNotNull);
  });

  test('identifiers without notes return null', () async {
    expect(await PdgNotes.forPdgid('NOT-A-PDGID'), isNull);
  });
}
