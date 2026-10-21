import 'models.dart';
import 'pdg_math.dart';

/// Conservative conversion of PDG's ASCII particle names into LaTeX.
///
/// The converter returns `null` whenever a name cannot be interpreted with
/// certainty; callers then fall back to the selectable raw text. It never drops
/// a character to make the output look clean.

/// Converts the PDG's `IG(JPC) = ...` shorthand into mathematics.
///
/// Examples:
/// `X(360) IG(JPC) = ??(??+)` → `X(360)\,I^{G}(J^{PC}) = ??(??^{+})`.
String? quantumLineToLatex(String source) {
  final match = RegExp(r'^(.*?)\s*IG\(JPC\)\s*=\s*(.+)$')
      .firstMatch(source.trim());
  if (match == null) return null;
  final prefixText = match.group(1)!.trim();
  final value = match.group(2)!.trim();
  final prefix = prefixText.isEmpty ? '' : particleNameToLatex(prefixText);
  if (prefixText.isNotEmpty && prefix == null) return null;

  final valueMatch = RegExp(r'^([^()]*)\(([^()]*)\)\s*$').firstMatch(value);
  String? valueLatex;
  if (valueMatch != null) {
    final isospin = _quantumValue(valueMatch.group(1)!.trim());
    final jpc = _quantumValue(valueMatch.group(2)!.trim());
    if (isospin != null && jpc != null) {
      valueLatex = '$isospin($jpc)';
    }
  } else {
    valueLatex = _quantumValue(value);
  }
  if (valueLatex == null) return null;
  return [
    if (prefix != null && prefix.isNotEmpty) '$prefix\\,',
    r'I^{G}(J^{PC}) = ',
    valueLatex,
  ].join();
}

String? _quantumValue(String source) {
  final value = source.trim();
  if (value.isEmpty) return null;
  final match = RegExp(r'^(.*?)(\+\+|\-\-|\+\-|\-\+|\+|\-|\?)$')
      .firstMatch(value);
  final base = (match?.group(1) ?? value).trim();
  final suffix = match?.group(2) ?? '';
  if (base.isEmpty) return null;
  final baseLatex = RegExp(r'^[0-9/?]+$').hasMatch(base)
      ? base
      : base == 'even' || base == 'odd'
      ? '\\mathrm{$base}'
      : null;
  if (baseLatex == null) return null;
  if (suffix.isEmpty || suffix == '?') return '$baseLatex$suffix';
  final suffixLatex = switch (suffix) {
    '+-' => r'\pm',
    '-+' => r'\mp',
    _ => suffix,
  };
  return '$baseLatex^{$suffixLatex}';
}

