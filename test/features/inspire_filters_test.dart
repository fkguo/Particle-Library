import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/features/reference/inspire_search_page.dart';

void main() {
  test('opposite filters replace each other', () {
    var active = <String>{};
    active = toggleInspireFilter(active, 'local');
    expect(active, {'local'});
    active = toggleInspireFilter(active, 'notLocal');
    expect(active, {'notLocal'});
    active = toggleInspireFilter(active, 'notLocal');
    expect(active, isEmpty);
  });

  test('published and preprint are exclusive but compose with other groups', () {
    var active = <String>{'local'};
    active = toggleInspireFilter(active, 'published');
    expect(active, {'local', 'published'});
    active = toggleInspireFilter(active, 'preprint');
    expect(active, {'local', 'preprint'});
    active = toggleInspireFilter(active, 'recent5');
    expect(active, {'local', 'preprint', 'recent5'});
  });

  test('zotero pair is exclusive', () {
    final active = toggleInspireFilter({'zotero'}, 'notZotero');
    expect(active, {'notZotero'});
  });

  test('toggling does not mutate the input set', () {
    final original = {'local'};
    final next = toggleInspireFilter(original, 'notLocal');
    expect(original, {'local'});
    expect(next, {'notLocal'});
  });
}
