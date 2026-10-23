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
    final source = raw.trim().replaceAll('“', '"').replaceAll('”', '"');
    if (source.isEmpty) {
      return const ReviewQuery._(notice: noticeEmpty);
    }
    if (source.length > 256) {
      return const ReviewQuery._(notice: noticeTooLong);
    }

    var notice = '"'.allMatches(source).length.isOdd ? noticeQuote : null;

    // Resolve the star against the RAW trailing item before quote extraction
    // or lossy normalization; otherwise `cleb μ*`, `cleb 中文*` and
    // `cleb "x"*` would silently move the star to `cleb`.
    var starOnQuote = false;
    String? starOwner;
    var body = source;
    if (body.endsWith('*')) {
      body = body.substring(0, body.length - 1).trimRight();
      if (body.endsWith('"') || body.endsWith('”')) {
        starOnQuote = true;
      } else {
        final match = RegExp(r'(\S+)$').firstMatch(body);
        starOwner = match?.group(1);
      }
    }
    final ownerTokens = starOwner == null
        ? const <String>[]
        : ReviewNotation.allTokens(starOwner);
    final owner = ownerTokens.length == 1 ? ownerTokens.single : null;
    final canPrefix =
        !starOnQuote &&
        owner != null &&
        owner.length >= 3 &&
        !_reserved.contains(owner) &&
        !ReviewNotation.aliases.containsKey(owner);

    final phrases = <String>[];
    var rest = body.replaceAllMapped(RegExp(r'"([^"]*)"'), (match) {
      phrases.add(match[1]!);
      return ' ';
    });
    rest = rest.replaceAll('"', ' ');

    final parts = <String>[];
    final rankWords = <String>[];
    final exactGroups = <List<String>>[];

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
        exactGroups.add(expanded.split(' '));
      } else {
        parts.add('"${words.join(' ')}"');
        rankWords.addAll(words);
        exactGroups.add(words);
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
        exactGroups.add(expansion.split(' '));
        lastPartIsToken = false;
      } else {
        parts.add('"$token"');
        rankWords.add(token);
        exactGroups.add([token]);
        lastPartIsToken = true;
        lastToken = token;
      }
    }

    if (canPrefix && lastPartIsToken && lastToken == owner) {
      parts[parts.length - 1] = '$lastToken*';
      prefixApplied = true;
    }
    final exactWords = <String>{for (final group in exactGroups) ...group};
    if (prefixApplied) {
      // The prefixed occurrence itself is not an exact-word requirement; only
      // an earlier phrase/token (including an alias expansion) of the same word
      // is.  This keeps `CG gordan*` exact without breaking bare `cleb*`.
      final prior = <String>{
        for (final group in exactGroups.take(exactGroups.length - 1)) ...group,
      };
      if (!prior.contains(lastToken)) exactWords.remove(lastToken);
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
