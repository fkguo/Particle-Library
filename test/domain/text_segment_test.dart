import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/latex.dart';
import 'package:pdgapp/domain/pdg_math.dart';

void main() {
  test('review titles can typeset a neutral-meson pair', () {
    final segments = segmentPdgText(r'$D_0$–$\bar{D}_0$ mixing');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'D_0',
      r'\bar{D}_0',
    ]);
    expect(segments.map((s) => s.text).whereType<String>().join(), '– mixing');
  });

  test('PDG text is segmented into whole math fragments or literal text', () {
    final segments = segmentPdgText(r'coupling g**nu_{{{{\mathit \ell}}}} at');
    expect(segments.map((s) => s.latex).whereType<String>(), [
      r'g^{\nu_{\ell}}',
    ]);
    expect(segments.first.text, 'coupling ');
    expect(segments.last.text, ' at');
  });

  test('g(A)**e and g(V)**e use subscript A/V and superscript e', () {
    final segments = segmentPdgText('g(A)**e and g(V)**e');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'g_{A}^{e}',
      r'g_{V}^{e}',
    ]);
    expect(segments[1].text, ' and ');
  });

  test('spaces inside parentheses do not split an expression', () {
    final segments = segmentPdgText('sin**2(2 theta(12)) is small');
    expect(segments.first.latex, r'\sin^{2}(2\theta_{12})');
  });

  test('ambiguous or unsupported runs stay verbatim', () {
    for (final source in [
      'CLEO-c',
      'Deltam(21)**2',
      'pi**0+',
      'a_0(980)**+0',
    ]) {
      final segments = segmentPdgText(source);
      expect(segments, hasLength(1), reason: source);
      expect(segments.single.text, source, reason: source);
    }
  });

  test('arrows are typeset and adjacent names stay separate', () {
    final segments = segmentPdgText('D0 --> K- pi+');
    expect(segments.map((s) => s.latex).whereType<String>(), [
      r'D^{0}',
      r'\longrightarrow',
      r'K^{-}',
      r'\pi^{+}',
    ]);
  });

  test('bare articles and variables stay prose, particle symbols do not', () {
    final prose = segmentPdgText('a measurement of A and I');
    expect(prose.every((s) => s.latex == null), isTrue);
    expect(prose.map((s) => s.text).join(), 'a measurement of A and I');
    final particle = segmentPdgText('the W boson');
    expect(particle.where((s) => s.latex != null).map((s) => s.latex), ['W']);
  });

  test('failed composite formulas still get complete name tokens', () {
    final segments = segmentPdgText('G(Z --> pi0 gamma)/G(total)');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'\Gamma(Z\to \pi^{0}\gamma)',
      r'\Gamma(\mathrm{total})',
    ]);
  });

  test('top-level operator splits convert complete function calls', () {
    final segments = segmentPdgText('mass(pi+-)-mass(pi0)');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'm_{\pi^{\pm}}',
      r'm_{\pi^{0}}',
    ]);
    expect(
      segments.where((s) => s.text != null).map((s) => s.text),
      contains('-'),
    );
  });

  test('collaboration names stay literal, including CLEO-c', () {
    for (final source in ['CLEO-c', 'LHCb', 'Belle II', 'BESIII', 'L3']) {
      final segments = segmentPdgText(source);
      expect(segments.every((s) => s.latex == null), isTrue, reason: source);
      expect(segments.map((s) => s.text).join(), source, reason: source);
    }
    expect(textTokenToLatex('CLEO-c'), isNull);
    expect(textTokenToLatex('D0'), r'D^{0}');
  });

  test('formula titles typeset Z, J/psi and generic leptons', () {
    final segments = segmentPdgText(
      'G(Z --> J/psi(1S) lepton+ lepton-)/G(total)',
    );
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'\Gamma(Z\to J/\psi(1S)\ell^{+}\ell^{-})',
      r'\Gamma(\mathrm{total})',
    ]);
  });

  test('a dollar math segment directly after a word is not swallowed', () {
    final segments = segmentPdgText(
      r'Observation of the Z$\to\psi\ell^+\ell^-$ decay',
    );
    final latex = segments
        .where((s) => s.latex != null)
        .map((s) => s.latex)
        .toList();
    expect(latex, contains(r'\to\psi\ell^+\ell^-'));
  });

  test('K0S and eta prime in measurement comments', () {
    final segments = segmentPdgText("J/psi --> gamma K0S K0S eta^'");
    final latex = segments
        .where((s) => s.latex != null)
        .map((s) => s.latex)
        .toList();
    expect(latex, contains(r'K_{S}^{0}'));
    expect(latex, contains(r"\eta^{\prime}"));
  });

  test('luminosity units and neutralino names', () {
    final segments = segmentPdgText('1.6 fb**-1 chitilde_1()0');
    expect(
      segments.where((s) => s.latex != null).map((s) => s.latex),
      containsAll([r'\mathrm{fb}^{-1}', r'\tilde{\chi}_{1}^{0}']),
    );
  });

  test('mbar is typeset as a barred mass', () {
    final segments = segmentPdgText('mbar = (mass(u)+mass(d))/2');
    expect(
      segments.where((s) => s.latex != null).map((s) => s.latex),
      contains(r'\bar{m}'),
    );
  });

  test('flavour tags, annotations and charge conjugates stay typeset', () {
    final segments = segmentPdgText(
      'G(tau- --> K- pi+ pi- nu_tau)/G(tau- --> K- pi+ pi- nu_tau (ex.K0))',
    );
    expect(segments.where((s) => s.latex != null).length, 2);
    expect(segments.map((s) => s.text ?? '').join().trim(), '/');
  });

  test('variable functions and double-star factors', () {
    final segments = segmentPdgText('(1 + q(r)**2 R**2) / (1 + q^2 R^2)');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'(1+q(r)^{2}R^{2})',
      r'(1+q^{2}R^{2})',
    ]);
    expect(segments.map((s) => s.text ?? '').join().trim(), '/');
  });

  test('C-odd chi state notation with comma-separated chain', () {
    final segments = segmentPdgText(
      'G(B+ --> chi_c1-odd(3872) K+ , chi_c1-odd --> J/psi eta)/G(total)',
    );
    expect(segments.where((s) => s.latex != null).length, 2);
    expect(segments.first.latex, contains(r'\chi_{c1-\mathrm{odd}}'));
  });

  test('non-phi keeps the upright prefix with an italic phi', () {
    final segments = segmentPdgText('D+ --> K+ K- pi+ pi0 non-phi');
    expect(
      segments.where((segment) => segment.latex != null).map((s) => s.latex),
      contains(r'\text{non-}\phi'),
    );
    expect(convertPdgExpression('non-phi'), r'\text{non-}\phi');
  });

  test('parenthetical prose stays literal', () {
    expect(
      segmentPdgText('(shown rounded)').every((s) => s.latex == null),
      isTrue,
    );
    expect(
      segmentPdgText('(Particle Data Group)').every((s) => s.latex == null),
      isTrue,
    );
  });

  test('mass differences with nested particle labels', () {
    final segments = segmentPdgText('mass(chi_c1(3872))-mass(J/psi)');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'm_{\chi_{c1}(3872)}',
      r'm_{J/\psi}',
    ]);
    expect(segments.map((s) => s.text ?? '').join(), '-');
  });

  test('measurement-parameter titles typeset Greek symbols', () {
    final first = segmentPdgText(
      '|(xi PARAMETER)*(μ LONGITUDINAL POLARIZATION)|',
    ).where((segment) => segment.latex != null).map((s) => s.latex);
    expect(first, containsAll([r'\xi', r'\mu']));

    final second = segmentPdgText(
      'xi * (μ LONGITUDINAL POLARIZATION) * delta / ρ',
    ).where((segment) => segment.latex != null).map((s) => s.latex);
    expect(second, containsAll([r'\xi', r'\mu', r'\delta', r'\rho']));
  });

  test('trailing quantity labels stay prose, not subscripts', () {
    for (final source in [
      'B_s0 MASS',
      'K(S)0 MEAN LIFE',
      'B_s* MASS',
      'Omega_b MEAN LIFE',
    ]) {
      final segments = segmentPdgText(source);
      expect(segments.last.text, isNotNull, reason: source);
      expect(segments.first.latex, isNotNull, reason: source);
    }
    expect(segmentPdgText('B_s0 MASS').first.latex, r'B_{s}^{0}');
    expect(
      segmentPdgText('T_c c cbar cbar(6600) MASS').first.latex,
      r'T_{cc\bar{c}\bar{c}}(6600)',
    );
  });

  test('spaced multi-charm particle descriptions stay one math unit', () {
    final segments = segmentPdgText('T_c c cbar cbar(6600)');
    expect(segments, hasLength(1));
    expect(segments.single.latex, r'T_{cc\bar{c}\bar{c}}(6600)');
  });

  test('dollar TeX and bare names both work', () {
    final segments = segmentPdgText(r'$B_s^0$ and D0');
    expect(segments.first.latex, r'B_s^0');
    expect(segments.last.latex, r'D^{0}');
  });

  test('descriptive titles keep prose and typeset only particle symbols', () {
    final segments = segmentPdgText('pi ELECTRIC POLARIZABILITY alpha(pi)');
    final latex = segments
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(latex, contains(r'\pi'));
    expect(latex, contains(r'\alpha_{\pi}'));
    expect(latex.every((value) => !value.contains('ELECTRIC')), isTrue);
    expect(latex.every((value) => !value.contains('POLARIZABILITY')), isTrue);
    final plain = segments
        .where((segment) => segment.text != null)
        .map((segment) => segment.text!)
        .join();
    expect(plain, contains('ELECTRIC'));
    expect(plain, contains('POLARIZABILITY'));
  });

  test('reverse-related measurement descriptions are fully typeset', () {
    final absolute = segmentPdgText('ABS(mass(D_10)-mass(D_20)) = x Gamma');
    final absoluteLatex = absolute
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(
      absoluteLatex,
      contains(r'\left|m_{D_{1}^{0}}-m_{D_{2}^{0}}\right|'),
    );
    expect(absoluteLatex, contains('x'));
    expect(absoluteLatex, contains(r'\Gamma'));
    expect(
      absolute
          .where((segment) => segment.text != null)
          .map((segment) => segment.text!)
          .join(),
      isNot(contains('D_10')),
    );

    final widths = segmentPdgText('(Gamma(D_10) - Gamma(D_20))/Gamma = 2y');
    final widthsLatex = widths
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(widthsLatex, contains(r'\Gamma'));
    expect(widthsLatex, contains('2y'));
    expect(
      widths
          .where((segment) => segment.text != null)
          .map((segment) => segment.text!)
          .join(),
      isNot(contains('D_10')),
    );

    final coherence = segmentPdgText(
      'D0 --> K- pi- 2pi+ COHERENCE FACTOR R(K 3pi)',
    );
    final coherenceLatex = coherence
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(coherenceLatex, contains(r'2\pi^{+}'));
    expect(coherenceLatex, contains(r'R(K3\pi)'));
    expect(
      coherence
          .where((segment) => segment.text != null)
          .map((segment) => segment.text!)
          .join(),
      contains('COHERENCE FACTOR'),
    );

    final phase = segmentPdgText(
      'D0 --> K- pi- 2pi+ AVERAGE RELATIVE STRONG PHASE delta**K 3pi',
    );
    final phaseLatex = phase
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(phaseLatex, contains(r'\delta^{K}'));
    expect(phaseLatex, contains(r'3\pi'));
    expect(
      phase
          .where((segment) => segment.text != null)
          .map((segment) => segment.text!)
          .join(),
      contains('AVERAGE RELATIVE STRONG PHASE'),
    );
  });

  test('reference titles with compact star and charge notation typeset', () {
    final segments = segmentPdgText(
      'Study of B- --> D^**0 pi- (D^**0 --> D^(*)+ pi-) Decays',
    );
    final latex = segments
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .toList();
    expect(latex, contains(r'B^{-}'));
    expect(latex, contains(r'D^{**0}'));
    final joined = latex.join(' ');
    expect(joined, contains(r'D^{(*)+}'));
    expect(joined, contains(r'\pi^{-}'));
    expect(joined, contains(r'\longrightarrow'));
    final plain = segments
        .where((segment) => segment.text != null)
        .map((segment) => segment.text!)
        .join();
    expect(plain, contains('Study of'));
    expect(plain, contains('Decays'));
  });

  test('comma-separated branching-ratio descriptions keep math tokens', () {
    final segments = segmentPdgText(
      'G(D0 --> K*(892)- 2pi+ pi- , K*(892)- --> K0S pi- , no rho0)/'
      'G(D0 --> K0S 2pi+ 2pi-)',
    );
    final latex = segments
        .where((segment) => segment.latex != null)
        .map((segment) => segment.latex!)
        .join(' ');
    expect(latex, contains(r'K^{*}(892)^{-}'));
    expect(latex, contains(r'K_{S}^{0}'));
    expect(latex, contains(r'\rho^{0}'));
    expect(latex, contains(r'\Gamma'));
    final plain = segments
        .where((segment) => segment.text != null)
        .map((segment) => segment.text!)
        .join();
    expect(plain, contains('no'));
    expect(plain, isNot(contains('K0S')));
    expect(plain, isNot(contains('K*(892)-')));
  });
  test('measurement uncertainties are typeset with pm', () {
    final segments = segmentPdgText('The mass difference is 185.54+-0.06 MeV');
    expect(segments.where((s) => s.latex != null).map((s) => s.latex), [
      r'185.54 \pm 0.06',
    ]);
    expect(segments.first.text, 'The mass difference is ');
    expect(segments.last.text, ' MeV');
  });

  test('a chained uncertainty keeps its order and parentheses', () {
    final segments = segmentPdgText('(-0.71+-0.96+-0.19) MeV.');
    expect(segments.map((s) => s.text ?? s.latex), [
      '(',
      r'-0.71 \pm 0.96 \pm 0.19',
      ') MeV.',
    ]);
  });

  test('bare signs and detector names are not measurement values', () {
    for (final source in ['run 5+ and 6-', 'CLEO-c 2020', '1.2 + 3.4']) {
      final segments = segmentPdgText(source);
      expect(segments.every((s) => s.latex == null), isTrue, reason: source);
    }
  });
}
