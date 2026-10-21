import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_theme.dart';
import 'description_text.dart';

Future<void> copyText(
  BuildContext context,
  String text, {
  String? message,
}) async {
  final strings = AppScope.of(context).strings;
  if (text.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.commonNothingToCopy)));
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${strings.commonCopyFailed}: ${errorText(error, strings)}',
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message ?? strings.commonCopied),
      duration: const Duration(seconds: 2),
    ),
  );
}

class CopyButton extends StatelessWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.label,
    this.icon = Icons.copy_outlined,
    this.compact = false,
  });

  final String text;
  final String? label;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label ?? AppScope.of(context).strings.commonCopy;
    if (compact) {
      return IconButton(
        tooltip: effectiveLabel,
        icon: Icon(icon, size: 18),
        onPressed: () => copyText(context, text),
      );
    }
    if (label != null) {
      return TextButton.icon(
        onPressed: () => copyText(context, text),
        icon: Icon(icon, size: 17),
        label: Text(label!),
      );
    }
    return IconButton(
      tooltip: effectiveLabel,
      icon: Icon(icon, size: 18),
      onPressed: () => copyText(context, text),
    );
  }
}

class CopyIconButton extends StatelessWidget {
  const CopyIconButton({super.key, required this.text, this.tooltip});

  final String text;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip ?? AppScope.of(context).strings.commonCopy,
      icon: const Icon(Icons.copy_outlined, size: 18),
      onPressed: () => copyText(context, text),
    );
  }
}

class MetaChip extends StatelessWidget {
  const MetaChip(
    this.label, {
    super.key,
    this.icon,
    this.tone = BadgeTone.neutral,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final BadgeTone tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      BadgeTone.neutral => palette.textSecondary,
      BadgeTone.info => palette.primary,
      BadgeTone.accent => palette.accent,
      BadgeTone.warning => palette.warning,
      BadgeTone.error => palette.error,
      BadgeTone.success => palette.accent,
    };
    final background = switch (tone) {
      BadgeTone.neutral => palette.surfaceAlt,
      BadgeTone.info => palette.primary.withValues(alpha: 0.09),
      BadgeTone.accent => palette.accent.withValues(alpha: 0.09),
      BadgeTone.warning => palette.warning.withValues(alpha: 0.10),
      BadgeTone.error => palette.error.withValues(alpha: 0.09),
      BadgeTone.success => palette.accent.withValues(alpha: 0.09),
    };
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
    Widget result = content;
    if (onTap != null) {
      result = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: content,
        ),
      );
    }
    if (tooltip == null) return result;
    return Tooltip(message: tooltip!, child: result);
  }
}

enum BadgeTone { neutral, info, accent, warning, error, success }

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.all(Insets.l),
  });

  final Widget child;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.resolve(TextDirection.ltr).left,
                padding.resolve(TextDirection.ltr).top,
                padding.resolve(TextDirection.ltr).right,
                subtitle == null ? Insets.s : Insets.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: Insets.s),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.resolve(TextDirection.ltr).left,
              title == null
                  ? padding.resolve(TextDirection.ltr).top
                  : Insets.xs,
              padding.resolve(TextDirection.ltr).right,
              padding.resolve(TextDirection.ltr).bottom,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.wrap = false,
  });

  final String label;
  final String value;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: style?.copyWith(
                color: palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: style,
              maxLines: wrap ? null : 3,
            ),
          ),
        ],
      ),
    );
  }
}

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({super.key, required this.entries, this.onOpen});

  final List<dynamic> entries;
  final void Function(String pdgid)? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall;
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final pdgid = entry.pdgid as String;
      final description = entry.description as String;
      children.add(
        InkWell(
          onTap: i == entries.length - 1 ? null : () => onOpen?.call(pdgid),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: DescriptionText(
              description.isEmpty ? pdgid : description,
              maxLines: 1,
              style: style?.copyWith(
                color: i == entries.length - 1
                    ? palette.textSecondary
                    : palette.primary,
              ),
            ),
          ),
        ),
      );
      if (i != entries.length - 1) {
        children.add(
          Icon(Icons.chevron_right, size: 14, color: palette.textSecondary),
        );
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Insets.xl,
        horizontal: Insets.l,
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 28,
            color: palette.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: Insets.s),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: Insets.m), action!],
        ],
      ),
    );
  }
}
