import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../features/entry/entry_route_page.dart';
import '../features/reference/reference_page.dart';
import '../features/series/measurement_deep_link.dart';
import 'immersive_page.dart';

/// Key of the Search tab's navigator. Kept as a string so HomePage can
/// register its detail navigator without importing AppShell (and creating an
/// import cycle).
const String searchTabNavigationKey = 'search';

/// Width at which the Search tab keeps the list and detail panes side by side.
const double searchSplitBreakpoint = 900;

/// A per-tab navigation stack with browser-like back/forward history.
///
/// The controller is also the navigator's [NavigatorObserver]. Every route
/// pushed through [push] records its page builder; going back stores the
/// entry in a forward stack, and forward rebuilds that page. Rebuilding means
/// a page opened again from history starts with fresh widget state; durable
/// state belongs in the user store, not in transient page fields.
class NavigationController extends NavigatorObserver with ChangeNotifier {
  NavigationController({required this.hub, required this.rootBuilder})
    : _entries = <_NavEntry>[_NavEntry(rootBuilder)];

  final NavigationHub hub;
  final WidgetBuilder rootBuilder;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final List<_NavEntry> _entries;
  final List<_NavEntry> _forward = <_NavEntry>[];
  bool _suppressForward = false;
  VoidCallback? _rootBack;

  /// Optional action used when the stack is already at its root (for example
  /// returning from the Settings tab to the tab that opened it).
  VoidCallback? get rootBack => _rootBack;

  set rootBack(VoidCallback? value) {
    if (identical(_rootBack, value)) return;
    _rootBack = value;
    hub.notifyHistoryChanged();
  }

  bool get canGoBack => _entries.length > 1 || _rootBack != null;

  /// Whether the route currently on top of this stack is an [ImmersivePage].
  bool get topIsImmersive => _entries.length > 1 && _entries.last.immersive;

  /// Whether the top route owns text selection and must not inherit the
  /// app-wide [SelectionArea].
  bool get topDisablesGlobalSelection =>
      _entries.length > 1 && _entries.last.disableGlobalSelection;
  bool get canGoForward => _forward.isNotEmpty;
  bool get hasHistory => canGoBack || canGoForward;

  Future<T?> push<T>(Widget page) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return Future<T?>.value();
    final entry = _NavEntry(
      (_) => page,
      immersive: page is ImmersivePage,
      disableGlobalSelection: page is NoGlobalSelection,
    );
    final route = MaterialPageRoute<T>(builder: entry.builder!);
    entry.route = route;
    _entries.add(entry);
    _forward.clear();
    hub.notifyHistoryChanged();
    return navigator.push<T>(route);
  }

  void back() {
    if (_entries.length > 1) {
      navigatorKey.currentState?.maybePop();
      return;
    }
    _rootBack?.call();
  }

  void forward() {
    if (_forward.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final entry = _forward.removeLast();
    if (entry.builder == null) {
      hub.notifyHistoryChanged();
      return;
    }
    final route = MaterialPageRoute<dynamic>(builder: entry.builder!);
    entry.route = route;
    _entries.add(entry);
    hub.notifyHistoryChanged();
    navigator.push(route);
  }

  /// Clear this stack back to its root page. Used by the Home action and by
  /// callers that need to replace the current context.
  void resetToRoot() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      _suppressForward = true;
      navigator.popUntil((route) => route.isFirst);
      _suppressForward = false;
    }
    _forward.clear();
    if (_entries.length > 1) {
      _entries.removeRange(1, _entries.length);
    }
    hub.notifyHistoryChanged();
  }

  void clearForward() {
    _forward.clear();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute<dynamic>) {
      if (previousRoute == null && _entries.isNotEmpty) {
        // This navigator was (re)created: its old route handles are dead.
        // Keep only the root builder and start a fresh stack.
        _entries.removeRange(1, _entries.length);
        _forward.clear();
        _entries.first.route = route;
        hub.notifyHistoryChanged();
        return;
      }
      if (!_entries.any((entry) => identical(entry.route, route))) {
        // A route pushed without going through this controller (for example
        // Flutter's license page). It can still be popped, but it cannot be
        // replayed from the forward stack.
        _entries.add(_NavEntry(null, route: route));
      }
      hub.notePushed(this);
      return;
    }
    hub.notifyHistoryChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final index = _entries.indexWhere((entry) => identical(entry.route, route));
    if (index > 0) {
      final entry = _entries.removeAt(index);
      if (!_suppressForward && entry.builder != null) {
        _forward.add(entry);
      }
      hub.notePopped(this);
      return;
    }
    hub.notifyHistoryChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _entries.removeWhere((entry) => identical(entry.route, route));
    hub.notifyHistoryChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = _entries.indexWhere(
      (entry) => identical(entry.route, oldRoute),
    );
    if (index >= 0) {
      _entries[index].route = newRoute;
    }
    hub.notifyHistoryChanged();
  }
}

