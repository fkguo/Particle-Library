import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard bindings for the PDF reader's find bar.
///
/// Cmd/Ctrl+F opens and focuses the search field; Cmd/Ctrl+G and F3 walk
/// matches, with Shift for the previous one. Escape closes the bar only while
/// it is open, so it does not swallow Escape for the rest of the reader.
class ReviewSearchShortcuts extends StatelessWidget {
  const ReviewSearchShortcuts({
    super.key,
    required this.isMac,
    required this.searchOpen,
    required this.onFind,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.child,
  });

  final bool isMac;
  final bool searchOpen;
  final VoidCallback onFind;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyF, meta: isMac, control: !isMac):
            onFind,
        SingleActivator(LogicalKeyboardKey.keyG, meta: isMac, control: !isMac):
            onNext,
        SingleActivator(
          LogicalKeyboardKey.keyG,
          meta: isMac,
          control: !isMac,
          shift: true,
        ): onPrevious,
        const SingleActivator(LogicalKeyboardKey.f3): onNext,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): onPrevious,
        if (searchOpen)
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
