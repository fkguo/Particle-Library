import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Non-modal, draggable and resizable panel rendered in an [Overlay].
///
/// Unlike a dialog it has no barrier: the page below stays interactive, which
/// is what the notes editor needs for a PDG lookup window that can sit next to
/// the text while the user keeps typing.
/// Tracks the floating panels currently inserted in overlays so a modal
/// dialog can hide them (they sit above route overlays) and restore them.
class FloatingPanelHost {
  static final List<({OverlayEntry entry, OverlayState overlay})> _active = [];

  static void register(OverlayEntry entry, OverlayState overlay) {
    _active.add((entry: entry, overlay: overlay));
  }

  static void unregister(OverlayEntry entry) {
    _active.removeWhere((item) => identical(item.entry, entry));
  }

  static void suspendAll() {
    for (final item in List.of(_active)) {
      if (item.entry.mounted) item.entry.remove();
    }
  }

  static void resumeAll() {
    for (final item in List.of(_active)) {
      if (!item.entry.mounted) item.overlay.insert(item.entry);
    }
  }

  static void closeAll() {
    for (final item in List.of(_active)) {
      if (item.entry.mounted) item.entry.remove();
    }
    _active.clear();
  }
}

class FloatingPanel extends StatefulWidget {
  const FloatingPanel({
    super.key,
    required this.title,
    required this.child,
    required this.initialRect,
    this.minSize = const Size(320, 240),
    this.maxSize,
    this.onClose,
    this.onBack,
  });

  final String title;
  final Widget child;
  final Rect initialRect;
  final Size minSize;
  final Size? maxSize;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  @override
  State<FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<FloatingPanel> {
  late Rect _rect = widget.initialRect;

  Rect _clamp(Rect rect) {
    final media = MediaQuery.sizeOf(context);
    final maxWidth = widget.maxSize?.width ?? media.width - 16;
    final maxHeight = widget.maxSize?.height ?? media.height - 16;
    final width = rect.width
        .clamp(widget.minSize.width, math.max(widget.minSize.width, maxWidth))
        .toDouble();
    final height = rect.height
        .clamp(
          widget.minSize.height,
          math.max(widget.minSize.height, maxHeight),
        )
        .toDouble();
    final left = rect.left
        .clamp(8.0, math.max(8.0, media.width - width - 8))
        .toDouble();
    final top = rect.top
        .clamp(8.0, math.max(8.0, media.height - height - 8))
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  void _move(Offset delta) {
    setState(() => _rect = _clamp(_rect.shift(delta)));
  }

  void _resize(Offset delta) {
    setState(() {
      _rect = _clamp(
        Rect.fromLTWH(
          _rect.left,
          _rect.top,
          _rect.width + delta.dx,
          _rect.height + delta.dy,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      rect: _clamp(_rect),
      child: Material(
        elevation: 18,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: palette.surface,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      if (widget.onBack != null)
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: widget.onBack,
                          icon: const Icon(Icons.arrow_back, size: 18),
                        )
                      else
                        const SizedBox(width: 6),
                      const Icon(Icons.drag_indicator, size: 16),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) => _move(details.delta),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: widget.child),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => _resize(details.delta),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.open_in_full,
                      size: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