String? particleNameToLatex(String source) {
  final quantum = quantumLineToLatex(source);
  if (quantum != null) return quantum;
  final ckm = RegExp(r'^V\(([udscbt]{2})\)$').firstMatch(source.trim());
  if (ckm != null) return 'V_{${ckm.group(1)}}';
  var name = source.trim();
  if (name.isEmpty) return null;
  // PDG occasionally separates repeated subscript letters with spaces
  // (`T_c c cbar cbar`). Spaces are not part of the particle identity.
  name = name.replaceAll(RegExp(r'\s+'), '_');
  if (name.contains(RegExp(r'[\[\]<>,;|\\%&$#]'))) return null;
  if (name == 'K0S') return r'K_{S}^{0}';
  if (name == 'K0L') return r'K_{L}^{0}';

  // Kaon short states use a parenthesised subscript in the source.
  name = name.replaceAll(RegExp(r'\(L\)'), '_L');
  name = name.replaceAll(RegExp(r'\(S\)'), '_S');

  // LaTeX-style charge annotation: B_s^0, D_s^+, B_s^{+-}. The database names
  // usually write the neutral charge after an empty mass placeholder instead;
  // both forms are accepted for display and text enrichment.
  String? caretCharge;
  final caretChargeMatch = RegExp(r'\^(?:\{([+\-0]{1,2})\}|([+\-0]{1,2}))$')
      .firstMatch(name);
  if (caretChargeMatch != null) {
    caretCharge = caretChargeMatch.group(1) ?? caretChargeMatch.group(2);
    name = name.substring(0, caretChargeMatch.start);
  }

  // Trailing charge.
  String? charge;
  final chargeMatch = RegExp(r'(\+\+|\-\-|\+\-|\-\+|\+|\-|0)$')
      .firstMatch(name);
  if (chargeMatch != null) {
    charge = chargeMatch.group(1);
    name = name.substring(0, name.length - charge!.length);
  }
  charge ??= caretCharge;

  // Empty mass placeholders such as `B_s()0` and `D_s^*()+`.
  name = name.replaceAll('()', '');

  // Mass label in parentheses.
  String? mass;
  final massMatch = RegExp(r'\(([^()]*)\)$').firstMatch(name);
  if (massMatch != null) {
    mass = massMatch.group(1);
    name = name.substring(0, name.length - mass!.length - 2);
  }

  // Subscripts/superscripts. PDG writes multi-part subscripts as repeated
  // underscores (`T_c_cbar_1`), so collect every trailing `_...`/`^...`
  // segment rather than only the last one.
  final subParts = <String>[];
  final supParts = <String>[];
  while (true) {
    final script = RegExp(r"([_^])([A-Za-z0-9*'\u2032]+)$").firstMatch(name);
    if (script == null) break;
    var value = script.group(2)!;
    if (script.group(1) == '_') {
      // `D_s3*(...)` stores the star in the same token as the subscript.
      final star = RegExp(r"([*'\u2032]+)$").firstMatch(value);
      if (star != null) {
        supParts.insert(0, star.group(1)!);
        value = value.substring(0, star.start);
      }
      if (value.isNotEmpty) subParts.insert(0, value);
    } else {
      supParts.insert(0, value);
    }
    name = name.substring(0, script.start);
  }
  // Bare star/prime, e.g. D*(2010) after the mass was removed.
  final bareSup = RegExp(r"([*'\u2032]+)$").firstMatch(name);
  if (bareSup != null) {
    supParts.insert(0, bareSup.group(1)!);
    name = name.substring(0, bareSup.start);
  }
  final sub = subParts.isEmpty ? null : subParts;
  final sup = supParts.isEmpty ? null : supParts.join();

  if (name.isEmpty) return null;
  if (name.contains(RegExp(r'[^A-Za-z/]'))) return null;

  var anti = false;
  if (name.endsWith('bar') && name.length > 3) {
    anti = true;
    name = name.substring(0, name.length - 3);
  }

  final base = _baseLatex(name);
  if (base == null) return null;

  final buffer = StringBuffer();
  if (anti) buffer.write(r'\bar{');
  buffer.write(base);
  if (anti) buffer.write('}');
  if (sub != null && sub.isNotEmpty) {
    buffer.write('_{');
    buffer.write(_subPartsLatex(sub));
    buffer.write('}');
  }

  final superscript = <String>[];
  if (sup != null && sup.isNotEmpty) {
    superscript.add(sup.replaceAll('\u2032', "'"));
  }
  final chargePart = <String>[];
  if (charge == '0') {
    chargePart.add('0');
  } else if (charge != null && charge.isNotEmpty) {
    chargePart.add(charge);
  }

  if (mass == null) {
    // No mass label: star and charge conventionally share one superscript.
    final combined = <String>[];
    for (final part in superscript) {
      combined.add(part == '*' ? '*' : part);
    }
    combined.addAll(chargePart);
    if (combined.isNotEmpty) {
      buffer.write('^{');
      for (final part in combined) {
        buffer.write(_supPartLatex(part));
      }
      buffer.write('}');
    }
  } else {
    // With a mass: star/prime first, then mass, then charge.
    if (superscript.isNotEmpty) {
      buffer.write('^{');
      for (final part in superscript) {
        buffer.write(_supPartLatex(part));
      }
      buffer.write('}');
    }
    buffer.write('(');
    final nestedMass = particleNameToLatex(mass);
    buffer.write(
      nestedMass ?? mass.replaceAll(r'\', '').replaceAll('~', r'\sim '),
    );
    buffer.write(')');
    if (chargePart.isNotEmpty) {
      buffer.write('^{');
      for (final part in chargePart) {
        buffer.write(_supPartLatex(part));
      }
      buffer.write('}');
    }
  }

  final latex = buffer.toString();
  if (latex.contains('\\bar{}')) return null;
  return latex;
}

String _subLatex(String sub) {
  return switch (sub) {
    'tau' => r'\tau',
    'mu' => r'\mu',
    'e' => 'e',
    _ => sub,
  };
}

String _subPartsLatex(List<String> parts) {
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.length > 3 && part.endsWith('bar')) {
      // `c cbar` / `b bbar` are two flavour factors, not one fused token.
      final base = part.substring(0, part.length - 3);
      buffer.write(base.substring(0, base.length - 1));
      buffer.write(r'\bar{');
      buffer.write(base.substring(base.length - 1));
      buffer.write('}');
    } else {
      // PDG Live writes P_{c\bar c s} with a normal space before a separate
      // one-letter flavour, but T_{c\bar c1} without one before an index.
      if (i > 0 &&
          part.length == 1 &&
          RegExp(r'[A-Za-z]').hasMatch(part) &&
          parts[i - 1].endsWith('bar')) {
        buffer.write(' ');
      }
      buffer.write(_subLatex(part));
    }
  }
  return buffer.toString();
}

