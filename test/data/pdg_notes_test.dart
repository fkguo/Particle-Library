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

  test(
    'citations missing from the official table have a patch reference',
    () async {
      final reference = await PdgNotes.referenceFor('DU 2018A');
      expect(reference, isNotNull);
      expect(reference!.title, isNotNull);
      expect(reference.title, isNotEmpty);
      expect(reference.year, isNotNull);
    },
  );

  test('a patch citation knows which entries cite it', () async {
    final entries = await PdgNotes.entriesForCitation('DU 2018A');
    expect(entries, contains('M252'));
  });

  test('related reviews for a particle come from the patch', () async {
    final files = await PdgNotes.reviewFilesFor('S010');
    expect(files, hasLength(3));
    expect(files, contains('rpp2026-rev-rare-kaon-decays.pdf'));
    expect(files, contains('rpp2026-rev-charged-kaon-mass.pdf'));
    expect(files, contains('rpp2026-rev-dalitz-params-k3pi-decays.pdf'));
  });

  test('identifiers without notes return null', () async {
    expect(await PdgNotes.forPdgid('NOT-A-PDGID'), isNull);
  });
}
