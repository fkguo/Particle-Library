import 'models.dart';

/// Display form of the snapshot's quantum-number columns.
///
/// PDG writes the spin-parity block as `J^PC`, isospin as `I`, and the G and C
/// parities separately. The snapshot stores the individual components, with
/// SQL NULL, the empty string and `?` all meaning "not stated". Those never
/// become a made-up symbol in the compact catalog line.
class ParticleQuantumNumbers {
  const ParticleQuantumNumbers({this.i, this.g, this.j, this.p, this.c});

  factory ParticleQuantumNumbers.fromParticle(Particle particle) =>
      ParticleQuantumNumbers.fromValues(
        i: particle.quantumI,
        g: particle.quantumG,
        j: particle.quantumJ,
        p: particle.quantumP,
        c: particle.quantumC,
      );

  factory ParticleQuantumNumbers.fromValues({
    String? i,
    String? g,
    String? j,
    String? p,
    String? c,
  }) {
    return ParticleQuantumNumbers(
      i: _known(i),
      g: _known(g),
      j: _known(j),
      p: _known(p),
      c: _known(c),
    );
  }

  static const ParticleQuantumNumbers none = ParticleQuantumNumbers();

  final String? i;
  final String? g;
  final String? j;
  final String? p;
  final String? c;

  static String? _known(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == '?') return null;
    return text;
  }

  /// Typeset tokens, one per known quantity. C is folded into `J^PC` when the
  /// spin is a single value and both parities are known; otherwise P and C are
  /// kept as separate tokens so a compound or unknown J never swallows them.
  List<QuantumNumberToken> get tokens {
    final result = <QuantumNumberToken>[];
    var jIncludesP = false;
    var jIncludesC = false;
    final spin = j;
    if (spin != null) {
      final parity = p;
      final chargeParity = c;
      if (_simpleSpin.hasMatch(spin) &&
          parity != null &&
          chargeParity != null) {
        jIncludesP = true;
        jIncludesC = true;
        result.add(
          QuantumNumberToken(
            'J^{PC} = $spin^{$parity$chargeParity}',
            'J^PC = $spin^$parity$chargeParity',
          ),
        );
      } else if (_simpleSpin.hasMatch(spin) && parity != null) {
        jIncludesP = true;
        result.add(
          QuantumNumberToken('J^{P} = $spin^{$parity}', 'J^P = $spin^$parity'),
        );
      } else {
        // A value such as `2++ or 4` or `>=5/2` is already a complete source
        // expression; appending a parity superscript would change its meaning.
        result.add(QuantumNumberToken('J = $spin', 'J = $spin'));
      }
    }
    final parity = p;
    if (parity != null && !jIncludesP) {
      result.add(QuantumNumberToken('P = $parity', 'P = $parity'));
    }
    final isospin = i;
    if (isospin != null) {
      result.add(QuantumNumberToken('I = $isospin', 'I = $isospin'));
    }
    final gParity = g;
    if (gParity != null) {
      result.add(QuantumNumberToken('G = $gParity', 'G = $gParity'));
    }
    final cParity = c;
    if (cParity != null && !jIncludesC) {
      result.add(QuantumNumberToken('C = $cParity', 'C = $cParity'));
    }
    return List.unmodifiable(result);
  }

  static final RegExp _simpleSpin = RegExp(r'^[0-9]+(?:/[0-9]+)?$');

  bool get isEmpty => tokens.isEmpty;

  bool get isNotEmpty => tokens.isNotEmpty;

  /// A single string with inline `$...$` mathematics, ready for
  /// `DescriptionText`.
  String get latex => tokens.map((token) => '\$${token.latex}\$').join(' · ');

  /// The same line without TeX, suitable for tooltips and semantics.
  String get plain => tokens.map((token) => token.plain).join(' · ');

  @override
  bool operator ==(Object other) {
    return other is ParticleQuantumNumbers &&
        other.i == i &&
        other.g == g &&
        other.j == j &&
        other.p == p &&
        other.c == c;
  }

  @override
  int get hashCode => Object.hash(i, g, j, p, c);
}

class QuantumNumberToken {
  const QuantumNumberToken(this.latex, this.plain);

  final String latex;
  final String plain;
}

/// The particle whose quantum numbers represent a listing in a compact row.
///
/// A listing usually carries the particle and its antiparticle, whose P parity
/// (and sometimes C) differ. Antiparticles are excluded when a particle or
/// self-conjugate state exists; among the remaining charge states the neutral
/// one is preferred because it can carry C. Information completeness wins over
/// the charge preference, and ties keep the source order stable by id.
Particle? representativeParticle(Iterable<Particle> particles) {
  final all = particles.toList(growable: false);
  if (all.isEmpty) return null;
  final notAntiparticles = all
      .where((particle) => particle.ccType != 'A')
      .toList(growable: false);
  final pool = notAntiparticles.isNotEmpty ? notAntiparticles : all;
  final ranked = [...pool]
    ..sort((a, b) {
      final byInformation = _informationScore(b)
          .compareTo(_informationScore(a));
      if (byInformation != 0) return byInformation;
      final byCharge = (a.charge ?? 1).abs().compareTo((b.charge ?? 1).abs());
      if (byCharge != 0) return byCharge;
      // Prefer the particle state over the self-conjugate row only after the
      // neutral and information checks, so rho(770)0 is not displaced by a
      // charged rho(770)+.
      final byType = (a.ccType == 'P' ? 0 : 1).compareTo(
        b.ccType == 'P' ? 0 : 1,
      );
      if (byType != 0) return byType;
      return a.id.compareTo(b.id);
    });
  return ranked.first;
}

int _informationScore(Particle particle) {
  final values = [
    particle.quantumI,
    particle.quantumG,
    particle.quantumJ,
    particle.quantumP,
    particle.quantumC,
  ];
  return values.where((value) {
    final text = value?.trim();
    return text != null && text.isNotEmpty && text != '?';
  }).length;
}
