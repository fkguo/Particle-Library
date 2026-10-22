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
    },
  );

  test('identifiers without notes return null', () async {
    expect(await PdgNotes.forPdgid('NOT-A-PDGID'), isNull);
  });
}
