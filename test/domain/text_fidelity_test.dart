import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/domain/latex.dart';
import 'package:pdgapp/domain/reference_title.dart';

/// The segments of [source] as one string: plain text in brackets, converted
/// mathematics as `<M:latex>`.
String render(String source) {
  final buffer = StringBuffer();
  for (final segment in segmentPdgText(source)) {
    buffer.write(
      segment.latex != null ? '<M:${segment.latex}>' : '[${segment.text}]',
    );
  }
  return buffer.toString();
}

void main() {
  group('J^PC signs are parities', () {
    test('0-+ and +- are not typeset as plus-minus signs', () {
      expect(
        quantumLineToLatex('eta(2010) IG(JPC) = 0+(0-+)'),
        r'\eta(2010)\,I^{G}(J^{PC}) = 0^{+}(0^{-+})',
      );
      expect(
        quantumLineToLatex('h_1(1900) IG(JPC) = 0-(1+-)'),
        r'h_{1}(1900)\,I^{G}(J^{PC}) = 0^{-}(1^{+-})',
      );
      expect(
        quantumLineToLatex('pi(2360) IG(JPC) = 1-(0-+)'),
        r'\pi(2360)\,I^{G}(J^{PC}) = 1^{-}(0^{-+})',
      );
    });

    test('the other parity combinations are unchanged', () {
      expect(
        quantumLineToLatex('rho(770) IG(JPC) = 1+(1--)'),
        r'\rho(770)\,I^{G}(J^{PC}) = 1^{+}(1^{--})',
      );
      expect(
        quantumLineToLatex('f_2(1270) IG(JPC) = 0+(2++)'),
        r'f_{2}(1270)\,I^{G}(J^{PC}) = 0^{+}(2^{++})',
      );
    });

    test('a charge written +- on a particle is still plus-minus', () {
      expect(render('W+-'), r'<M:W^{\pm}>');
    });

    test('a generated J^PC line keeps both parity signs', () {
      expect(render(r'$J^{PC} = 0^{-+}$'), r'<M:J^{PC} = 0^{-+}>');
      expect(render(r'$J^{PC} = 1^{+-}$'), r'<M:J^{PC} = 1^{+-}>');
      expect(render(r'$J^{P} = 1^{-+}$'), r'<M:J^{P} = 1^{-+}>');
    });
  });

  group('primes and separators never lose characters', () {
    test('a prime with an exponent keeps the exponent (D0 mixing x\'^2)', () {
      expect(render("x^'2"), r'<M:x^{\prime 2}>');
      expect(
        render("Reported x^'2 = 0.5"),
        r'[Reported ]<M:x^{\prime 2}>[ = 0.5]',
      );
    });

    test('a star before the prime is kept (D*\')', () {
      expect(
        render("D^*'(2629)+- X").contains(r'D^{*\prime}(2629)^{\pm}'),
        isTrue,
      );
    });

    test('two primes are two primes', () {
      expect(render("lambda''(+)"), contains(r'\lambda^{\prime \prime}(+)'));
    });

    test('a separator between a script and a word is not a placeholder', () {
      // "mu^2()A" is a square and a separate A, not a script "2A".
      expect(render('mu^2()A'), '[mu^2()A]');
    });

    test('"not=" stays as words after the symbol', () {
      expect(
        render("lambda_{{333}}^'()not=0"),
        r"<M:\lambda_{333}^{\prime}>[ not=0]",
      );
    });

    test('an empty mass placeholder before a charge is still accepted', () {
      expect(render('B_s()0'), r'<M:B_{s}^{0}>');
      expect(render('D_s^*()+'), r'<M:D_{s}^{*+}>');
    });

    test('a prime followed by letters is left as text, not shortened', () {
      // "V(t^'b)" used to lose the b: V(t').
      expect(render("V(t^'b)"), isNot(contains(r'V(t^{\prime})')));
    });
  });

  group('a sign followed by a word does not swallow the word', () {
    test('(-2.3)**+inf keeps its "inf"', () {
      expect(render('(-2.3)**+inf'), contains('inf'));
    });

    test('2**+-state keeps its "state"', () {
      expect(render('first excited 2**+-state of'), contains('state'));
    });

    test('a TeX line-break hint is not part of the text', () {
      expect(
        render('(rho pi)^-allowbreak nu_tau'),
        isNot(contains('allowbreak')),
      );
    });
  });

  group('reference labels stay prose', () {
    test('the letters of a label are not turned into symbols', () {
      // 1994G used to become 1994 followed by a Gamma, 2019N a nucleon N.
      expect(
        render('BUSKULIC 1994G uses e'),
        startsWith('[BUSKULIC 1994G uses '),
      );
      expect(
        render('AABOUD 2019N reports 4.7'),
        startsWith('[AABOUD 2019N reports'),
      );
      expect(render('Repl. by AUBERT 2009C'), '[Repl. by AUBERT 2009C]');
    });

    test('the case of the letters is kept', () {
      expect(render('SIRUNYAN 2019AT'), '[SIRUNYAN 2019AT]');
      expect(render('AAD 2023AT combine'), startsWith('[AAD 2023AT combine'));
    });

    test('an author with an initial is one label (AUBERT,B 2006B)', () {
      expect(render('Repl. by AUBERT,B 2006B'), '[Repl. by AUBERT,B 2006B]');
    });

    test('labels inside prose with particles around them', () {
      final text = render(
        'ABLIKIM 2014C uses e+ e- --> D0 Dbar0 at the psi(3770)',
      );
      expect(text, startsWith('[ABLIKIM 2014C uses '));
      expect(text, contains(r'<M:e^{+}>'));
      expect(text, contains(r'<M:\longrightarrow>'));
    });

    test('a year alone and ordinary words are untouched', () {
      expect(
        render('measured in 2011 at 7 TeV'),
        '[measured in 2011 at 7 TeV]',
      );
    });

    test('Supernova 1987A is not mathematics', () {
      expect(
        render('Supernova 1987A Constraints'),
        '[Supernova 1987A Constraints]',
      );
    });
  });

  group('reference titles', () {
    test('a charge sign before an arrow is not a plus-minus', () {
      expect(
        cleanReferenceTitle('New limit on the μ+->e+γdecay'),
        'New limit on the μ+->e+γdecay',
      );
    });

    test('deeply nested markup does not take exponential time', () {
      final watch = Stopwatch()..start();
      final title = '${'<b>' * 40}x${'</b>' * 40}';
      expect(cleanReferenceTitle(title), 'x');
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('MathML is still linearised', () {
      expect(
        cleanReferenceTitle(
          'at <math><msqrt><mi>s</mi></msqrt></math> = 13 TeV',
        ),
        'at √s = 13 TeV',
      );
    });

    test('an ASCII plus-minus is still converted', () {
      expect(
        cleanReferenceTitle('m_t = 172.5+-0.5 GeV'),
        'm_t = 172.5±0.5 GeV',
      );
    });
  });
}