class _NavEntry {
  _NavEntry(
    this.builder, {
    this.route,
    this.immersive = false,
    this.disableGlobalSelection = false,
  });

  final WidgetBuilder? builder;
  Route<dynamic>? route;
  final bool immersive;
  final bool disableGlobalSelection;
}

/// Which navigator the persistent top bar controls.
///
/// The active tab's own navigator wins when it has a page above its root;
/// otherwise the detail pane (Search split view) wins. This keeps the top bar
/// history tied to the topmost visible content.
class NavigationHub extends ChangeNotifier {
  final Map<String, NavigationController> _tabs =
      <String, NavigationController>{};
  final Map<String, NavigationController> _details =
      <String, NavigationController>{};
  String _activeTabKey = searchTabNavigationKey;
  NavigationController? _lastPopped;
  bool _disposed = false;
  bool _notificationScheduled = false;

  String get activeTabKey => _activeTabKey;

  void registerTab(String key, NavigationController controller) {
    _tabs[key] = controller;
    notifyHistoryChanged();
  }

  NavigationController? tabController(String key) => _tabs[key];

  void registerDetail(String key, NavigationController controller) {
    _details[key] = controller;
    notifyHistoryChanged();
  }

  void unregisterDetail(String key, NavigationController controller) {
    if (identical(_details[key], controller)) {
      _details.remove(key);
      if (identical(_lastPopped, controller)) _lastPopped = null;
      notifyHistoryChanged();
    }
  }

  NavigationController? get activeTabController => _tabs[_activeTabKey];

  NavigationController? get activeDetailController => _details[_activeTabKey];

  /// Back follows the topmost visible stack: a page pushed over the whole
  /// tab wins, otherwise the Search detail pane.
  NavigationController? get backController {
    final tab = activeTabController;
    final detail = activeDetailController;
    if (tab != null && tab.canGoBack) return tab;
    if (detail != null && detail.canGoBack) return detail;
    return null;
  }

  /// Forward restores the stack that most recently lost a page. A new push
  /// clears every stack's forward history, so the two panes cannot rewind to
  /// unrelated hidden pages.
  NavigationController? get forwardController {
    final last = _lastPopped;
    if (last == null || !last.canGoForward) return null;
    final activeTab = activeTabController;
    final activeDetail = activeDetailController;
    if (identical(last, activeTab) || identical(last, activeDetail)) {
      return last;
    }
    return null;
  }

  /// Whether the active tab's own top route is immersive. A page above the
  /// tab root always wins over the Search split-view detail pane.
  bool get tabChromeHidden => activeTabController?.topIsImmersive ?? false;

  /// Whether the detail pane is immersive and is the visible pane. The detail
  /// pane never fills the window on wide Search layouts, so the shell only
  /// treats it as full-screen below [searchSplitBreakpoint].
  bool get detailChromeHidden {
    final tab = activeTabController;
    if (tab != null && tab.canGoBack) return false;
    return activeDetailController?.topIsImmersive ?? false;
  }

