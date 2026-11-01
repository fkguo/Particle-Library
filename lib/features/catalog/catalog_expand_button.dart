import 'package:flutter/material.dart';

/// Expand/collapse control for a catalog row with child entries.
///
/// It lives in the row's trailing action area, not inside the chips Wrap. The
/// IconButton keeps a 48dp touch target, while the explicit Semantics node
/// carries the label, tap action and expanded state so a screen reader receives
/// the state together with the actionable control.
class CatalogExpandButton extends StatelessWidget {
  const CatalogExpandButton({
    super.key,
    required this.expanded,
    required this.tooltip,
    required this.onPressed,
  });

  final bool expanded;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
