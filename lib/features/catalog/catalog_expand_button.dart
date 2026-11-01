import 'package:flutter/material.dart';

/// Expand/collapse control for a catalog row with child entries.
///
/// It lives in the row's trailing action area, not inside the chips Wrap. The
/// IconButton keeps a 48dp touch target and the wrapping Semantics exposes the
/// expanded/collapsed state to accessibility services.
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
      expanded: expanded,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
        onPressed: onPressed,
      ),
    );
  }
}