  /// Whether the visible page owns its own text selection.
  bool get globalSelectionDisabled {
    final tab = activeTabController;
    if (tab != null && tab.topDisablesGlobalSelection) return true;
    return activeDetailController?.topDisablesGlobalSelection ?? false;
  }

  bool get canGoBack => backController != null;
  bool get canGoForward => forwardController != null;

  void back() => backController?.back();

  void forward() {
    final controller = forwardController;
    if (controller == null) return;
    controller.forward();
  }

  void notePushed(NavigationController controller) {
    for (final candidate in <NavigationController>{
      ..._tabs.values,
      ..._details.values,
    }) {
      candidate.clearForward();
    }
    _lastPopped = null;
    notifyHistoryChanged();
  }

  void notePopped(NavigationController controller) {
    _lastPopped = controller;
    notifyHistoryChanged();
  }

  void setActiveTab(String key) {
    if (_activeTabKey == key) return;
    _activeTabKey = key;
    notifyHistoryChanged();
  }

  /// Notify the top bar after a route change. A navigator can report a push
  /// while it is building its initial route; defer that notification until
  /// the frame is complete to avoid marking an ancestor dirty during build.
  void notifyHistoryChanged() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationScheduled) return;
      _notificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Exposes the active [NavigationController] to pages built inside its
/// navigator. [PageScaffold] uses this to avoid drawing a second back button
/// when the persistent top bar already provides one.
class NavigationScope extends InheritedWidget {
  const NavigationScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final NavigationController controller;

  static NavigationController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NavigationScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(NavigationScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Provides the app-wide hub to pages that own a nested navigator (currently
/// the Search split view). The hub itself is a [Listenable], so it is passed
/// as a plain inherited value rather than rebuilding every page on history
/// changes.
class ActiveTabScope extends InheritedWidget {
  const ActiveTabScope({
    super.key,
    required this.activeTabKey,
    required super.child,
  });

  final String activeTabKey;

  static String? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ActiveTabScope>()
        ?.activeTabKey;
  }

  @override
  bool updateShouldNotify(ActiveTabScope oldWidget) =>
      oldWidget.activeTabKey != activeTabKey;
}

class NavigationHubScope extends InheritedWidget {
  const NavigationHubScope({
    super.key,
    required this.hub,
    required super.child,
  });

  final NavigationHub hub;

  static NavigationHub? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NavigationHubScope>()
        ?.hub;
  }

  @override
  bool updateShouldNotify(NavigationHubScope oldWidget) => oldWidget.hub != hub;
}

class AppNav {
  static NavigationController? _controllerOf(BuildContext context) {
    return NavigationScope.maybeOf(context);
  }

  static Future<T?> push<T>(BuildContext context, Widget page) {
    final controller = _controllerOf(context);
    if (controller != null) return controller.push<T>(page);
    return Navigator.of(context)
        .push<T>(MaterialPageRoute<T>(builder: (_) => page));
  }

  static Future<T?> replaceAll<T>(BuildContext context, Widget page) {
    final controller = _controllerOf(context);
    if (controller != null) {
      controller.resetToRoot();
      return controller.push<T>(page);
    }
    return Navigator.of(context).pushAndRemoveUntil<T>(
      MaterialPageRoute<T>(builder: (_) => page),
      (route) => route.isFirst,
    );
  }

  static Future<void> openPdgid(BuildContext context, String pdgid) async {
    await push(context, EntryRoutePage(pdgid: pdgid));
  }

  static Future<void> openReference(
    BuildContext context,
    int referenceId,
  ) async {
    await push(context, ReferencePage(referenceId: referenceId));
  }

  /// Opens one measurement directly. A missing row falls back inside the page
  /// to the series route instead of silently doing nothing.
  static Future<void> openMeasurement(
    BuildContext context, {
    required String pdgid,
    required int measurementId,
  }) async {
    await push(
      context,
      MeasurementDeepLinkPage(pdgid: pdgid, measurementId: measurementId),
    );
  }
}
