import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/core/contract.dart';
import 'package:pdgapp/data/pdg_database.dart';
import 'package:pdgapp/data/sql_executor.dart';
import 'package:pdgapp/domain/models.dart';
import 'package:pdgapp/domain/quantum_numbers.dart';

void main() {
  late DirectSqlExecutor executor;
  late PdgDatabase db;

  setUpAll(() async {
    if (!File('assets/pdgall-2026.0.sqlite').existsSync()) {
      fail(
        'Snapshot asset missing; this suite runs against the real pdgall file.',
      );
    }
    executor = await DirectSqlExecutor.open('assets/pdgall-2026.0.sqlite');
    db = await PdgDatabase.open(
      executor,
      snapshotHash: SnapshotContract.expectedSha256,
    );
  });

  tearDownAll(() async {
    await executor.dispose();
  });

  Future<ParticleQuantumNumbers> quantumFor(String pdgid) async {
    final entry = await db.requireEntryByPdgid(pdgid);
    final particles = await db.particlesForEntry(entry.id);
    final chosen = representativeParticle(particles);
    expect(chosen, isNotNull, reason: '$pdgid has a particle row');
    return ParticleQuantumNumbers.fromParticle(chosen!);
  }

  test('charged pion shows J^P, I and G without an invented C', () async {
    final quantum = await quantumFor('S008');
    expect(quantum.plain, 'J^P = 0^- · I = 1 · G = -');
    expect(quantum.latex, r'$J^{P} = 0^{-}$ · $I = 1$ · $G = -$');
  });

  test('neutral pion folds C into J^PC', () async {
    final quantum = await quantumFor('S009');
    expect(quantum.plain, 'J^PC = 0^-+ · I = 1 · G = -');
    expect(quantum.latex, r'$J^{PC} = 0^{-+}$ · $I = 1$ · $G = -$');
  });

  test('a tensor meson keeps its full J^PC block', () async {
    final quantum = await quantumFor('M005');
    expect(quantum.plain, 'J^PC = 2^++ · I = 0 · G = +');
  });

  test('a W boson with only spin recorded shows J alone', () async {
    final quantum = await quantumFor('S043');
    expect(quantum.plain, 'J = 1');
    expect(quantum.tokens, hasLength(1));
  });

  test('the photon keeps its comma-separated isospin', () async {
    final quantum = await quantumFor('S000');
    expect(quantum.plain, 'J^PC = 1^-- · I = 0,1');
  });

  test('the representative of a multiplet is the particle state', () async {
    final quantum = await quantumFor('B033');
    // Delta(1232): the particle state has P = +; the antiparticle has P = -.
    expect(quantum.plain, 'J^P = 3/2^+ · I = 3/2');
  });

  test('batched particles match per-entry queries in source order', () async {
    final roots = (await db.catalogRoots())
        .where((root) => root.particleCount > 0)
        .take(40)
        .toList(growable: false);
    final batched = await db.particlesForEntries([
      for (final root in roots) root.entry.id,
    ]);
    for (final root in roots) {
      final direct = await db.particlesForEntry(root.entry.id);
      expect(
        batched[root.entry.id]?.map((particle) => particle.id).toList(),
        direct.map((particle) => particle.id).toList(),
        reason: root.entry.pdgid,
      );
    }
  });

  test('every catalog listing with a particle can be formatted', () async {
    final roots = await db.catalogRoots();
    final byEntry = await db.particlesForEntries([
      for (final root in roots) root.entry.id,
    ]);
    var withQuantum = 0;
    for (final root in roots) {
      final particles = byEntry[root.entry.id] ?? const <Particle>[];
      if (particles.isEmpty) continue;
      final chosen = representativeParticle(particles);
      expect(chosen, isNotNull, reason: root.entry.pdgid);
      final quantum = ParticleQuantumNumbers.fromParticle(chosen!);
      if (quantum.isNotEmpty) {
        withQuantum++;
        expect(quantum.latex, contains(r'$'));
        expect(quantum.plain, isNot(contains(r'$')));
      }
    }
    // The snapshot leaves some states with only unknown (`?`) components; the
    // great majority still carry a displayable J/I/G/C block.
    expect(withQuantum, greaterThan(350));
  });
}
