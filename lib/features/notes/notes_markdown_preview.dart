import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../app/app_theme.dart';

/// Small, dependency-free Markdown preview used by the notes editor.
///
/// It supports the subset the notes UI advertises: headings, paragraphs,
/// bullets, numbered lists, blockquotes, fenced code, emphasis, inline code,
/// links (label only) and `$...$` math. It is a preview, not a renderer for
/// arbitrary HTML.
class NotesMarkdownPreview extends StatelessWidget {
  const NotesMarkdownPreview({
    super.key,
    required this.markdown,
    this.padding = const EdgeInsets.all(12),
    this.emptyHint,
    this.onOpenLink,
    this.onHoverLink,
    this.onLeaveLink,
  });

  final String markdown;
  final EdgeInsetsGeometry padding;
  final String? emptyHint;
  final ValueChanged<String>? onOpenLink;
  final void Function(String target, Offset globalPosition)? onHoverLink;
  final VoidCallback? onLeaveLink;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final blocks = _parseBlocks(markdown);
    if (blocks.isEmpty) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            emptyHint ?? '',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      padding: padding,
      children: [for (final block in blocks) _buildBlock(context, block)],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block) {
    final palette = context.palette;
    final theme = Theme.of(context);
    switch (block.kind) {
      case _BlockKind.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.divider),
          ),
          child: SelectableText(
            block.text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: AppFonts.monospaceFamily,
              height: 1.45,
            ),
          ),
        );
      case _BlockKind.heading:
        final style = switch (block.level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          3 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(context, block.text, style)),
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case _BlockKind.quote:
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.accent, width: 3)),
            color: palette.surfaceAlt,
          ),
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(context, block.text, null)),
          ),
        );
      case _BlockKind.bullet:
      case _BlockKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  block.kind == _BlockKind.bullet ? '•' : block.marker,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(children: _inlineSpans(context, block.text, null)),
                ),
              ),
            ],
          ),
        );
      case _BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText.rich(
            TextSpan(children: _inlineSpans(context, block.text, null)),
          ),
        );
    }
  }

  List<InlineSpan> _inlineSpans(
    BuildContext context,
    String text,
    TextStyle? baseStyle,
  ) {
    final style = baseStyle ?? Theme.of(context).textTheme.bodyLarge;
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\$[^$\n]+\$|\*\*[^*]+\*\*|\*[^*]+\*|__[^_]+__|_[^_]+_|`[^`]+`|\[[^\]]+\]\([^)]*\))',
    );
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith(r'$') && token.endsWith(r'$') && token.length > 2) {
        final latex = token.substring(1, token.length - 1).trim();
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Math.tex(
              latex,
              mathStyle: MathStyle.text,
              textStyle: style,
              onErrorFallback: (_) => Text(token, style: style),
            ),
          ),
        );
      } else if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('__') && token.endsWith('__')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('_') && token.endsWith('_')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: AppFonts.monospaceFamily,
              backgroundColor: context.palette.surfaceAlt,
            ),
          ),
        );
      } else {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]*)\)$').firstMatch(token);
        if (link != null) {
          final label = link.group(1) ?? '';
          final target = link.group(2) ?? '';
          final linkStyle = TextStyle(
            color: context.palette.accent,
            decoration: TextDecoration.underline,
          );
          if (onOpenLink != null && target.isNotEmpty) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (event) => onHoverLink?.call(target, event.position),
                  onExit: (_) => onLeaveLink?.call(),
                  child: GestureDetector(
                    onTap: () => onOpenLink!(target),
                    child: Text(label, style: linkStyle),
                  ),
                ),
              ),
            );
          } else {
            spans.add(TextSpan(text: label, style: linkStyle));
          }
        } else {
          spans.add(TextSpan(text: token));
        }
      }
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return spans;
  }

  List<_Block> _parseBlocks(String source) {
    final lines = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final blocks = <_Block>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        final fence = trimmed.substring(0, 3);
        final buffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith(fence)) {
          buffer.writeln(lines[i]);
          i++;
        }
        if (i < lines.length) i++;
        blocks.add(_Block(_BlockKind.code, buffer.toString().trimRight()));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        blocks.add(
          _Block(
            _BlockKind.heading,
            heading.group(2)!.trim(),
            level: heading.group(1)!.length,
          ),
        );
        i++;
        continue;
      }
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        blocks.add(_Block(_BlockKind.bullet, bullet.group(1)!.trim()));
        i++;
        continue;
      }
      final numbered = RegExp(r'^(\d+[.)])\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        blocks.add(
          _Block(
            _BlockKind.numbered,
            numbered.group(2)!.trim(),
            marker: numbered.group(1)!,
          ),
        );
        i++;
        continue;
      }
      if (trimmed.startsWith('>')) {
        final buffer = StringBuffer();
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          final content = lines[i].trimLeft().substring(1).trimLeft();
          if (buffer.isNotEmpty) buffer.write(' ');
          buffer.write(content);
          i++;
        }
        blocks.add(_Block(_BlockKind.quote, buffer.toString()));
        continue;
      }
      // Paragraph: consume until a blank line or another block construct.
      final buffer = StringBuffer();
      while (i < lines.length) {
        final current = lines[i];
        final t = current.trim();
        if (t.isEmpty ||
            t.startsWith('```') ||
            t.startsWith('~~~') ||
            RegExp(r'^(#{1,6})\s+').hasMatch(t) ||
            RegExp(r'^[-*+]\s+').hasMatch(t) ||
            RegExp(r'^\d+[.)]\s+').hasMatch(t) ||
            t.startsWith('>')) {
          break;
        }
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(t);
        i++;
      }
      if (buffer.isNotEmpty) {
        blocks.add(_Block(_BlockKind.paragraph, buffer.toString()));
      } else {
        i++;
      }
    }
    return blocks;
  }
}

enum _BlockKind { heading, paragraph, bullet, numbered, quote, code }

class _Block {
  const _Block(this.kind, this.text, {this.level = 1, this.marker = ''});

  final _BlockKind kind;
  final String text;
  final int level;
  final String marker;
}