String _supPartLatex(String part) {
  if (part.contains("'")) return r"\prime";
  if (part == '+-') return r'\pm';
  if (part == '-+') return r'\mp';
  return part;
}

String? _baseLatex(String name) {
  const greek = {
    'alpha': r'\alpha',
    'beta': r'\beta',
    'gamma': r'\gamma',
    'delta': r'\delta',
    'epsilon': r'\epsilon',
    'zeta': r'\zeta',
    'eta': r'\eta',
    'theta': r'\theta',
    'iota': r'\iota',
    'kappa': r'\kappa',
    'lambda': r'\lambda',
    'mu': r'\mu',
    'nu': r'\nu',
    'xi': r'\xi',
    'pi': r'\pi',
    'rho': r'\rho',
    'sigma': r'\sigma',
    'tau': r'\tau',
    'upsilon': r'\upsilon',
    'phi': r'\phi',
    'chi': r'\chi',
    'psi': r'\psi',
    'omega': r'\omega',
    'Delta': r'\Delta',
    'Gamma': r'\Gamma',
    'Theta': r'\Theta',
    'Lambda': r'\Lambda',
    'Xi': r'\Xi',
    'Pi': r'\Pi',
    'Sigma': r'\Sigma',
    'Upsilon': r'\Upsilon',
    'Phi': r'\Phi',
    'Psi': r'\Psi',
    'Omega': r'\Omega',
    'chitilde': r'\tilde{\chi}',
    'nutilde': r'\tilde{\nu}',
    'lambdatilde': r'\tilde{\lambda}',
    'kappatilde': r'\tilde{\kappa}',
    'leptontilde': r'\tilde{\ell}',
    'qtilde': r'\tilde{q}',
    'ttilde': r'\tilde{t}',
    'btilde': r'\tilde{b}',
  };
  if (name == 'J/psi') return r'J/\psi';
  if (name == 'G') return r'\Gamma';
  if (name == 'lepton') return r'\ell';
  if (name == 'KS') return r'K_{S}';
  if (name == 'KL') return r'K_{L}';
  final greekBase = greek[name];
  if (greekBase != null) return greekBase;
  const latin = {
    'p',
    'P',
    'n',
    'e',
    'g',
    'W',
    'Z',
    'H',
    'K',
    'D',
    'B',
    'N',
    'X',
    'Y',
    'f',
    'm',
    'a',
    'h',
    'b',
    'c',
    's',
    'd',
    'u',
    't',
    'r',
    'R',
    'A',
    'V',
    'T',
    'x',
    'y',
  };
  if (latin.contains(name)) return name;
  if (RegExp(r'^[A-Za-z]{2,}$').hasMatch(name)) {
    return '\\mathrm{$name}';
  }
  return null;
}

String mathEscapeText(String source) {
  final buffer = StringBuffer();
  for (final char in source.split('')) {
    switch (char) {
      case '\u005c':
        buffer.write(r'\backslash ');
      case '{':
      case '}':
      case '%':
      case '&':
      case '#':
      case r'$':
      case '_':
      case '^':
        buffer.write('\\$char');
      case '~':
        buffer.write(r'\sim ');
      default:
        buffer.write(char);
    }
  }
  return buffer.toString();
}

/// LaTeX for the ordered source tokens of a decay. The sequence is displayed
/// exactly in source order: arrows that are T items become `\longrightarrow`,
/// and text fragments stay text. This is not a claim that every token belongs
/// to a resolved physical stage.
String decayTokensToLatex(List<DecayToken> tokens) {
  final buffer = StringBuffer();
  bool? previousOutgoing;
  var arrowEmitted = false;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final name = token.name.trim();
    final isArrow =
        token.itemType != 'T' &&
        (name == '-->' ||
            name == r'\rightarrow' ||
            name == '→' ||
            name.contains('-->'));
    if (isArrow) {
      buffer.write(r'\;\longrightarrow\;');
      arrowEmitted = true;
      continue;
    }
    // A single-stage mode stores no arrow token; the incoming -> outgoing
    // change is the stage boundary and is typeset exactly once.
    if (previousOutgoing == false && token.isOutgoing && !arrowEmitted) {
      buffer.write(r'\;\longrightarrow\;');
      arrowEmitted = true;
    }
    if (i > 0 && !buffer.toString().endsWith(r'\;\longrightarrow\;')) {
      buffer.write(r'\;');
    }
    if (token.multiplier > 1) {
      buffer.write('${token.multiplier}');
    }
    final latex = particleNameToLatex(name);
    if (latex != null && token.itemType != 'T') {
      buffer.write(latex);
    } else {
      buffer.write(r'\text{');
      buffer.write(mathEscapeText(name));
      buffer.write('}');
    }
    previousOutgoing = token.isOutgoing;
  }
  return buffer.toString();
}

