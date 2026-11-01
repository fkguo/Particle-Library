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

  test('a review named in the summary becomes a related review', () async {
    final files = await PdgNotes.reviewFilesFor('M111');
    expect(files, contains('rpp2026-rev-light-mesons-spectroscopy.pdf'));
  });

  test('a see-also particle in the summary becomes a link target', () async {
    final links = await PdgNotes.seeAlsoFor('M111');
    expect(links, hasLength(1));
    expect(links.first.targetPdgid, 'M164');
    expect(links.first.label, 'pi_1(1600)');
    expect(links.first.math, contains(r'\pi'));
  });

  test('summary review shorthands resolve to the review article', () async {
    expect(
      await PdgNotes.reviewFilesFor('M191'),
      contains('rpp2026-rev-non-qqbar-mesons.pdf'),
    );
    expect(
      await PdgNotes.reviewFilesFor('S054'),
      contains('rpp2026-rev-searches-quark-lep-compositeness.pdf'),
    );
    expect(
      await PdgNotes.reviewFilesFor('S058'),
      contains('rpp2026-rev-quark-model.pdf'),
    );
    expect(
      await PdgNotes.reviewFilesFor('S077'),
      contains('rpp2026-rev-neutrino-mixing.pdf'),
    );
  });

  test(
    'historical Pc names resolve to the current pentaquark entries',
    () async {
      final b171 = await PdgNotes.seeAlsoFor('B171');
      expect(
        b171.any(
          (link) =>
              link.targetPdgid == 'B172' && (link.math ?? '').contains('4450'),
        ),
        isTrue,
      );
      final b172 = await PdgNotes.seeAlsoFor('B172');
      expect(
        b172.any(
          (link) =>
              link.targetPdgid == 'B171' && (link.math ?? '').contains('4380'),
        ),
        isTrue,
      );
    },
  );

  test('identifiers without notes return null', () async {
    expect(await PdgNotes.forPdgid('NOT-A-PDGID'), isNull);
  });
}
