import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/debug_hooks.dart';
import '../../app/app_strings.dart';
import '../../app/navigation.dart';
import '../../app/app_theme.dart';
import '../../data/pdg_database.dart';
import '../../data/review_cache.dart';
import '../../search/search_service.dart';
import '../catalog/catalog_page.dart';
import '../common/async_view.dart';
import '../common/description_text.dart';
import '../common/math_text.dart';
import '../common/page.dart';
import '../common/resize_handle.dart';
import '../common/ui.dart';
import '../entry/entry_route_page.dart';
import '../notes/note_editor.dart';
import '../notes/notes_format.dart';
import '../reference/inspire_search_page.dart';
import '../reference/reference_page.dart';
import '../reviews/review_download_dialog.dart';
import '../reviews/review_index.dart';
import '../reviews/review_viewer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<SearchResults?> _results = ValueNotifier(null);

  SearchScope _scope = SearchScope.all;
  Timer? _debounce;
  Object? _error;
  bool _searching = false;
  int _generation = 0;
  String? _inFlightKey;
  double? _resultsWidth;
  bool _searchPanelOpen = true;
  late Future<SnapshotStats> _statsFuture;

  bool _initialized = false;
  ValueNotifier<int>? _homeRequests;
  NavigationController? _detailController;
  NavigationHub? _navigationHub;
  NavigationHub? _ownedNavigationHub;
  bool? _detailRegisteredWide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _homeRequests = AppScope.of(context).homeRequests;
    _homeRequests!.addListener(_onHomeRequested);
    _statsFuture = AppScope.of(context).database.snapshotStats();
    final providedHub = NavigationHubScope.maybeOf(context);
    final hub = providedHub ?? (_ownedNavigationHub ??= NavigationHub());
    _navigationHub = hub;
    final detailController = NavigationController(
      hub: hub,
      rootBuilder: (_) => _DetailPlaceholder(
        onOpenCatalog: () => _openCatalog(true),
        statsFuture: _statsFuture,
      ),
    );
    _detailController = detailController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppScope.of(context).search.warmNameIndex());
    });
    _controller.addListener(_onTextChanged);
    debugSearchHook = (query) {
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
      _scope = SearchScope.all;
      _runSearch();
    };
  }

  @override
  void dispose() {
    _homeRequests?.removeListener(_onHomeRequested);
    if (debugSearchHook != null) debugSearchHook = null;
    _debounce?.cancel();
    final detailController = _detailController;
    if (detailController != null) {
      _navigationHub?.unregisterDetail(
        searchTabNavigationKey,
        detailController,
      );
      detailController.dispose();
    }
    _ownedNavigationHub?.dispose();
    _controller.dispose();
    _focus.dispose();
    _results.dispose();
    super.dispose();
  }

  void _onHomeRequested() {
    _debounce?.cancel();
    _detailController?.resetToRoot();
    _controller.clear();
    // A search still running must not fill the emptied page when it returns.
    _generation++;
    _results.value = null;
    setState(() {
      _scope = SearchScope.all;
      _searching = false;
      _error = null;
      _inFlightKey = null;
    });
    _focus.requestFocus();
  }

  void _syncDetailRegistration(bool wide) {
    final controller = _detailController;
    if (controller == null) return;
    if (wide) {
      if (_detailRegisteredWide == true) return;
      _detailRegisteredWide = true;
      _navigationHub?.registerDetail(searchTabNavigationKey, controller);
      return;
    }
    if (_detailRegisteredWide == false) return;
    _detailRegisteredWide = false;
    _navigationHub?.unregisterDetail(searchTabNavigationKey, controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.resetToRoot();
    });
  }

  void _onTextChanged() {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      // Cleared while a search was running: its answer no longer belongs here.
      _generation++;
      _inFlightKey = null;
      setState(() {
        _results.value = null;
        _error = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 240), () => _runSearch());
  }

  Future<void> _runSearch({bool record = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final inFlightKey = '${_scope.name}|$query';
    if (_inFlightKey == inFlightKey) return;
    _inFlightKey = inFlightKey;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    if (record) {
      unawaited(AppScope.of(context).store.addRecent(query, _scope.name));
    }
    try {
      final results = await AppScope.of(context).search.search(query, _scope);
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _results.value = results;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _error = error;
      });
    } finally {
      if (_inFlightKey == inFlightKey) _inFlightKey = null;
    }
  }

  void _setScope(SearchScope scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    _runSearch();
  }

  void _useRecent(String query, String scopeName) {
    final scope = SearchScope.values.firstWhere(
      (candidate) => candidate.name == scopeName,
      orElse: () => SearchScope.all,
    );
    setState(() {
      _scope = scope;
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
    });
    _focus.requestFocus();
    _runSearch();
  }

  void _openInspireSearch(String query) {
    unawaited(
      AppNav.push<void>(context, InspireSearchPage(initialQuery: query.trim())),
    );
  }

  void _openCatalog(bool wide) {
    const page = CatalogPage();
    final controller = _detailController;
    if (wide && controller != null) {
      unawaited(controller.push<void>(page));
    } else {
      unawaited(AppNav.push<void>(context, page));
    }
  }

  void _openHit(SearchHit hit, {required bool wide}) {
    if (hit.kind == SearchGroupKind.review) {
      unawaited(
        AppScope.of(context).store.addRecent(_controller.text, _scope.name),
      );
      unawaited(_openReviewHit(hit));
      return;
    }
    final Widget page;
    if (hit.kind == SearchGroupKind.note && hit.note != null) {
      page = NoteEditorPage(note: hit.note!);
    } else if (hit.kind == SearchGroupKind.reference) {
      page = ReferencePage(referenceId: hit.referenceId!);
    } else {
      page = EntryRoutePage(pdgid: hit.openPdgid);
    }
    unawaited(
      AppScope.of(context).store.addRecent(_controller.text, _scope.name),
    );
    final controller = _detailController;
    if (wide && controller != null) {
      unawaited(controller.push<void>(page));
    } else {
      unawaited(AppNav.push<void>(context, page));
    }
  }

  Future<void> _openReviewHit(SearchHit hit) async {
    final file = hit.reviewFile;
    if (file == null) return;
    final entry = reviewEntryForFile(file);
    final title = entry?.title ?? hit.title;
    final url = entry?.url ?? 'https://pdg.lbl.gov/2026/reviews/$file';
    final strings = AppScope.of(context).strings;
    try {
      final cache = await ReviewCache.open();
      var local = cache.fileFor(file);
      if (!await local.exists()) {
        if (!mounted) return;
        final progress = ValueNotifier<ReviewDownloadProgress>(
          const ReviewDownloadProgress(received: 0),
        );
        final navigator = Navigator.of(context, rootNavigator: true);
        var dialogOpen = true;
        unawaited(
          showDialog<void>(
            context: context,
            useRootNavigator: true,
            barrierDismissible: false,
            builder: (_) => ReviewDownloadDialog(
              title: title,
              progress: progress,
              strings: strings,
            ),
          ).then((_) => dialogOpen = false),
        );
        try {
          local = await cache.download(
            fileName: file,
            url: url,
            onProgress: (received, total) {
              progress.value = ReviewDownloadProgress(
                received: received,
                total: total,
              );
            },
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.searchReviewDownloadFailed)),
          );
          return;
        } finally {
          if (dialogOpen && navigator.mounted) navigator.pop();
        }
      }
      var page = hit.reviewPage;
      final expected = hit.reviewSha256;
      if (expected != null && expected.isNotEmpty) {
        final actual = await _sha256Of(local);
        if (actual != expected) {
          page = 1;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.searchReviewPdfMismatch)),
            );
          }
        }
      }
      if (!mounted) return;
      await AppNav.push<void>(
        context,
        ReviewViewerPage(
          title: title,
          path: local.path,
          officialUrl: url,
          initialPage: page,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.searchReviewOpenFailed)));
    }
  }

  Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _focus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _focus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= searchSplitBreakpoint;
            final searchActive =
                ActiveTabScope.maybeOf(context) == searchTabNavigationKey;
            _syncDetailRegistration(wide);
            if (!wide) {
              return _SearchPanel(
                controller: _controller,
                focusNode: _focus,
                scope: _scope,
                results: _results,
                searching: _searching,
                error: _error,
                statsFuture: _statsFuture,
                onScopeChanged: _setScope,
                onSearch: () => _runSearch(record: true),
                onOpenHit: (hit) => _openHit(hit, wide: false),
                onUseRecent: _useRecent,
                onOpenCatalog: () => _openCatalog(false),
                onSearchInspire: _openInspireSearch,
              );
            }
            final maxResultsWidth = (constraints.maxWidth - 420).clamp(
              300.0,
              620.0,
            );
            final resultsWidth = (_resultsWidth ?? 390).clamp(
              300.0,
              maxResultsWidth,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CollapsibleSidebar(
                  expanded: _searchPanelOpen,
                  width: resultsWidth,
                  tooltip: AppScope.of(context).strings.searchResizeTooltip,
                  railIcon: Icons.search,
                  railTooltip: AppScope.of(context).strings.sidebarShow,
                  onExpand: () => setState(() => _searchPanelOpen = true),
                  onDrag: (delta) {
                    final next = (resultsWidth + delta).clamp(
                      300.0,
                      maxResultsWidth,
                    );
                    if (delta < 0 && next <= 302) {
                      setState(() => _searchPanelOpen = false);
                      return;
                    }
                    setState(() => _resultsWidth = next);
                  },
                  onReset: () => setState(() => _resultsWidth = null),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      border: Border(
                        right: BorderSide(color: context.palette.divider),
                      ),
                    ),
                    child: _SearchPanel(
                      controller: _controller,
                      focusNode: _focus,
                      scope: _scope,
                      results: _results,
                      searching: _searching,
                      error: _error,
                      statsFuture: _statsFuture,
                      onScopeChanged: _setScope,
                      onSearch: () => _runSearch(record: true),
                      onOpenHit: (hit) => _openHit(hit, wide: true),
                      onUseRecent: _useRecent,
                      onOpenCatalog: () => _openCatalog(true),
                      onSearchInspire: _openInspireSearch,
                      onCollapse: () =>
                          setState(() => _searchPanelOpen = false),
                      dense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final controller = _detailController;
                      if (controller == null) {
                        return const SizedBox.shrink();
                      }
                      return NavigatorPopHandler<void>(
                        enabled: searchActive,
                        onPopWithResult: (_) => controller.back(),
                        child: NavigationScope(
                          controller: controller,
                          child: Navigator(
                            key: controller.navigatorKey,
                            observers: <NavigatorObserver>[controller],
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              settings: settings,
                              builder: controller.rootBuilder,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.focusNode,
    required this.scope,
    required this.results,
    required this.searching,
    required this.error,
    required this.statsFuture,
    required this.onScopeChanged,
    required this.onSearch,
    required this.onOpenHit,
    required this.onUseRecent,
    required this.onOpenCatalog,
    required this.onSearchInspire,
    this.onCollapse,
    this.dense = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchScope scope;
  final ValueNotifier<SearchResults?> results;
  final bool searching;
  final Object? error;
  final Future<SnapshotStats> statsFuture;
  final ValueChanged<SearchScope> onScopeChanged;
  final VoidCallback onSearch;
  final ValueChanged<SearchHit> onOpenHit;
  final void Function(String query, String scope) onUseRecent;
  final VoidCallback onOpenCatalog;
  final ValueChanged<String> onSearchInspire;
  final VoidCallback? onCollapse;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scopeData = AppScope.of(context);
    final strings = scopeData.strings;
    final palette = context.palette;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        dense ? Insets.l : Insets.l,
        Insets.l,
        Insets.l,
        Insets.xxl,
      ),
      children: [
        if (dense)
          Row(
            children: [
              Text(
                strings.navQuery,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: strings.sidebarHide,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: onCollapse,
                icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
              ),
            ],
          ),
        if (!dense) ...[
          Text(
            strings.navQuery,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
          const SizedBox(height: 2),
          Text(
            strings.searchEmptyPrompt,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: Insets.l),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: dense ? strings.searchShortHint : strings.searchHint,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              tooltip: strings.commonReset,
              icon: const Icon(Icons.close, size: 17),
              onPressed: () {
                controller.clear();
                focusNode.requestFocus();
              },
            ),
            filled: true,
            fillColor: palette.surface,
          ),
        ),
        const SizedBox(height: Insets.s),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final entry in const {
              SearchScope.all: 'searchScopeAll',
              SearchScope.particles: 'searchScopeParticles',
              SearchScope.titles: 'searchScopeTitles',
              SearchScope.decays: 'searchScopeDecays',
              SearchScope.references: 'searchScopeReferences',
              SearchScope.reviews: 'searchScopeReviews',
              SearchScope.notes: 'searchScopeNotes',
            }.entries)
              ChoiceChip(
                label: Text(switch (entry.key) {
                  SearchScope.all => strings.searchScopeAll,
                  SearchScope.particles => strings.searchScopeParticles,
                  SearchScope.titles => strings.searchScopeTitles,
                  SearchScope.decays => strings.searchScopeDecays,
                  SearchScope.references => strings.searchScopeReferences,
                  SearchScope.reviews => strings.searchScopeReviews,
                  SearchScope.notes => strings.searchScopeNotes,
                }),
                selected: scope == entry.key,
                onSelected: (_) => onScopeChanged(entry.key),
              ),
          ],
        ),
        if (scope == SearchScope.references || scope == SearchScope.all) ...[
          const SizedBox(height: Insets.s),
          Align(
            alignment: Alignment.centerLeft,
            // The offline/online scope note moved to a tooltip and the help
            // page; it no longer costs a line under the button.
            child: Tooltip(
              message: strings.inspireSearchEntryHint,
              child: OutlinedButton.icon(
                onPressed: () => onSearchInspire(''),
                icon: const Icon(Icons.travel_explore, size: 17),
                label: Text(strings.inspireSearchAction),
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        SelectableText(
          strings.searchExamples,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
        if (searching)
          Padding(
            padding: const EdgeInsets.only(top: Insets.s),
            child: Row(
              children: [
                const BrandMark(size: 26, animate: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.commonLoading,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                      const SizedBox(height: 3),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.m),
            child: ErrorPanel(error: error!, onRetry: onSearch),
          ),
        ValueListenableBuilder<SearchResults?>(
          valueListenable: results,
          builder: (context, value, _) {
            if (value != null) {
              final notice = switch (value.notice) {
                'unavailable' ||
                'degraded' => strings.searchReviewIndexUnavailable,
                _ => null,
              };
              if (value.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Insets.s),
                        child: Text(
                          notice,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.palette.textSecondary),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: Insets.m),
                      child: EmptyPanel(
                        message: strings.searchNoResults,
                        icon: Icons.search_off,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Insets.s),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.s),
                      child: Text(
                        notice,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: context.palette.textSecondary),
                      ),
                    ),
                  for (final group in value.groups)
                    _ResultGroup(
                      group: group,
                      strings: strings,
                      onOpenHit: onOpenHit,
                    ),
                ],
              );
            }
            return _IdleContent(
              statsFuture: statsFuture,
              onUseRecent: onUseRecent,
              onOpenCatalog: onOpenCatalog,
            );
          },
        ),
      ],
    );
  }
}

