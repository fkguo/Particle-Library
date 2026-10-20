import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/notes/note_evidence.dart';
import 'package:pdgapp/notes/notes_models.dart';

void main() {
  NoteRecord note({
    required Map<String, Object?> context,
    String kind = NoteTargetKinds.measurement,
    String key = 'S008EPL:42',
    NoteAnchorStatus status = NoteAnchorStatus.exact,
  }) {
    return NoteRecord(
      id: 'note-1',
      uuid: 'uuid-1',
      title: 'chi_c1 mass',
      bodyMarkdown: 'body',
      bodyPlain: 'body',
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 20),
      revision: 1,
      anchors: [
        NoteAnchor(
          id: 'a1',
          noteId: 'note-1',
          targetKind: kind,
          targetKey: key,
          snapshotHash: 'hash',
          targetLabel: 'chi_c1(3872) mass',
          status: status,
          context: context,
          createdAt: DateTime.utc(2026, 10, 20),
        ),
      ],
    );
  }

  Map<String, Object?> measurementContext({String value = '3871.64'}) => {
    'ctxVersion': 1,
    'kind': 'measurement',
    'measurementId': 42,
    'pdgid': 'S008EPL',
    'quantityLabel': 'chi_c1(3872) mass',
    'value': value,
    'errPlus': '0.06',
    'errMinus': '0.06',
    'unit': 'MeV',
    'edition': '2026',
    'valueText': '$value ± 0.06 MeV',
  };

  test('captured measurement is compared with the current PDG row', () async {
    final rows = await buildNoteEvidence(
      [note(context: measurementContext())],
      resolver: _FakeResolver(currentValue: '3871.64'),
      currentEdition: '2026',
    );
    expect(rows, hasLength(1));
    expect(rows.single.type, NoteEvidenceType.measurement);
    expect(rows.single.status, NoteEvidenceStatus.current);
    expect(rows.single.capturedValue, '3871.64 ± 0.06 MeV');
    expect(rows.single.currentValue, '3871.64 ± 0.06 MeV');
  });

  test(
    'changed values are marked and missing current rows are explicit',
    () async {
      final changed = await buildNoteEvidence(
        [note(context: measurementContext())],
        resolver: _FakeResolver(currentValue: '3872.00'),
        currentEdition: '2026',
      );
      expect(changed.single.status, NoteEvidenceStatus.changed);

      final missing = await buildNoteEvidence(
        [note(context: measurementContext())],
        resolver: _FakeResolver(currentValue: null),
        currentEdition: '2026',
      );
      expect(missing.single.status, NoteEvidenceStatus.missing);
    },
  );

  test(
    'old notes without structured context are uncompared, never guessed',
    () async {
      final rows = await buildNoteEvidence(
        [
          note(context: {'measurementId': 42, 'pdgid': 'S008EPL'}),
        ],
        resolver: _FakeResolver(currentValue: '3871.64'),
        currentEdition: '2026',
      );
      expect(rows.single.captured, isNull);
      expect(rows.single.status, NoteEvidenceStatus.uncompared);
      expect(rows.single.capturedValue, '—');
      expect(rows.single.currentValue, contains('3871.64'));
    },
  );

  test('different units are not silently compared', () async {
    final rows = await buildNoteEvidence(
      [note(context: measurementContext())],
      resolver: _FakeResolver(currentValue: '3871.64', unit: 'GeV'),
      currentEdition: '2026',
    );
    expect(rows.single.status, NoteEvidenceStatus.uncompared);
  });

  test('small magnitudes use relative tolerance', () async {
    final rows = await buildNoteEvidence(
      [note(context: measurementContext(value: '1e-25')..['unit'] = 's')],
      resolver: _FakeResolver(currentValue: '2e-25', unit: 's'),
      currentEdition: '2026',
    );
    expect(rows.single.status, NoteEvidenceStatus.changed);
  });

  test('fuzzy anchors stay fuzzy even when the current row resolves', () async {
    final rows = await buildNoteEvidence(
      [note(context: measurementContext(), status: NoteAnchorStatus.fuzzy)],
      resolver: _FakeResolver(currentValue: '3871.64'),
      currentEdition: '2026',
    );
    expect(rows.single.status, NoteEvidenceStatus.fuzzy);
  });
}

class _FakeResolver implements NoteEvidenceResolver {
  _FakeResolver({required this.currentValue, this.unit = 'MeV'});

  final String? currentValue;
  final String unit;

  @override
  Future<CurrentEvidence?> resolveMeasurement(
    String pdgid,
    int measurementId,
  ) async => _value();

  @override
  Future<CurrentEvidence?> resolveSummary(CapturedEvidence captured) async =>
      _value();

  CurrentEvidence? _value() {
    final value = currentValue;
    if (value == null) return null;
    return CurrentEvidence(
      value: value,
      errPlus: '0.06',
      errMinus: '0.06',
      unit: unit,
      edition: '2026',
      limitType: null,
      valueText: '$value ± 0.06 $unit',
    );
  }
}
