import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';

/// A thin vertical drag handle used between a resizable panel and the content.
///
/// Callers place it inside a Row with a bounded height (usually
/// [CrossAxisAlignment.stretch]) so the whole strip is draggable.
class VerticalResizeHandle extends StatefulWidget {
  const VerticalResizeHandle({
    super.key,
    required this.onDrag,
    this.onReset,
    this.tooltip,
    this.width = 6,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onReset;
  final String? tooltip;
  final double width;

  @override
  State<VerticalResizeHandle> createState() => _VerticalResizeHandleState();
}

class _VerticalResizeHandleState extends State<VerticalResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = _hover || _dragging;
    return Semantics(
      label:
          widget.tooltip ??
          AppScope.maybeOf(context)?.strings.resizeSidebar ??
          'Resize sidebar',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          onDoubleTap: widget.onReset,
          child: Container(
            width: widget.width,
            color: active ? palette.divider : Colors.transparent,
            alignment: Alignment.center,
            child: Container(
              width: 1,
              height: 32,
              color: active ? palette.accent : palette.divider,
            ),
          ),
        ),
      ),
    );
  }
}

/// A fixed-width side panel with the same drag handle and collapse gesture as
/// the context rail. [handleOnLeft] places the handle on the inner edge of a
/// right-hand rail; leave it false for a left-hand notes list.
class CollapsibleSidePanel extends StatelessWidget {
  const CollapsibleSidePanel({
    super.key,
    required this.width,
    required this.onDrag,
    required this.child,
    this.onReset,
    this.handleOnLeft = false,
    this.tooltip,
  });

  final double width;
  final ValueChanged<double> onDrag;
  final VoidCallback? onReset;
  final Widget child;
  final bool handleOnLeft;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final handle = VerticalResizeHandle(
      tooltip: tooltip,
      onDrag: onDrag,
      onReset: onReset,
    );
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (handleOnLeft) handle,
          Expanded(child: child),
          if (!handleOnLeft) handle,
        ],
      ),
    );
  }
}

/// Shared left-hand sidebar: expanded panel with draggable divider, or a
/// narrow icon rail after collapsing.
///
/// Search, Favorites and Notes use this same widget so the collapse affordance,
/// rail width and divider behaviour cannot drift between workspaces.
class CollapsibleSidebar extends StatelessWidget {
  const CollapsibleSidebar({
    super.key,
    required this.expanded,
    required this.width,
    required this.child,
    required this.onExpand,
    this.onDrag,
    this.onReset,
    this.tooltip,
    this.railIcon = Icons.view_sidebar_outlined,
    this.railTooltip,
    this.handleOnLeft = false,
    this.expandIcon = Icons.keyboard_double_arrow_right,
  });

  final bool expanded;
  final double width;
  final Widget child;
  final VoidCallback onExpand;
  final ValueChanged<double>? onDrag;
  final VoidCallback? onReset;
  final String? tooltip;
  final IconData railIcon;
  final String? railTooltip;

  /// Put the drag handle on the left edge (panels docked to the right).
  final bool handleOnLeft;

  /// Chevron shown in the collapsed rail; right for a left panel, left for a
  /// right panel.
  final IconData expandIcon;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return CollapsedSidebarRail(
        icon: railIcon,
        tooltip: railTooltip ?? tooltip ?? '',
        onExpand: onExpand,
        expandIcon: expandIcon,
      );
    }
    return CollapsibleSidePanel(
      width: width,
      tooltip: tooltip,
      onDrag: onDrag ?? (_) {},
      onReset: onReset,
      handleOnLeft: handleOnLeft,
      child: child,
    );
  }
}

/// Narrow rail shown after a workspace sidebar is collapsed.
class CollapsedSidebarRail extends StatelessWidget {
  const CollapsedSidebarRail({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onExpand,
    this.expandIcon = Icons.keyboard_double_arrow_right,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onExpand;
  final IconData expandIcon;

  static const double width = 46;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      color: palette.surface,
      child: Column(
        children: [
          const SizedBox(height: 2),
          IconButton(
            tooltip: tooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onExpand,
            icon: Icon(expandIcon, size: 18),
          ),
          const SizedBox(height: 4),
          Icon(icon, size: 18, color: palette.textSecondary),
        ],
      ),
    );
  }
}