/// Converts one bare token from a description or explanatory text into LaTeX.
///
/// This handles the two spellings that occur in the snapshot's text fields:
/// the database's `D_s()+-` style and the TeX-ish `D_{{s}}()+-` /
/// `g**nu_{{e}}` style. A token with no mathematical marker and no known
/// particle symbol is returned as `null` so that normal prose stays prose.
String? textTokenToLatex(String token) {
  var trimmed = token.trim();
  // Crossref/PDG titles mix Unicode Greek with ASCII particle formulas.
  const unicodeGreek = {
    'μ': 'mu',
    'ρ': 'rho',
    'ξ': 'xi',
    'δ': 'delta',
    'α': 'alpha',
    'β': 'beta',
    'γ': 'gamma',
    'τ': 'tau',
    'π': 'pi',
    'σ': 'sigma',
    'λ': 'lambda',
    'ω': 'omega',
    'φ': 'phi',
    'χ': 'chi',
    'η': 'eta',
  };
  if (unicodeGreek.containsKey(trimmed)) {
    trimmed = unicodeGreek[trimmed]!;
  }
  if (trimmed.isEmpty || trimmed.length > 40) return null;
  // Crossref titles sometimes run the two final-state particles together.
  if (trimmed == 'J/psieta') return r'J/\psi\eta';
  if (trimmed == 'non-phi') return r'\text{non-}\phi';
  final lepton = RegExp(r'^lepton([+-]{1,2})?$').firstMatch(trimmed);
  if (lepton != null) {
    final charge = lepton.group(1);
    if (charge == null || charge.isEmpty) return r'\ell';
    final latex = switch (charge) {
      '+-' => r'\pm',
      '-+' => r'\mp',
      _ => charge,
    };
    return '\\ell^{$latex}';
  }
  // Experimental collaborations are names, not particle formulas. In
  // particular CLEO-c is the CLEO-c collaboration, never CLEO^- + c.
  if (_isCollaborationName(trimmed)) return null;
  final hasScript = RegExp(r'[_^]|\*\*|\{\{').hasMatch(trimmed);
  final hasSymbol = RegExp(r'[0-9*+\-\u2032]').hasMatch(trimmed);
  if (!hasScript && !hasSymbol) {
    // A bare one-letter word is usually an article or a mathematical
    // variable, not a particle. Convert only the unambiguous particle names
    // (and let the expression parser handle anything with structure).
    if (!_bareNameWords.contains(trimmed) &&
        !_isAntiSymbol(trimmed) &&
        !trimmed.contains('/')) {
      return null;
    }
    final bare = particleNameToLatex(trimmed);
    if (bare != null) return bare;
    if (!_isSymbolWord(trimmed)) return null;
  }

  // A multi-letter prose word such as CLEO or LHCb must not be turned into a
  // charged particle merely because of a trailing hyphen. Only known particle
  // bases (Greek names, anti-particle names, etc.) are accepted.
  final base =
      RegExp(r'^([A-Za-z]+(?:bar)?)').firstMatch(trimmed)?.group(1) ?? '';
  const unitWords = {'fb', 'pb', 'nb', 'ab'};
  if (base.length > 1 &&
      !_symbolWords.contains(base) &&
      !_isAntiSymbol(base) &&
      !unitWords.contains(base)) {
    return null;
  }

  var normalized = trimmed;
  while (normalized.contains('{{') || normalized.contains('}}')) {
    normalized = normalized.replaceAll('{{', '{').replaceAll('}}', '}');
  }
  normalized = normalized.replaceAll('**', '^');

  final simplified = normalized.replaceAll(RegExp(r'[{}]'), '');
  final particle = particleNameToLatex(simplified);
  if (particle != null) return particle;
  if (RegExp(r'^[0-9]+[A-Za-z]').hasMatch(trimmed)) {
    final expression = convertPdgExpression(trimmed);
    if (expression != null) return expression;
  }
  if (!hasScript) return null;
  return convertPdgExpression(trimmed);
}

/// Converts the PDG's explanatory-text markup to LaTeX.
///
/// The actual grammar lives in [convertPdgExpression]; this wrapper keeps the
/// older call sites and tests explicit.
String? sourceExpressionToLatex(String source) => convertPdgExpression(source);

/// A run of PDG text: either literal prose or a converted LaTeX fragment.
class PdgTextSegment {
  const PdgTextSegment.plain(this.text) : latex = null;

  const PdgTextSegment.math(this.latex) : text = null;

  final String? text;
  final String? latex;
}

