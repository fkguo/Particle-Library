/// Canonical tokens shared by review indexing, query parsing and title
/// matching.  The rules mirror `assets/review_search_rules_v1.json`; the
/// golden vectors in that file are asserted by the Dart tests.
library;

class ReviewNotation {
  const ReviewNotation._();

  /// Tokens that get a phrase alternative.  Keep this list deliberately small:
  /// an ambiguous abbreviation is worse than a missed expansion.
  static const Map<String, List<String>> aliases = {
    'cg': ['cg', 'clebsch gordan'],
    'hvp': ['hvp', 'hadronic vacuum polarization'],
    'hlbl': ['hlbl', 'hadronic light by light'],
    'qcd': ['qcd', 'quantum chromodynamics'],
    'gminus2': ['gminus2', 'anomalous magnetic moment'],
    'electronpositronpair': ['electronpositronpair', 'electron positron'],
  };

  static const Map<String, String> _ligatures = {
    'ﬀ': 'ff',
    'ﬁ': 'fi',
    'ﬂ': 'fl',
    'ﬃ': 'ffi',
    'ﬄ': 'ffl',
  };

  /// Normalize notation *before* tokenization.  The order matters: primes,
  /// superscripts and charge combinations must be recognized before generic
  /// punctuation is removed, otherwise `W′` silently becomes `w`.
  static String normalize(String input) {
    var text = input;
    _ligatures.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    text = text.replaceAll(
      RegExp(r'g\s*[-−]\s*2', caseSensitive: false),
      ' gminus2 ',
    );
    text = text.replaceAll(
      RegExp(r'e\s*[+⁺]\s*e\s*[-−⁻]'),
      ' electronpositronpair ',
    );
    text = text.replaceAllMapped(
      RegExp(r"([WZ])\s*['′]", caseSensitive: false),
      (match) => ' ${match[1]!.toLowerCase()}prime ',
    );
    text = text.replaceAll(RegExp(r'B\s*[⁰0]'), ' bzero ');
    text = text.toLowerCase();
    text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return text.trim();
  }

  static List<String> tokens(String input) {
    return normalize(input)
        .split(' ')
        .where((token) => token.isNotEmpty)
        .where((token) => token.length > 1 || aliases.containsKey(token))
        .toList(growable: false);
  }

  /// Title matching expands the abbreviations used in the review directory.
  /// This is only for titles; body text keeps the original abbreviations.
  static String titleKey(String input) {
    var text = input;
    text = text.replaceAll(
      RegExp(r'\bcoeff\.', caseSensitive: false),
      'coefficients',
    );
    text = text.replaceAll(
      RegExp(r'\bsph\.', caseSensitive: false),
      'spherical',
    );
    return normalize(text);
  }

  static bool titleMatches(String title, List<String> words) {
    final key = titleKey(title);
    if (words.isEmpty) return false;
    return words.every(key.contains);
  }

  static bool titleHasPhrase(String title, List<String> words) {
    if (words.isEmpty) return false;
    return titleKey(title).contains(words.join(' '));
  }
}
