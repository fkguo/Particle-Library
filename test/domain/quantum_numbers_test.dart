import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/domain/quantum_numbers.dart';

Particle particle({
  int id = 1,
  String cc = 'P',
  double? charge,
  String? i,
  String? g,
  String? j,
  String? p,
  String? c,
}) {
  return Particle({
    'id': id,
    'pdgid_id': 1,
    'pdgid': 'X',
    'pdgitem_id': 1,
    'name': 'X',
    'cc_type': cc,
    'mcid': null,
    'charge': charge,
    'quantum_i': i,
    'quantum_g': g,
    'quantum_j': j,
    'quantum_p': p,
    'quantum_c': c,
  });
}

void main() {
  test('a complete J^PC block folds C into the spin token', () {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '0',
      g: '+',
      j: '2',
      p: '+',
      c: '+',
    );
    expect(quantum.latex, r'$J^{PC} = 2^{++}$ · $I = 0$ · $G = +$');
    expect(quantum.plain, 'J^PC = 2^++ · I = 0 · G = +');
    // C is already part of J^PC and must not be repeated.
    expect(quantum.tokens, hasLength(3));
  });

  test('P and C are folded into J^PC when both are known', () {
    final quantum = ParticleQuantumNumbers.fromValues(j: '1', p: '-', c: '+');
    expect(quantum.latex, r'$J^{PC} = 1^{-+}$');
    expect(quantum.plain, 'J^PC = 1^-+');
  });

  test('C without P stays separate instead of inventing J^C', () {
    final quantum = ParticleQuantumNumbers.fromValues(j: '1', c: '+');
    expect(quantum.latex, r'$J = 1$ · $C = +$');
    expect(quantum.plain, 'J = 1 · C = +');
  });

  test('isospin and G parity stand alone when J is absent', () {
    final quantum = ParticleQuantumNumbers.fromValues(i: '1/2', g: '-');
    expect(quantum.latex, r'$I = 1/2$ · $G = -$');
    expect(quantum.plain, 'I = 1/2 · G = -');
  });

  test('a comma-separated isospin is preserved', () {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '0,1',
      j: '1',
      p: '-',
      c: '-',
    );
    expect(quantum.plain, 'J^PC = 1^-- · I = 0,1');
  });

  test('NULL, empty and question-mark fields are not displayed', () {
    final quantum = ParticleQuantumNumbers.fromValues(
      i: '',
      g: '?',
      j: '? ',
      p: null,
      c: '',
    );
    expect(quantum.isEmpty, isTrue);
    expect(quantum.latex, isEmpty);
    expect(quantum.plain, isEmpty);
  });

  test(
    'representative chooses the particle state with the most information',
    () {
      final antiparticle = particle(
        id: 1,
        cc: 'A',
        charge: 1,
        i: '1',
        j: '1',
        p: '-',
      );
      final charged = particle(
        id: 2,
        cc: 'P',
        charge: 1,
        i: '1',
        j: '1',
        p: '+',
      );
      final neutral = particle(
        id: 3,
        cc: 'P',
        charge: 0,
        i: '1',
        g: '+',
        j: '1',
        p: '+',
        c: '-',
      );
      final chosen = representativeParticle([antiparticle, charged, neutral]);
      expect(chosen, isNotNull);
      expect(chosen!.id, 3);
      expect(
        ParticleQuantumNumbers.fromParticle(chosen).plain,
        'J^PC = 1^+- · I = 1 · G = +',
      );
    },
  );

  test('representative falls back to self-conjugate then the first row', () {
    final self = particle(id: 2, cc: 'S', j: '0');
    expect(representativeParticle([self])!.id, 2);
    final other = particle(id: 3, cc: 'A', j: '1/2');
    expect(representativeParticle([other])!.id, 3);
    expect(representativeParticle(const <Particle>[]), isNull);
  });
}