/// Splits PDG explanatory text into literal and math segments.
///
/// Candidate expressions are scanned as balanced units (spaces inside braces
/// and parentheses are allowed). A candidate is typeset only when the whole
/// candidate converts; otherwise the exact original substring is emitted as
/// literal text. This is what prevents a half-converted formula such as
/// `sin**2(2 theta(12))` from turning into a valid prefix plus a broken tail.
List<PdgTextSegment> segmentPdgText(String original) {
  // Quantity labels such as `MASS`, `WIDTH` or `MEAN LIFE` are prose, not
  // part of the particle name. Split them before whole-name conversion;
  // otherwise `B_s0 MASS` becomes a single fake subscript.
  final suffix = RegExp(
    r'^(.*?)(\s+(?:BREIT-WIGNER\s+)?(?:MASS|WIDTH|MEAN\s+LIFE|LIFETIME|'
    r'MODE|MODES|FORM\s+FACTORS?|PARAMETERS?|CONSTANTS?|RATIO|RATIOS|'
    r'ADMIXTURE|MIXING|FACTORS?))\s*$',
    caseSensitive: false,
  ).firstMatch(original);
  if (suffix != null) {
    final body = segmentPdgText(suffix.group(1)!);
    return [...body, PdgTextSegment.plain(suffix.group(2)!)];
  }
  final quantum = quantumLineToLatex(original);
  if (quantum != null) return [PdgTextSegment.math(quantum)];
  // PDG descriptions sometimes preserve spaces inside a particle name
  // (`T_c c cbar cbar(6600)`). Treat a complete name as one math unit before
  // the generic token scanner can split it into `T_c` + prose.
  if (original.contains(RegExp(r'\s')) &&
      original.contains(RegExp(r'[0-9_^()]')) &&
      RegExp(r'\([0-9][^()]*\)[+-]?\d*$').hasMatch(original) &&
      !RegExp(
        r'\b(MASS|MEAN|LIFE|MODE|WIDTH|RATIO|ADMIXTURE|MIXING|PARAMETER|'
        r'PARAMETERS|CONSTANT|CONSTANTS|FACTOR|FACTORS)\b',
        caseSensitive: false,
      ).hasMatch(original)) {
    final wholeName = particleNameToLatex(original);
    if (wholeName != null) return [PdgTextSegment.math(wholeName)];
  }
  final cached = _segmentCache[original];
  if (cached != null) return cached;
  final result = _segmentPdgTextUncached(original);
  if (_segmentCache.length >= _segmentCacheLimit) {
    _segmentCache.remove(_segmentCache.keys.first);
  }
  _segmentCache[original] = result;
  return result;
}

const int _segmentCacheLimit = 300;
final Map<String, List<PdgTextSegment>> _segmentCache = {};

