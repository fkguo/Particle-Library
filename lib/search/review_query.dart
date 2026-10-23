import 'review_notation.dart';

/// A parsed review query.  The FTS5 expression is built here, never from raw
/// user text, and the rank words are the canonical words used for title and
/// heading scoring.
class ReviewQuery {
  const ReviewQuery._({
    this.expression,
    this.rankWords = const [],
    this.prefixWord,
    this.exactWords = const {},
    this.notice,
  });

  final String? expression;
  final List<String> rankWords;
  final String? prefixWord;
  final Set<String> exactWords;
  final String? notice;

  bool get isEmpty => expression == null;

  static const String noticeEmpty = 'empty';
  static const String noticeQuote = 'unclosedQuote';
  static const String noticeTooLong = 'tooLong';

  static const Set<String> _reserved = {'or', 'and', 'not', 'near'};

  static ReviewQuery parse(String raw) {
    final source = raw.trim();
    if (source.isEmpty) {
      return const ReviewQuery._(notice: noticeEmpty);
    }
    if (source.length > 256) {
      return const ReviewQuery._(notice: noticeTooLong);
    }

    var notice = '"'.allMatches(source).length.isOdd ? noticeQuote : null;

    final phrases = <String>[];
    var rest = source.replaceAllMapped(RegExp(r'"([^"]*)"'), (match) {
      phrases.add(match[1]!);
      return ' ';
    });
    rest = rest.replaceAll('"', ' ');

    var prefix = false;
    final trimmedRight = rest.trimRight();
    if (trimmedRight.endsWith('*')) {
      prefix = true;
      rest = trimmedRight.substring(0, trimmedRight.length - 1);
    }
    final rawTokens = prefix
        ? ReviewNotation.allTokens(rest)
        : const <String>[];
    final starToken = prefix && rawTokens.isNotEmpty ? rawTokens.last : null;
    final canPrefix =
        starToken != null &&
        starToken.length >= 3 &&
        !_reserved.contains(starToken) &&
        !ReviewNotation.aliases.containsKey(starToken);

    final parts = <String>[];
    final rankWords = <String>[];
    final exactWords = <String>{};

    for (final phrase in phrases) {
      final words = ReviewNotation.tokens(phrase);
      if (words.isEmpty) continue;
      if (words.contains('cg')) {
        final original = words.join(' ');
        final expanded = words
            .map((word) => word == 'cg' ? 'clebsch gordan' : word)
            .join(' ');
        parts.add('("$original" OR "$expanded")');
        rankWords.addAll(expanded.split(' '));
        exactWords.addAll(expanded.split(' '));
      } else {
        parts.add('"${words.join(' ')}"');
        rankWords.addAll(words);
        exactWords.addAll(words);
      }
    }

    final tokens = ReviewNotation.tokens(rest)
        .where((token) => !_reserved.contains(token))
        .toList(growable: false);
    var lastPartIsToken = false;
    var prefixApplied = false;
    String? lastToken;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final alias = ReviewNotation.aliases[token];
      if (alias != null) {
        final alternatives = alias.map((value) => '"$value"').join(' OR ');
        parts.add('($alternatives)');
        final expansion = alias.length > 1 ? alias.last : alias.first;
        rankWords.addAll(expansion.split(' '));
        exactWords.addAll(expansion.split(' '));
        lastPartIsToken = false;
      } else {
        parts.add('"$token"');
        rankWords.add(token);
        exactWords.add(token);
        lastPartIsToken = true;
        lastToken = token;
      }
    }

    if (canPrefix && lastPartIsToken && lastToken == starToken) {
      parts[parts.length - 1] = '$lastToken*';
      prefixApplied = true;
      // The prefixed occurrence itself is not an exact-word requirement; only
      // an earlier, non-prefixed occurrence of the same word is.
      final prior = tokens
          .take(tokens.length - 1)
          .where((token) => token == lastToken)
          .length;
      if (prior == 0) exactWords.remove(lastToken);
    }

    if (parts.isEmpty) {
      return ReviewQuery._(notice: notice ?? noticeEmpty);
    }
    return ReviewQuery._(
      expression: parts.join(' AND '),
      rankWords: _unique(rankWords),
      prefixWord: prefixApplied ? lastToken : null,
      exactWords: exactWords,
      notice: notice,
    );
  }

  static List<String> _unique(List<String> words) {
    final seen = <String>{};
    return [
      for (final word in words)
        if (word.isNotEmpty && seen.add(word)) word,
    ];
  }
}