class _IdleContent extends StatelessWidget {
  const _IdleContent({
    required this.statsFuture,
    required this.onUseRecent,
    required this.onOpenCatalog,
  });

  final Future<SnapshotStats> statsFuture;
  final void Function(String query, String scope) onUseRecent;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Insets.l),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.catalogTitle,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: onOpenCatalog,
              icon: const Icon(Icons.account_tree_outlined, size: 17),
              label: Text(strings.commonOpen),
            ),
          ],
        ),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenCatalog,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Insets.m),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.catalogSubtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: Insets.s),
                FutureBuilder<SnapshotStats>(
                  future: statsFuture,
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    if (stats == null) return const SizedBox(height: 22);
                    return Text(
                      '${stats.entries} ${strings.entriesLabel} · '
                      '${'${stats.measurements}'} ${strings.measurementsLabel} · '
                      '${stats.references} ${strings.referencesLabel}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.l),
        AnimatedBuilder(
          animation: scope.store,
          builder: (context, _) {
            final recents = scope.store.recents;
            if (recents.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.searchRecent,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: strings.searchClearRecent,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            content: Text(strings.searchClearRecentConfirm),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(strings.commonCancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(strings.commonConfirm),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) await scope.store.clearRecents();
                      },
                    ),
                  ],
                ),
                for (final recent in recents.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text(recent.query),
                    subtitle: Text(switch (recent.scope) {
                      'particles' => strings.searchScopeParticles,
                      'titles' => strings.searchScopeTitles,
                      'decays' => strings.searchScopeDecays,
                      'references' => strings.searchScopeReferences,
                      'reviews' => strings.searchScopeReviews,
                      'notes' => strings.searchScopeNotes,
                      _ => strings.searchScopeAll,
                    }),
                    onTap: () => onUseRecent(recent.query, recent.scope),
                    trailing: IconButton(
                      tooltip: strings.searchRemoveRecent,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () =>
                          scope.store.removeRecent(recent.query, recent.scope),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _ResultGroup extends StatelessWidget {
  const _ResultGroup({
    required this.group,
    required this.strings,
    required this.onOpenHit,
  });

  final SearchGroup group;
  final AppStrings strings;
  final ValueChanged<SearchHit> onOpenHit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = switch (group.kind) {
      SearchGroupKind.identifier => strings.searchKindIdentifier,
      SearchGroupKind.particle => strings.searchKindParticle,
      SearchGroupKind.topic => strings.searchKindTopic,
      SearchGroupKind.decay => strings.searchKindDecay,
      SearchGroupKind.reference => strings.searchKindReference,
      SearchGroupKind.text => strings.searchKindText,
      SearchGroupKind.review => strings.searchKindReview,
      SearchGroupKind.note => strings.searchKindNote,
    };
    final icon = switch (group.kind) {
      SearchGroupKind.identifier => Icons.tag,
      SearchGroupKind.particle => Icons.science_outlined,
      SearchGroupKind.topic => Icons.folder_outlined,
      SearchGroupKind.decay => Icons.call_split,
      SearchGroupKind.reference => Icons.menu_book_outlined,
      SearchGroupKind.text => Icons.notes,
      SearchGroupKind.review => Icons.picture_as_pdf_outlined,
      SearchGroupKind.note => Icons.sticky_note_2_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.m, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: palette.textSecondary),
              const SizedBox(width: 5),
              Text(
                '$title · ${group.total}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (group.note != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group.note!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final hit in group.hits)
          _HitTile(hit: hit, onTap: () => onOpenHit(hit), strings: strings),
      ],
    );
  }
}

Widget _searchHitTile(
  BuildContext context, {
  required VoidCallback onTap,
  required Widget title,
  required String subtitle,
}) {
  final palette = context.palette;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    ),
  );
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.onTap,
    required this.strings,
  });

  final SearchHit hit;
  final VoidCallback onTap;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final note = hit.note;
    if (hit.kind == SearchGroupKind.note && note != null) {
      final anchor = note.anchors.isEmpty ? null : note.anchors.first;
      final subtitle = [
        noteUpdatedLabel(note.updatedAt, strings),
        if (anchor != null) anchorDisplayLabel(anchor),
      ].join(' · ');
      return _searchHitTile(
        context,
        onTap: onTap,
        title: Text(
          noteDisplayTitle(note, strings),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle,
      );
    }
    final title = switch (hit.kind) {
      SearchGroupKind.particle => ParticleSymbol(
        hit.title,
        fontSize: 17,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      SearchGroupKind.reference => DescriptionText(
        hit.title,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      _ => DescriptionText(
        hit.title,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 2),
                    Text(
                      hit.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    if (hit.snippet != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: DescriptionText(
                          hit.snippet!,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ),
                    const SizedBox(height: 3),
                    MetaChip(strings.reasonLabel(hit.reason.name)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({
    required this.onOpenCatalog,
    required this.statsFuture,
  });

  final VoidCallback onOpenCatalog;
  final Future<SnapshotStats> statsFuture;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    return Container(
      color: palette.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 48, animate: true),
                const SizedBox(height: Insets.m),
                Text(
                  strings.searchEmptyPrompt,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: Insets.l),
                FilledButton.tonalIcon(
                  onPressed: onOpenCatalog,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: Text(strings.catalogTitle),
                ),
                const SizedBox(height: Insets.l),
                FutureBuilder<SnapshotStats>(
                  future: statsFuture,
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    if (stats == null) return const SizedBox.shrink();
                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Insets.l,
                      runSpacing: Insets.s,
                      children: [
                        _Stat(
                          label: strings.entriesLabel,
                          value: stats.entries,
                        ),
                        _Stat(
                          label: strings.summariesLabel,
                          value: stats.currentSummaries,
                        ),
                        _Stat(
                          label: strings.referencesLabel,
                          value: stats.references,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