List<PdgTextSegment> _segmentPdgTextUncached(String original) {
  var source = original;
  // CKM matrix elements use a two-letter subscript, not a mass label.
  if (!source.contains(r'$')) {
    for (final pair in const [
      'cb',
      'ub',
      'cd',
      'cs',
      'td',
      'ts',
      'tb',
      'ud',
      'us',
    ]) {
      source = source.replaceAll('V($pair)', r'$V_{' + pair + r'}$');
    }
  }
  const titleGreek = {
    'μ': 'mu',
    'ρ': 'rho',
    'ξ': 'xi',
    'δ': 'delta',
    'α': 'alpha',
    'β': 'beta',
    'γ': 'gamma',
    'τ': 'tau',
    'π': 'pi',
    'σ': 'sigma',
    'λ': 'lambda',
    'ω': 'omega',
    'φ': 'phi',
    'χ': 'chi',
    'η': 'eta',
  };
  // Only normalize Greek outside explicit `$...$` math; that path already
  // accepts TeX commands.
  final dollarParts = source.split(RegExp(r'(?=\$)'));
  source = [
    for (final part in dollarParts)
      part.startsWith(r'$') && part.length > 1
          ? part
          : part.replaceAllMapped(
              RegExp('[${titleGreek.keys.join()}]'),
              (match) => titleGreek[match.group(0)]!,
            ),
  ].join();
  source = source.replaceAllMapped(
    RegExp(r'([_^])mathit\s+([A-Za-z]+)'),
    (match) => '${match.group(1)}${match.group(2)}',
  );
  source = source.replaceAll(RegExp(r'\\mathit\s+'), r'\mathit');

  final segments = <PdgTextSegment>[];
  var plainStart = 0;
  var index = 0;

  void flushPlain(int end) {
    if (end > plainStart) {
      _addPlain(segments, source.substring(plainStart, end));
    }
  }

  while (index < source.length) {
    if (source[index] == r'$') {
      final end = source.indexOf(r'$', index + 1);
      if (end > index) {
        flushPlain(index);
        var body = source.substring(index + 1, end);
        // MathML/Crossref occasionally leaves a bare `\alpha_-`; the sign is
        // a subscript, not a binary minus.
        body = body.replaceAllMapped(
          RegExp(r'(\\(?:alpha|beta|gamma|mu|tau|Lambda))_([+-])$'),
          (match) => '${match.group(1)}_{${match.group(2)}}',
        );
        body = body.replaceAll(RegExp(r'\^\{\s*\+\s*-\s*\}'), r'^{\pm}');
        body = body.replaceAll(RegExp(r'\^\{\s*-\s*\+\s*\}'), r'^{\mp}');
        if (_looksLikeSafeLatex(body)) {
          segments.add(PdgTextSegment.math(body));
        } else {
          _addPlain(segments, source.substring(index, end + 1));
        }
        index = end + 1;
        plainStart = index;
        continue;
      }
    }
    final arrowLength = _arrowLength(source, index);
    if (arrowLength > 0) {
      flushPlain(index);
      segments.add(const PdgTextSegment.math(r'\longrightarrow'));
      index += arrowLength;
      plainStart = index;
      continue;
    }
    if (_canStartExpression(source[index])) {
      final end = _scanExpression(source, index);
      if (end > index) {
        final candidate = source.substring(index, end);
        if (_isCollaborationName(candidate)) {
          flushPlain(index);
          _addPlain(segments, candidate);
          index = end;
          plainStart = index;
          continue;
        }
        final prepared = _prepareCandidate(candidate);
        String? latex;
        if (_hasMathMarker(prepared)) {
          latex = convertPdgExpression(prepared);
          // Never paper over a parser rejection of a scripted expression with
          // the narrower token converter; that is how invalid double
          // superscripts such as pi**0+ used to slip through.
          if (latex == null &&
              !prepared.contains('**') &&
              !prepared.contains(r'\')) {
            latex = textTokenToLatex(prepared);
          }
        } else {
          latex = textTokenToLatex(prepared);
        }
        if (latex != null && _looksLikeSafeLatex(latex)) {
          flushPlain(index);
          segments.add(PdgTextSegment.math(latex));
          index = end;
          plainStart = index;
          continue;
        }
        // If the whole expression has no `**` script, fall back to complete
        // name tokens inside it (e.g. G(Z --> pi0 gamma)/G(total)). Tokens are
        // validated as whole units, so this cannot produce the broken
        // half-superscript that the whole-expression rule prevents.
        flushPlain(index);
        if (!candidate.contains('**') &&
            (_emitTopLevelSplit(segments, candidate) ||
                _emitTokenFallback(segments, candidate))) {
          index = end;
          plainStart = index;
          continue;
        }
        _addPlain(segments, candidate);
        index = end;
        plainStart = index;
        continue;
      }
    }
    index++;
  }
  flushPlain(source.length);
  return _withMeasurements(segments);
}

/// Measurement values such as `185.54+-0.06` and `-0.71+-0.96+-0.19` are
/// written with ASCII `+-` in the database. Typesetting them as `\pm` keeps
/// the uncertainty readable instead of leaving an operator that looks like a
/// typo. Only plain runs are touched, so an already converted expression is
/// never rewritten.
final RegExp _measurementPattern = RegExp(
  r'(?<![\w.])-?\d+(?:\.\d+)?(?:\s*(?:\+-|±)\s*\d+(?:\.\d+)?)+(?![\w.])',
);

List<PdgTextSegment> _withMeasurements(List<PdgTextSegment> segments) {
  var changed = false;
  final result = <PdgTextSegment>[];
  for (final segment in segments) {
    final text = segment.text;
    if (text == null) {
      result.add(segment);
      continue;
    }
    var cursor = 0;
    for (final match in _measurementPattern.allMatches(text)) {
      changed = true;
      if (match.start > cursor) {
        result.add(PdgTextSegment.plain(text.substring(cursor, match.start)));
      }
      result.add(PdgTextSegment.math(_measurementLatex(match.group(0)!)));
      cursor = match.end;
    }
    if (cursor < text.length) {
      result.add(PdgTextSegment.plain(text.substring(cursor)));
    }
  }
  return changed ? result : segments;
}

String _measurementLatex(String source) {
  final normalized = source.replaceAll('±', '+-').replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final parts = normalized.split('+-');
  final buffer = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    buffer.write(r' \pm ');
    buffer.write(parts[i]);
  }
  return buffer.toString();
}

