import 'package:flutter/widgets.dart';

/// Room available to the app, independent of orientation.
///
/// The class comes from the window's shortest side, so rotating a phone or a
/// tablet does not change it. Orientation may only choose a split axis inside
/// a class, never move the app to another class.
enum LayoutClass { compact, medium, expanded }

/// Single source of truth for the layout classes.
///
/// Thresholds follow the short-side brackets used by mature readers
/// (Zotero Android uses 680/834 dp for its own brackets); these are the
/// Material/browser table values: phone, small tablet, desktop-class.
class AppLayout {
  const AppLayout._();

  /// Below this shortest side the window is a phone: one pane at a time and
  /// the inspector is a sheet.
  static const double mediumMin = 600;

  /// At or above this shortest side the window is desktop/tablet-large: a
  /// permanent rail and a docked inspector.
  static const double expandedMin = 1024;

  static LayoutClass ofSize(Size size) {
    final shortest = size.shortestSide;
    if (shortest >= expandedMin) return LayoutClass.expanded;
    if (shortest >= mediumMin) return LayoutClass.medium;
    return LayoutClass.compact;
  }
}

extension LayoutClassContext on BuildContext {
  LayoutClass get layoutClass => AppLayout.ofSize(MediaQuery.sizeOf(this));

  bool get isCompactLayout => layoutClass == LayoutClass.compact;

  bool get isMediumLayout => layoutClass == LayoutClass.medium;

  bool get isExpandedLayout => layoutClass == LayoutClass.expanded;
}
