import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_scope.dart';
import 'chrome_visibility.dart';
import 'app_strings.dart';
import 'debug_hooks.dart';
import 'navigation.dart';
import 'shortcuts.dart';
import 'app_theme.dart';
import 'update_checker.dart';
import '../data/zotero_bridge.dart';
import '../data/zotero_cache.dart';
import '../features/common/page.dart';
import '../features/common/ui.dart';
import '../features/catalog/catalog_page.dart';
import '../features/favorites/favorites_page.dart';
import '../features/home/home_page.dart';
import '../features/notes/notes_page.dart';
import '../features/settings/settings_page.dart';
import '../features/help/help_page.dart';
import '../features/reference/inspire_search_page.dart';
import '../features/reviews/reviews_page.dart';

/// Primary destinations plus Settings, available from app navigation UI.
///
/// Keeping the enum order authoritative means the IndexedStack, tabs and
/// shortcuts stay aligned. Settings deliberately has no tab of its own.
enum AppTab { search, favorites, notes, settings }

const Map<AppTab, Widget> _pages = <AppTab, Widget>{
  AppTab.search: HomePage(),
  AppTab.favorites: FavoritesPage(),
  AppTab.notes: NotesPage(),
  AppTab.settings: SettingsPage(),
};

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const MethodChannel _menuChannel = MethodChannel('pdg.menu');
  int _index = AppTab.search.index;
  final List<bool> _built = [true, false, false, false];
  late final NavigationHub _navHub;
  int? _settingsReturnIndex;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _navHub = NavigationHub();
    _menuChannel.setMethodCallHandler(_handleMenuCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdates());
      unawaited(_autoUpdateZoteroIndex());
    });
  }

  Future<void> _autoUpdateZoteroIndex() async {
    if (!mounted || !ZoteroBridge.isSupportedPlatform) return;
    final settings = AppScope.of(context).settings;
    if (!settings.zoteroEnabled || !settings.autoUpdateZoteroIndex) return;
    try {
      await ZoteroIndexAutoUpdater.updateIfDue();
    } catch (_) {
      // The Zotero index is a speed cache; a failure must never affect startup.
    }
  }

  Future<void> _checkForUpdates() async {
    if (!UpdateChecker.isConfigured) return;
    final scope = AppScope.of(context);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (scope.settings.settings.lastUpdateCheck == today) return;
    try {
      final update = await UpdateChecker.check();
      if (!mounted) return;
      // Persist only after a successful check, so a transient network failure
      // is retried on the next start instead of silently skipping a day.
      await scope.settings.markUpdateChecked(today);
      if (update == null || !mounted) return;
      await showUpdateAvailableDialog(
        context,
        AppScope.of(context).strings,
        update,
      );
    } catch (_) {
      // An update check must never block startup or show a network error.
    }
  }

  Future<void> _handleMenuCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'showHelp') {
      _openPage(const HelpPage());
    } else if (call.method == 'showSettings') {
      _showSettings();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    for (final tab in AppTab.values) {
      _navHub.registerTab(
        tab.name,
        NavigationController(hub: _navHub, rootBuilder: (_) => _pages[tab]!),
      );
    }
    _navHub.setActiveTab(AppTab.search.name);
    debugTabHook = _select;
  }

  @override
  void dispose() {
    _menuChannel.setMethodCallHandler(null);
    if (debugTabHook != null) debugTabHook = null;
    _navHub.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (!mounted) return;
    if (index < 0 || index >= AppTab.values.length) return;
    if (index == _index) return;
    if (index == AppTab.settings.index) {
      _settingsReturnIndex = _index;
      _navHub.tabController(AppTab.settings.name)?.rootBack = _leaveSettings;
    } else if (_index == AppTab.settings.index) {
      _settingsReturnIndex = null;
      _navHub.tabController(AppTab.settings.name)?.rootBack = null;
    }
    setState(() {
      _index = index;
      _built[index] = true;
    });
    _navHub.setActiveTab(AppTab.values[index].name);
  }

  void _leaveSettings() {
    final target = _settingsReturnIndex;
    if (target == null) return;
    _select(target);
  }

  void _openPage(Widget page) {
    final controller = _navHub.activeTabController;
    if (controller != null) {
      unawaited(controller.push<void>(page));
      return;
    }
    unawaited(
      Navigator.of(context)
          .push<void>(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }

  void _showSettings() {
    _navHub.tabController(AppTab.settings.name)?.resetToRoot();
    _select(AppTab.settings.index);
  }

  void _goHome() {
    _navHub.tabController(AppTab.search.name)?.resetToRoot();
    _select(AppTab.search.index);
    AppScope.of(context).homeRequests.value++;
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final settings = AppScope.of(context).settings;
    final bindings = <ShortcutActivator, VoidCallback>{};
    void add(AppShortcutCommand command, VoidCallback action) {
      for (final binding in settings.shortcutBindings(command)) {
        bindings[binding.activator] = action;
      }
    }

    add(AppShortcutCommand.search, () => _select(AppTab.search.index));
    add(AppShortcutCommand.favorites, () => _select(AppTab.favorites.index));
    add(AppShortcutCommand.notes, () => _select(AppTab.notes.index));
    add(AppShortcutCommand.settings, _showSettings);
    add(AppShortcutCommand.newNote, () {
      _select(AppTab.notes.index);
      AppScope.of(context).noteRequests.value++;
    });
    add(AppShortcutCommand.back, _navHub.back);
    add(AppShortcutCommand.forward, _navHub.forward);
    return bindings;
  }

  PopupMenuButton<_CompactTopAction> _compactTopMenu(AppStrings strings) {
    return PopupMenuButton<_CompactTopAction>(
      tooltip: strings.moreActions,
      onSelected: (action) {
        switch (action) {
          case _CompactTopAction.catalog:
            _openPage(const CatalogPage());
          case _CompactTopAction.inspire:
            _openPage(const InspireSearchPage());
          case _CompactTopAction.reviews:
            _openPage(const ReviewsPage());
          case _CompactTopAction.help:
            _openPage(const HelpPage());
          case _CompactTopAction.settings:
            _showSettings();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _CompactTopAction.catalog,
          child: Text(strings.catalogTitle),
        ),
        PopupMenuItem(
          value: _CompactTopAction.inspire,
          child: Text(strings.inspireSearchAction),
        ),
        PopupMenuItem(
          value: _CompactTopAction.reviews,
          child: Text(strings.reviewsTitle),
        ),
        PopupMenuItem(
          value: _CompactTopAction.help,
          child: Text(strings.settingsHelp),
        ),
        PopupMenuItem(
          value: _CompactTopAction.settings,
          child: Text(strings.navSettings),
        ),
      ],
      icon: const Icon(Icons.more_vert, size: 20),
    );
  }

  List<_TabSpec> _tabSpecs(AppStrings strings) => <_TabSpec>[
    _TabSpec(
      tab: AppTab.search,
      label: strings.navQuery,
      icon: Icons.search,
      selectedIcon: Icons.search,
    ),
    _TabSpec(
      tab: AppTab.favorites,
      label: strings.navFavorites,
      icon: Icons.star_border,
      selectedIcon: Icons.star,
    ),
    _TabSpec(
      tab: AppTab.notes,
      label: strings.navNotes,
      icon: Icons.sticky_note_2_outlined,
      selectedIcon: Icons.sticky_note_2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final specs = _tabSpecs(strings);
    return NavigationHubScope(
      hub: _navHub,
      child: CallbackShortcuts(
        bindings: _shortcuts(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            // Four primary tabs need a little more room than the previous
            // three-tab layout before the compact NavigationBar takes over.
            // Back/forward add two controls to the persistent row; switch to
            // the compact bar a little earlier than the old tab-only layout.
            final compact =
                constraints.maxWidth < 1080 * textScale.clamp(1.0, 1.3);
            return AnimatedBuilder(
              animation: _navHub,
              builder: (context, _) {
                final keyboardOpen =
                    MediaQuery.viewInsetsOf(context).bottom > 0;
                final hideChrome =
                    compact &&
                    (_navHub.tabChromeHidden ||
                        (constraints.maxWidth < searchSplitBreakpoint &&
                            _navHub.detailChromeHidden));
                final hideBottomNav = compact && (hideChrome || keyboardOpen);
                return SelectionArea(
                  child: Scaffold(
                    backgroundColor: palette.background,
                    body: Column(
                      children: [
                        ExcludeFocus(
                          excluding: hideChrome,
                          child: Offstage(
                            offstage: hideChrome,
                            child: Material(
                              color: palette.surface,
                              child: SafeArea(
                                bottom: false,
                                child: Container(
                                  height: compact ? 48 : 64,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 10 : 20,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: palette.divider,
                                      ),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(
                                          right: compact ? 48 : 0,
                                        ),
                                        child: Row(
                                          children: [
                                            BrandMark(size: compact ? 24 : 28),
                                            SizedBox(width: compact ? 8 : 10),
                                            Flexible(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    strings.appName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textScaler:
                                                        MediaQuery.textScalerOf(
                                                          context,
                                                        ).clamp(
                                                          maxScaleFactor: 1.3,
                                                        ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          letterSpacing: -0.2,
                                                        ),
                                                  ),
                                                  if (!compact)
                                                    Text(
                                                      strings.appTagline,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textScaler:
                                                          MediaQuery.textScalerOf(
                                                            context,
                                                          ).clamp(
                                                            maxScaleFactor: 1.3,
                                                          ),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: palette
                                                                .textSecondary,
                                                            fontSize: 11.5,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: Insets.m),
                                            if (compact)
                                              _NavigationHistoryButtons(
                                                hub: _navHub,
                                                strings: strings,
                                              ),
                                            if (!compact)
                                              IconButton(
                                                tooltip: strings.navHome,
                                                icon: const Icon(
                                                  Icons.home_outlined,
                                                  size: 20,
                                                ),
                                                onPressed: _goHome,
                                              ),
                                            if (!compact)
                                              _NavigationHistoryButtons(
                                                hub: _navHub,
                                                strings: strings,
                                              ),
                                            if (!compact) ...[
                                              const SizedBox(width: Insets.xxl),
                                              for (final spec in specs)
                                                _TopTab(
                                                  label: spec.label,
                                                  icon: spec.selectedIcon,
                                                  selected:
                                                      _index == spec.tab.index,
                                                  onTap: () =>
                                                      _select(spec.tab.index),
                                                ),
                                            ],
                                            const Spacer(),
                                            if (!compact) ...[
                                              IconButton(
                                                tooltip: strings.catalogTitle,
                                                icon: const Icon(
                                                  Icons.account_tree_outlined,
                                                  size: 19,
                                                ),
                                                onPressed: () => _openPage(
                                                  const CatalogPage(),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    strings.inspireSearchAction,
                                                onPressed: () => _openPage(
                                                  const InspireSearchPage(),
                                                ),
                                                icon: SvgPicture.asset(
                                                  'assets/brand/inspire.svg',
                                                  width: 19,
                                                  height: 19,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: strings.reviewsTitle,
                                                icon: const Icon(
                                                  Icons.menu_book_outlined,
                                                  size: 19,
                                                ),
                                                onPressed: () => _openPage(
                                                  const ReviewsPage(),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: strings.settingsHelp,
                                                icon: const Icon(
                                                  Icons.help_outline,
                                                  size: 19,
                                                ),
                                                onPressed: () =>
                                                    _openPage(const HelpPage()),
                                              ),
                                              IconButton(
                                                tooltip: strings.navSettings,
                                                icon: const Icon(
                                                  Icons.tune,
                                                  size: 19,
                                                ),
                                                onPressed: () => _select(
                                                  AppTab.settings.index,
                                                ),
                                              ),
                                              MetaChip(
                                                'PDG ${scope.database.currentEdition}',
                                                icon: Icons.data_object,
                                                tone: BadgeTone.accent,
                                                tooltip: strings.offlineLabel,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (compact)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          bottom: 0,
                                          child: _compactTopMenu(strings),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SafeArea(
                            top: false,
                            bottom: false,
                            child: MediaQuery.removePadding(
                              context: context,
                              removeTop: !hideChrome,
                              removeBottom: compact && !hideBottomNav,
                              child: ChromeVisibilityScope(
                                hidden: hideChrome,
                                child: ActiveTabScope(
                                  activeTabKey: AppTab.values[_index].name,
                                  child: IndexedStack(
                                    index: _index,
                                    children: <Widget>[
                                      for (final tab in AppTab.values)
                                        if (_built[tab.index])
                                          _TabNavigator(
                                            controller: _navHub.tabController(
                                              tab.name,
                                            )!,
                                            active: _index == tab.index,
                                          )
                                        else
                                          const SizedBox.shrink(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (compact)
                          ExcludeFocus(
                            excluding: hideBottomNav,
                            child: Offstage(
                              offstage: hideBottomNav,
                              child: _CompactNavigationBar(
                                selectedIndex: _index,
                                onSelected: _select,
                                specs: specs,
                                settingsLabel: strings.navSettings,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CompactNavigationBar extends StatelessWidget {
  const _CompactNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.specs,
    required this.settingsLabel,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_TabSpec> specs;
  final String settingsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 2.0);
    final scale = textScaler.scale(1.0);
    // Keep the bar tight at the default size, but give the icon + label room
    // when the user increases the system font size.
    final barHeight = 52 + (scale - 1.0) * 14;
    final items = <_TabSpec>[
      ...specs,
      _TabSpec(
        tab: AppTab.settings,
        label: settingsLabel,
        icon: Icons.tune,
        selectedIcon: Icons.tune,
      ),
    ];
    return Material(
      color: palette.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.divider)),
          ),
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _CompactNavItem(
                    item: items[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactNavItem extends StatelessWidget {
  const _CompactNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.primary : palette.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.selectedIcon, size: 20, color: color),
              ),
              const SizedBox(height: 1),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.2),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.1,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.controller, required this.active});

  final NavigationController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<void>(
      enabled: active,
      onPopWithResult: (_) => controller.back(),
      child: NavigationScope(
        controller: controller,
        child: Navigator(
          key: controller.navigatorKey,
          observers: <NavigatorObserver>[controller],
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: controller.rootBuilder,
          ),
        ),
      ),
    );
  }
}

class _NavigationHistoryButtons extends StatelessWidget {
  const _NavigationHistoryButtons({required this.hub, required this.strings});

  final NavigationHub hub;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: strings.commonBack,
              onPressed: hub.canGoBack ? hub.back : null,
              icon: const Icon(Icons.arrow_back, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              tooltip: strings.commonForward,
              onPressed: hub.canGoForward ? hub.forward : null,
              icon: const Icon(Icons.arrow_forward, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
      },
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final AppTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _TopTab extends StatelessWidget {
  const _TopTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? palette.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? palette.divider : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? palette.primary : palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? palette.primary : palette.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CompactTopAction { catalog, inspire, reviews, help, settings }