/// Converts complete subexpressions separated by top-level operators. This is
/// what turns `mass(pi+-)-mass(pi0)` into two typeset calls without touching
/// the hyphen in a detector name such as CLEO-c (both halves simply fail to
/// convert and are emitted verbatim).
bool _emitTopLevelSplit(List<PdgTextSegment> segments, String candidate) {
  final parts = <PdgTextSegment>[];
  var converted = false;
  var start = 0;
  var depth = 0;

  void addPart(int end) {
    if (end <= start) return;
    final part = candidate.substring(start, end);
    if (part.trim().isEmpty) {
      _addPlain(parts, part);
      return;
    }
    String? latex;
    if (_hasMathMarker(part)) latex = convertPdgExpression(part);
    latex ??= textTokenToLatex(part);
    if (latex != null && _looksLikeSafeLatex(latex)) {
      parts.add(PdgTextSegment.math(latex));
      converted = true;
    } else if (!_emitTokenFallback(parts, part)) {
      _addPlain(parts, part);
    } else {
      converted = true;
    }
  }

  for (var i = 0; i < candidate.length; i++) {
    final char = candidate[i];
    if (char == '(' || char == '[' || char == '{') depth++;
    if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth < 0) return false;
    }
    if (depth != 0) continue;
    final arrow = _arrowLength(candidate, i);
    if (arrow > 0) {
      addPart(i);
      parts.add(const PdgTextSegment.math(r'\longrightarrow'));
      converted = true;
      i += arrow - 1;
      start = i + 1;
      continue;
    }
    if ('+-/*='.contains(char)) {
      addPart(i);
      _addPlain(parts, char);
      start = i + 1;
    }
  }
  addPart(candidate.length);
  if (!converted) return false;
  for (final part in parts) {
    if (part.text != null) {
      _addPlain(segments, part.text!);
    } else {
      segments.add(part);
    }
  }
  return true;
}

final RegExp _fallbackTokenPattern = RegExp(
  r"[A-Za-z]+(?:bar)?(?:[0-9][A-Za-z])?(?:\*(?=\())*(?:(?:_|\^|\*\*)(?:\{\{[^{}]*\}\}|\{[^{}]*\}|[A-Za-z0-9+\-*'′]+))*(?:\([^()\s]*\))?(?:\^?[+\-0]{1,2})?",
);

/// Emits complete name tokens from a failed composite expression. Returns
/// `false` when nothing was converted, so the caller can keep one plain span.
bool _emitTokenFallback(List<PdgTextSegment> segments, String candidate) {
  final parts = <PdgTextSegment>[];
  var cursor = 0;
  var converted = false;
  void flush(int end) {
    if (end > cursor) _addPlain(parts, candidate.substring(cursor, end));
  }

  final combined = RegExp('(?:-->|->|→)|${_fallbackTokenPattern.pattern}');
  for (final match in combined.allMatches(candidate)) {
    if (!_fallbackBoundary(candidate, match.start, match.end)) continue;
    flush(match.start);
    final token = match.group(0)!;
    if (token == '-->' || token == '->' || token == '→') {
      parts.add(const PdgTextSegment.math(r'\longrightarrow'));
      converted = true;
      cursor = match.end;
      continue;
    }
    final latex = textTokenToLatex(token);
    if (latex != null && _looksLikeSafeLatex(latex)) {
      parts.add(PdgTextSegment.math(latex));
      converted = true;
    } else {
      _addPlain(parts, token);
    }
    cursor = match.end;
  }
  flush(candidate.length);
  if (!converted) return false;
  for (final part in parts) {
    if (part.text != null) {
      _addPlain(segments, part.text!);
    } else {
      segments.add(part);
    }
  }
  return true;
}

bool _fallbackBoundary(String text, int start, int end) {
  if (start > 0) {
    final previous = text.codeUnitAt(start - 1);
    if ((previous >= 65 && previous <= 90) ||
        (previous >= 97 && previous <= 122) ||
        previous == 45) {
      return false;
    }
  }
  if (end < text.length) {
    final next = text.codeUnitAt(end);
    if ((next >= 65 && next <= 90) || (next >= 97 && next <= 122)) {
      return false;
    }
  }
  return true;
}

void _addPlain(List<PdgTextSegment> segments, String text) {
  if (text.isEmpty) return;
  if (segments.isNotEmpty && segments.last.text != null) {
    final merged = '${segments.last.text}$text';
    segments[segments.length - 1] = PdgTextSegment.plain(merged);
  } else {
    segments.add(PdgTextSegment.plain(text));
  }
}

bool _canStartExpression(String char) {
  return RegExp(r'[A-Za-z0-9]').hasMatch(char) ||
      char == r'\' ||
      char == '(' ||
      char == '[';
}

int _arrowLength(String text, int index) {
  if (text.startsWith('-->', index)) return 3;
  if (text.startsWith('->', index)) return 2;
  if (text.startsWith('→', index)) return 1;
  return 0;
}

int _scanExpression(String text, int start) {
  var depth = 0;
  var index = start;
  while (index < text.length) {
    final char = text[index];
    if (char == r'$') break;
    if (depth == 0) {
      if (RegExp(r'\s').hasMatch(char)) break;
      if (',;:!?='.contains(char)) break;
      if (char == '|' || char == '<' || char == '>') break;
      if (char == '.' &&
          !(index > start &&
              index + 1 < text.length &&
              RegExp(r'[0-9]').hasMatch(text[index - 1]) &&
              RegExp(r'[0-9]').hasMatch(text[index + 1]))) {
        break;
      }
      if (_arrowLength(text, index) > 0) break;
    }
    if (char == '(' || char == '[' || char == '{') depth++;
    if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) break;
      depth--;
    }
    index++;
  }
  return index;
}

