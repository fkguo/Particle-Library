import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app_theme.dart';

/// One destination in a long entity page.
///
/// Use either [target] (scroll to the key) or [onTap] (for tab switches that
/// need to change state before scrolling).
class PageOutlineItem {
  const PageOutlineItem({
    required this.label,
    this.target,
    this.onTap,
    this.icon,
  });

  final String label;
  final GlobalKey? target;
  final VoidCallback? onTap;
  final IconData? icon;
}

/// Compact, horizontally scrollable table of contents for a long page.
///
/// It is deliberately part of the page body rather than a permanent extra
/// rail: wide pages already have a context sidebar, and a fixed third column
/// would squeeze the actual data.
/// Collapsible left-hand table of contents used by long detail pages.
///
/// The right context sidebar already exists on those pages; this rail is
/// independently collapsible and never takes space when collapsed to its
/// narrow handle. On narrow windows it becomes a small overlay button so the
/// content still gets the full width.
/// Scrolls the nearest page scrollable so [key] is just below the top edge.
///
/// `Scrollable.ensureVisible` can pick a nested scrollable or apply a slightly
/// different alignment. Computing the reveal offset against the actual viewport
/// keeps the section heading at a predictable position.
void scrollToOutlineTarget(GlobalKey key, {double alignment = 0.0}) {
  final targetContext = key.currentContext;
  if (targetContext == null) return;
  final renderObject = targetContext.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return;
  final scrollable = Scrollable.maybeOf(targetContext);
  final position = scrollable?.position;
  if (position == null || !position.hasContentDimensions) {
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: alignment,
    );
    return;
  }
  try {
    final viewport = RenderAbstractViewport.of(renderObject);
    final offset = viewport.getOffsetToReveal(renderObject, alignment).offset;
    final clamped = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  } catch (_) {
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: alignment,
    );
  }
}

/// Shows the compact, narrow-window table of contents as a modal sheet.
Future<void> showPageOutlineSheet(
  BuildContext context, {
  required String label,
  required List<PageOutlineItem> items,
  required ValueChanged<PageOutlineItem> onSelect,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              label,
              style: Theme.of(sheetContext).textTheme.titleSmall,
            ),
          ),
          for (final item in items)
            ListTile(
              dense: true,
              leading: Icon(item.icon ?? Icons.chevron_right, size: 18),
              title: Text(item.label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onSelect(item);
                });
              },
            ),
        ],
      ),
    ),
  );
}

class PageOutlineScaffold extends StatefulWidget {
  const PageOutlineScaffold({
    super.key,
    required this.label,
    required this.items,
    required this.child,
    this.minWidth = 760,
    this.showNarrowButton = true,
  });

  final String label;
  final List<PageOutlineItem> items;
  final Widget child;
  final double minWidth;
  final bool showNarrowButton;

  @override
  State<PageOutlineScaffold> createState() => _PageOutlineScaffoldState();
}

class _PageOutlineScaffoldState extends State<PageOutlineScaffold> {
  bool _open = true;
  int? _selected;

  void _select(PageOutlineItem item) {
    setState(() => _selected = widget.items.indexOf(item));
    if (item.onTap != null) {
      item.onTap!();
      return;
    }
    final target = item.target;
    if (target == null) return;
    scrollToOutlineTarget(target);
  }

  Widget _rail(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Icon(Icons.toc, size: 16, color: palette.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => setState(() => _open = false),
                  icon: const Icon(Icons.chevron_left, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: _selected == i
                          ? palette.accent.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        hoverColor: palette.accent.withValues(alpha: 0.09),
                        onTap: () => _select(widget.items[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              if (widget.items[i].icon != null) ...[
                                Icon(
                                  widget.items[i].icon,
                                  size: 15,
                                  color: _selected == i
                                      ? palette.accent
                                      : palette.textPrimary,
                                ),
                                const SizedBox(width: 7),
                              ],
                              Expanded(
                                child: Text(
                                  widget.items[i].label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _selected == i
                                        ? palette.accent
                                        : palette.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedRail(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.surfaceAlt,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: widget.label,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.chevron_right, size: 18),
          ),
          const SizedBox(height: 4),
          Icon(Icons.toc, size: 17, color: palette.textSecondary),
        ],
      ),
    );
  }

  Widget _narrowOutlineButton(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      child: Material(
        elevation: 2,
        color: context.palette.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        child: IconButton(
          tooltip: widget.label,
          onPressed: () => showPageOutlineSheet(
            context,
            label: widget.label,
            items: widget.items,
            onSelect: _select,
          ),
          icon: const Icon(Icons.toc, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < widget.minWidth) {
          if (!widget.showNarrowButton) return widget.child;
          return Stack(children: [widget.child, _narrowOutlineButton(context)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: _open ? 196 : 42,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: _open ? _rail(context) : _collapsedRail(context),
            ),
            VerticalDivider(width: 1, color: context.palette.divider),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