String _prepareCandidate(String candidate) {
  return candidate.replaceAll(RegExp(r'\\mathit\s*'), '');
}

bool _hasMathMarker(String candidate) {
  return candidate.contains('_') ||
      candidate.contains('^') ||
      candidate.contains('**') ||
      candidate.contains(r'\') ||
      candidate.contains('(') ||
      candidate.contains('[');
}

bool _looksLikeSafeLatex(String latex) {
  if (latex.isEmpty) return false;
  if (latex.contains(r'\mathit')) return false;
  var depth = 0;
  for (var i = 0; i < latex.length; i++) {
    final char = latex[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth < 0) return false;
    }
    // A raw PDG `**` exponent marker must not survive outside a LaTeX group.
    // Inside braces, `**` is a legitimate pair of star superscripts (D^{**0}).
    if (depth == 0 &&
        char == '*' &&
        i + 1 < latex.length &&
        latex[i + 1] == '*') {
      return false;
    }
  }
  return depth == 0;
}

bool _isCollaborationName(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(' ', '');
  return _collaborationNames.contains(normalized);
}

/// Common experiment/collaboration names in PDG text. These are deliberately
/// kept literal even when they contain digits or a hyphen that could otherwise
/// look like a charge. D0 is intentionally not listed because it is also the
/// D0 meson; the parser handles that context separately.
const Set<String> _collaborationNames = {
  'cleo',
  'cleo-c',
  'cleoiii',
  'cleo-iii',
  'lhc',
  'lhcb',
  'atlas',
  'cms',
  'alice',
  'cdf',
  'd0collaboration',
  'ua1',
  'ua2',
  'babar',
  'belle',
  'belleii',
  'bes',
  'besiii',
  'bes-iii',
  'aleph',
  'delphi',
  'opal',
  'l3',
  'sld',
  'lep',
  'slc',
  'tevatron',
  'fermilab',
  'cern',
  'desy',
  'slac',
  'kek',
  'j-parc',
  'rhic',
  'hera',
  'zeus',
  'h1',
  'kloe',
  'kloe-2',
  'klev',
  'ktev',
  'na31',
  'na48',
  'na62',
  'meg',
  'megii',
  'pep',
  'pep-ii',
  'cesr',
  'cesr-c',
  'bepc',
  'bepcii',
  'kekb',
  'superkekb',
  'snd',
  'crystalball',
  'marki',
  'markii',
  'markiii',
  'pluto',
  'tasso',
  'jade',
  'mac',
  'tpc',
  'cush',
  'cusb',
  'argus',
  'nutev',
  'ccfr',
  'cdhs',
  'gargamelle',
  'bebc',
  'charm',
  'charmii',
  'charm-ii',
};

const Set<String> _bareNameWords = {
  'W',
  'Z',
  'H',
  'G',
  'K',
  'D',
  'B',
  'N',
  'p',
  'n',
  'e',
  'g',
  'pi',
  'eta',
  'rho',
  'omega',
  'phi',
  'chi',
  'psi',
  'tau',
  'mu',
  'nu',
  'gamma',
  'Gamma',
  'Lambda',
  'Sigma',
  'Xi',
  'Omega',
  'Delta',
  'Upsilon',
  'theta',
  'lambda',
  'kappa',
  'xi',
  'delta',
  'sigma',
  'chitilde',
  'nutilde',
  'lambdatilde',
  'kappatilde',
  'x',
  'y',
};

const Set<String> _symbolWords = {
  'pi',
  'Pi',
  'K',
  'D',
  'B',
  'p',
  'n',
  'e',
  'mu',
  'tau',
  'nu',
  'gamma',
  'g',
  'W',
  'Z',
  'H',
  'G',
  'N',
  'X',
  'Y',
  'f',
  'a',
  'h',
  'm',
  'Lambda',
  'Sigma',
  'Xi',
  'Omega',
  'Delta',
  'Upsilon',
  'psi',
  'phi',
  'rho',
  'eta',
  'omega',
  'chi',
  'theta',
  'alpha',
  'beta',
  'lambda',
  'sigma',
  'xi',
  'delta',
  'kappa',
  'chitilde',
  'nutilde',
  'lambdatilde',
  'kappatilde',
  'x',
  'y',
};

bool _isSymbolWord(String token) => _symbolWords.contains(token);

bool _isAntiSymbol(String base) {
  if (!base.endsWith('bar') || base.length <= 3) return false;
  return _symbolWords.contains(base.substring(0, base.length - 3));
}
