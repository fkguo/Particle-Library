import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/inspire_bibtex.dart';
import '../../data/inspire_literature_search.dart';
import '../../data/pdg_notes.dart';
import '../../data/zotero_bridge.dart';
import '../../data/zotero_cache.dart';
import '../../data/zotero_inspire_api.dart';
import 'inspire_search_field.dart';
import 'inspire_search_help.dart';
import '../common/async_view.dart';

import '../common/context_sidebar.dart';
import '../common/description_text.dart';
import '../common/page.dart';
import '../common/snack_bars.dart';
import '../common/ui.dart';
import '../help/help_page.dart';
import '../common/zotero_icon.dart';
import 'zotero_setup_dialog.dart';
import 'reference_page.dart';

/// Filters that describe opposite states of the same property; enabling one
/// switches its partner off instead of ANDing them into no results.
const Map<String, String> inspireFilterOpposites = {
  'local': 'notLocal',
  'notLocal': 'local',
  'zotero': 'notZotero',
  'notZotero': 'zotero',
  'published': 'preprint',
  'preprint': 'published',
};

/// Toggles [value] in [active], clearing its opposite when enabling.
Set<String> toggleInspireFilter(Set<String> active, String value) {
  final next = Set<String>.of(active);
  if (next.remove(value)) return next;
  final opposite = inspireFilterOpposites[value];
  if (opposite != null) next.remove(opposite);
  next.add(value);
  return next;
}

/// Online INSPIRE search for authors, titles and other bibliographic terms
/// that are not present in the local PDG snapshot.
class InspireSearchPage extends StatefulWidget {
  const InspireSearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<InspireSearchPage> createState() => _InspireSearchPageState();
}

class _InspireSearchPageState extends State<InspireSearchPage> {
  late final TextEditingController _controller;
  final _service = InspireLiteratureSearchService();
  final _zotero = const ZoteroBridge();
  final _zoteroInspire = const ZoteroInspireApi();
  bool get _zoteroSupported =>
      ZoteroBridge.isSupportedPlatform &&
      (AppScope.maybeOf(context)?.settings.zoteroEnabled ?? false);
  bool _zoteroInitialized = false;
  bool? _zoteroAvailable;
  ZoteroInspireStatus? _zoteroInspireStatus;
  int? _zoteroAddBusy;
  Timer? _zoteroProbeTimer;
  int _zoteroProbeAttempts = 0;
  int? _zoteroBusy;
  int? _bibtexBusy;
  final Map<String, Future<String?>> _zoteroKeys = <String, Future<String?>>{};
  List<InspireLiteratureHit> _hits = const <InspireLiteratureHit>[];
  bool _loading = false;
  Object? _error;
  int _generation = 0;
  final Map<String, ({int? id, PdgNoteReference? patch})> _localTargets = {};
  final Map<String, Future<({int? id, PdgNoteReference? patch})>>
  _localFutures = {};
  int _page = 1;
  int _total = 0;
  int _pageSize = 20;
  static const List<int> _pageSizes = [20, 50, 100, 200];
  String _sort = 'mostcited';
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _activeFilters = <String>{};
  final Map<int, bool> _zoteroPresence = <int, bool>{};
  ZoteroCacheIndex? _zoteroCache;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_zoteroInitialized || !_zoteroSupported) return;
    _zoteroInitialized = true;
    unawaited(_loadZoteroCache());
    unawaited(_probeZotero());
  }

  Future<void> _loadZoteroCache() async {
    if (!_zoteroSupported) return;
    final cache = await ZoteroCacheIndex.load();
    if (!mounted) return;
    setState(() {
      _zoteroCache = cache;
      if (cache != null) _zoteroAvailable = true;
    });
    if (cache != null && _hits.isNotEmpty) {
      unawaited(_prefetchPresence(_hits));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _filterController.dispose();
    _searchFocus.dispose();
    _zoteroProbeTimer?.cancel();
    super.dispose();
  }

  Future<void> _search({int? page}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    unawaited(AppScope.of(context).store.addRecent(query, 'inspire'));
    final targetPage = page ?? _page;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.searchPage(
        query,
        page: targetPage,
        size: _pageSize,
        sort: _sort,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = targetPage;
        _hits = result.hits;
        _total = result.total;
        _loading = false;
        _error = null;
      });
      unawaited(_prefetchPresence(result.hits));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _setPageSize(int size) {
    if (_pageSize == size) return;
    setState(() => _pageSize = size);
    if (_controller.text.trim().isNotEmpty) _search(page: 1);
  }

  void _setSort(String value) {
    if (_sort == value) return;
    setState(() => _sort = value);
    if (_controller.text.trim().isNotEmpty) _search(page: 1);
  }

  Future<void> _prefetchPresence(List<InspireLiteratureHit> hits) async {
    if (hits.isEmpty) return;
    final localResults = <String, ({int? id, PdgNoteReference? patch})>{};
    for (var start = 0; start < hits.length; start += 8) {
      final chunk = hits.sublist(
        start,
        (start + 8 < hits.length) ? start + 8 : hits.length,
      );
      final entries = await Future.wait([
        for (final hit in chunk)
          if (hit.doi.trim().isNotEmpty)
            _localTarget(
              hit.doi,
            ).then((target) => MapEntry(hit.doi.trim().toLowerCase(), target)),
      ]);
      for (final entry in entries) {
        localResults[entry.key] = entry.value;
      }
    }
    final zoteroResults = <int, bool>{};
    if (_zoteroAvailable == true && _zoteroCache != null) {
      for (var start = 0; start < hits.length; start += 8) {
        final chunk = hits.sublist(
          start,
          (start + 8 < hits.length) ? start + 8 : hits.length,
        );
        final entries = await Future.wait([
          for (final hit in chunk)
            _zoteroKey(
              hit,
            ).then((key) => MapEntry(hit.recid, key != null && key.isNotEmpty)),
        ]);
        for (final entry in entries) {
          zoteroResults[entry.key] = entry.value;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _localTargets.addAll(localResults);
      _zoteroPresence.addAll(zoteroResults);
    });
  }

  List<String> _inspireHistory() => [
    for (final recent in AppScope.of(context).store.recents)
      if (recent.scope == 'inspire') recent.query,
  ];

  Future<void> _clearInspireHistory() async {
    final store = AppScope.of(context).store;
    for (final query in _inspireHistory()) {
      await store.removeRecent(query, 'inspire');
    }
    if (!mounted) return;
    setState(() {});
    // Close the suggestion overlay once the history is empty.
    _searchFocus.unfocus();
    _searchFocus.requestFocus();
  }

  void _openInspireHelp(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 620) {
      // Wide enough for the shared context sidebar, where the cheat sheet
      // lives; make sure that sidebar is not switched off.
      final settings = AppScope.of(context).settings;
      if (settings.sidebarMode == 'off') {
        unawaited(settings.setSidebarMode('auto'));
      }
      return;
    }
    AppNav.push<void>(context, const HelpPage(initialSection: 'inspire'));
  }

  void _toggleFilter(String value) {
    // Compute before mutating: in a cascade the argument of addAll is
    // evaluated after clear(), so toggling used to re-add the filter.
    final next = toggleInspireFilter(_activeFilters, value);
    setState(() {
      _activeFilters
        ..clear()
        ..addAll(next);
    });
  }

  List<InspireLiteratureHit> get _filteredHits {
    final text = _filterController.text.trim().toLowerCase();
    return _hits
        .where((hit) {
          if (text.isNotEmpty) {
            final haystack = [
              hit.title,
              hit.byline,
              hit.doi,
              hit.arxivId,
              hit.journal,
              hit.year?.toString() ?? '',
            ].join(' ').toLowerCase();
            if (!haystack.contains(text)) return false;
          }
          final doi = hit.doi.trim().toLowerCase();
          final target = doi.isEmpty ? null : _localTargets[doi];
          final localKnown = target != null;
          final local =
              target != null && (target.id != null || target.patch != null);
          if (_activeFilters.contains('local') && !local) return false;
          if (_activeFilters.contains('notLocal') && !(localKnown && !local)) {
            return false;
          }
          final zoteroKnown = _zoteroPresence.containsKey(hit.recid);
          final inZotero = zoteroKnown && _zoteroPresence[hit.recid] == true;
          if (_activeFilters.contains('zotero') && !inZotero) return false;
          if (_activeFilters.contains('notZotero') &&
              !(zoteroKnown && !inZotero)) {
            return false;
          }
          if (_activeFilters.contains('published') && hit.journal.isEmpty) {
            return false;
          }
          if (_activeFilters.contains('preprint') &&
              (hit.journal.isNotEmpty || hit.arxivId.isEmpty)) {
            return false;
          }
          if (_activeFilters.contains('highCited') &&
              hit.citationCount <= 100) {
            return false;
          }
          if (_activeFilters.contains('recent5') &&
              (hit.year == null || hit.year! < DateTime.now().year - 4)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Widget _sortControl(BuildContext context, AppStrings strings) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.inspireSortBy,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(width: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
              value: 'mostcited',
              label: Text(strings.inspireSortCited),
            ),
            ButtonSegment(
              value: 'mostrecent',
              label: Text(strings.inspireSortRecent),
            ),
          ],
          selected: {_sort},
          onSelectionChanged: (value) => _setSort(value.first),
        ),
      ],
    );
  }

  Widget _pageSizeControl(BuildContext context, AppStrings strings) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.inspirePageSize,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: _pageSize,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final size in _pageSizes)
              DropdownMenuItem(
                value: size,
                child: Text(strings.inspirePageSizeValue(size)),
              ),
          ],
          onChanged: _loading
              ? null
              : (value) {
                  if (value != null) _setPageSize(value);
                },
        ),
      ],
    );
  }

  Widget _filterMenu(BuildContext context, AppStrings strings) {
    final entries = <(String, String)>[
      ('local', strings.inspireFilterLocal),
      ('notLocal', strings.inspireFilterNotLocal),
      if (_zoteroSupported && _zoteroCache != null) ...[
        ('zotero', strings.inspireFilterZotero),
        ('notZotero', strings.inspireFilterNotZotero),
      ],
      ('published', strings.inspireFilterPublished),
      ('preprint', strings.inspireFilterPreprint),
      ('highCited', strings.inspireFilterHighCited),
      ('recent5', strings.inspireFilterRecent5),
    ];
    return PopupMenuButton<String>(
      tooltip: strings.inspireFilter,
      onSelected: _toggleFilter,
      icon: Badge(
        isLabelVisible: _activeFilters.isNotEmpty,
        label: Text('${_activeFilters.length}'),
        child: const Icon(Icons.filter_list, size: 20),
      ),
      itemBuilder: (context) => [
        for (final entry in entries)
          CheckedPopupMenuItem<String>(
            value: entry.$1,
            checked: _activeFilters.contains(entry.$1),
            child: Text(entry.$2),
          ),
      ],
    );
  }

  Future<void> _probeZotero() async {
    if (!_zoteroSupported) return;
    final available = await _zotero.isAvailable();
    if (!mounted) return;
    _zoteroProbeTimer?.cancel();
    setState(() => _zoteroAvailable = available || _zoteroCache != null);
    if (available) {
      unawaited(_probeZoteroInspire());
      unawaited(_autoUpdateZoteroCache());
      if (_hits.isNotEmpty) unawaited(_prefetchPresence(_hits));
      return;
    }
    // Zotero may still be starting or its local API may be busy. Probe a
    // couple more times instead of hiding the action for the whole session.
    if (_zoteroProbeAttempts < 2) {
      _zoteroProbeAttempts++;
      _zoteroProbeTimer = Timer(
        const Duration(seconds: 3),
        () => unawaited(_probeZotero()),
      );
    }
  }

  Future<void> _probeZoteroInspire() async {
    if (!_zoteroSupported) return;
    final status = await _zoteroInspire.probe();
    if (!mounted) return;
    setState(() => _zoteroInspireStatus = status);
  }

  Future<void> _addToZotero(InspireLiteratureHit hit) async {
    if (_zoteroAddBusy != null || _zoteroBusy != null) return;
    final strings = AppScope.of(context).strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _zoteroAddBusy = hit.recid);
    try {
      final recid = '${hit.recid}';
      String? existing;
      try {
        existing = await _zotero.findItemKey(
          recid: recid,
          doi: hit.doi,
          arxivId: hit.arxivId,
        );
      } catch (_) {
        // The plugin still checks for duplicates before creating.
      }
      if (!mounted) return;
      if (existing != null && existing.isNotEmpty) {
        _zoteroKeys[recid] = Future<String?>.value(existing);
        setState(() => _zoteroPresence[hit.recid] = true);
        await _launchZoteroItem(existing);
        return;
      }
      final result = await _zoteroInspire.addItemWithPicker(recid);
      if (!mounted || result == null) return;
      _zoteroKeys[recid] = Future<String?>.value(result.itemKey);
      setState(() => _zoteroPresence[hit.recid] = true);
      showActionSnackBar(
        messenger,
        message: result.existing
            ? strings.inspireAlreadyInZotero
            : strings.inspireAddedToZotero,
        actionLabel: strings.zoteroOpen,
        onAction: () => _launchZoteroItem(result.itemKey),
      );
    } on ZoteroInspireException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${strings.inspireAddToZoteroFailed}: ${error.message}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${strings.inspireAddToZoteroFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _zoteroAddBusy = null);
    }
  }

  Future<void> _autoUpdateZoteroCache() async {
    if (!_zoteroSupported || !mounted) return;
    if (!AppScope.of(context).settings.autoUpdateZoteroIndex) return;
    try {
      final index = await ZoteroIndexAutoUpdater.updateIfDue();
      if (!mounted || index == null) return;
      setState(() {
        _zoteroCache = index;
        _zoteroAvailable = true;
      });
      if (_hits.isNotEmpty) unawaited(_prefetchPresence(_hits));
    } catch (_) {
      // The per-row Zotero action still works without the speed cache.
    }
  }

  Future<String?> _zoteroKey(InspireLiteratureHit hit) {
    final recid = '${hit.recid}';
    final cached = _zoteroKeys[recid];
    if (cached != null) return cached;
    final index = _zoteroCache;
    if (index != null) {
      final key = index.findItemKey(
        recid: recid,
        doi: hit.doi,
        arxivId: hit.arxivId,
      );
      // A built index is the fast path. A miss is retried explicitly by the
      // button (or after the user rebuilds the index), not by one HTTP query
      // per visible row.
      return Future<String?>.value(key);
    }
    final future = _zotero.findItemKey(
      recid: recid,
      doi: hit.doi,
      arxivId: hit.arxivId,
    );
    _zoteroKeys[recid] = future;
    // A miss can be transient (Zotero starting, local index still loading).
    // Do not freeze a null result for the lifetime of the page.
    future.then((key) {
      if (key == null && identical(_zoteroKeys[recid], future)) {
        _zoteroKeys.remove(recid);
      }
    });
    return future;
  }

  Future<void> _retryZotero(InspireLiteratureHit hit) async {
    if (_zoteroBusy != null) return;
    final strings = AppScope.of(context).strings;
    setState(() => _zoteroBusy = hit.recid);
    try {
      final recid = '${hit.recid}';
      final key = await _zotero.findItemKey(
        recid: recid,
        doi: hit.doi,
        arxivId: hit.arxivId,
      );
      if (!mounted) return;
      if (key != null && key.isNotEmpty) {
        _zoteroKeys[recid] = Future<String?>.value(key);
        setState(() => _zoteroPresence[hit.recid] = true);
        await _launchZoteroItem(key);
        return;
      }
      _zoteroKeys.remove(recid);
      setState(() => _zoteroPresence[hit.recid] = false);
      final status = _zoteroInspireStatus;
      if (status != null && !status.canAdd) {
        final copy = await showZoteroInspireSetupDialog(
          context,
          strings: strings,
          reason: zoteroSetupReasonFor(status),
          currentVersion: status.version,
          zoteroRunning: _zoteroAvailable == true,
          offerBibtex: true,
        );
        if (!copy || !mounted) return;
      }
      final bibtex = await const InspireBibtexService().fetchBibtex(
        inspireId: recid,
        doi: hit.doi,
      );
      if (!mounted) return;
      await copyText(
        context,
        bibtex,
        message: strings.inspireZoteroNotFoundCopied,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.inspireZoteroFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _zoteroBusy = null);
    }
  }

  Future<void> _copyBibtex(InspireLiteratureHit hit) async {
    if (_bibtexBusy != null) return;
    final strings = AppScope.of(context).strings;
    setState(() => _bibtexBusy = hit.recid);
    try {
      final text = await const InspireBibtexService().fetchBibtex(
        inspireId: '${hit.recid}',
        doi: hit.doi,
      );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.referenceBibtexCopied)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.referenceBibtexFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _bibtexBusy = null);
    }
  }

  Future<void> _openZoteroItem(InspireLiteratureHit hit, String key) async {
    if (_zoteroBusy != null) return;
    setState(() => _zoteroBusy = hit.recid);
    try {
      await _launchZoteroItem(key);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppScope.of(context).strings.inspireZoteroFailed}: ${errorText(error, AppScope.of(context).strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _zoteroBusy = null);
    }
  }

  Future<void> _launchZoteroItem(String key) => launchUrl(
    Uri.parse('zotero://select/library/items/$key'),
    mode: LaunchMode.externalApplication,
  );

  Future<({int? id, PdgNoteReference? patch})> _localTarget(String doi) {
    final key = doi.trim().toLowerCase();
    if (key.isEmpty) return Future.value((id: null, patch: null));
    final cached = _localTargets[key];
    if (cached != null) return Future.value(cached);
    return _localFutures.putIfAbsent(key, () async {
      try {
        final references = await AppScope.of(context).database
            .referencesByDoi(key);
        final id = references.isEmpty ? null : references.first.id;
        final patch = id == null ? await PdgNotes.referenceForDoi(key) : null;
        final target = (id: id, patch: patch);
        if (mounted) setState(() => _localTargets[key] = target);
        return target;
      } catch (_) {
        const target = (id: null, patch: null);
        if (mounted) setState(() => _localTargets[key] = target);
        return target;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final filtered = _filteredHits;
    return PageScaffold(
      title: Text(strings.inspireSearchTitle),
      subtitle: strings.inspireSearchSubtitle,
      maxWidth: 960,
      showSidebarToggle: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.l,
              Insets.m,
              Insets.l,
              Insets.xxl,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: InspireSearchField(
                      controller: _controller,
                      focusNode: _searchFocus,
                      hintText: strings.inspireSearchHint,
                      searchTooltip: strings.inspireSearchAction,
                      history: _inspireHistory,
                      onSearch: () => _search(page: 1),
                      onClearHistory: () => unawaited(_clearInspireHistory()),
                    ),
                  ),
                  if (!showContextSidebar(
                    context,
                    MediaQuery.sizeOf(context).width,
                  ))
                    IconButton(
                      tooltip: strings.inspireHelpTitle,
                      onPressed: () => _openInspireHelp(context),
                      icon: const Icon(Icons.help_outline, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: Insets.s),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filterController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: strings.inspireFilterHint,
                        prefixIcon: const Icon(
                          Icons.filter_alt_outlined,
                          size: 18,
                        ),
                        suffixIcon: _filterController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: strings.commonClear,
                                onPressed: () {
                                  _filterController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close, size: 16),
                              ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _filterMenu(context, strings),
                ],
              ),
              if (_activeFilters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      for (final entry in <(String, String)>[
                        ('local', strings.inspireFilterLocal),
                        ('notLocal', strings.inspireFilterNotLocal),
                        if (_zoteroCache != null) ...[
                          ('zotero', strings.inspireFilterZotero),
                          ('notZotero', strings.inspireFilterNotZotero),
                        ],
                        ('published', strings.inspireFilterPublished),
                        ('preprint', strings.inspireFilterPreprint),
                        ('highCited', strings.inspireFilterHighCited),
                        ('recent5', strings.inspireFilterRecent5),
                      ])
                        if (_activeFilters.contains(entry.$1))
                          InputChip(
                            label: Text(entry.$2),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () => _toggleFilter(entry.$1),
                          ),
                    ],
                  ),
                ),
              if (_zoteroSupported &&
                  _zoteroAvailable == true &&
                  _zoteroCache == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    strings.inspireZoteroCacheHint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.m),
                  child: Row(
                    children: [
                      const BrandMark(size: 28, animate: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.commonLoading,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 3),
                            const LinearProgressIndicator(minHeight: 2),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.m),
                  child: ErrorPanel(
                    error: _error!,
                    onRetry: () => _search(page: _page),
                  ),
                ),
              if (!_loading && _error == null && _hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.l),
                  child: EmptyPanel(
                    message: strings.inspireSearchEmpty,
                    icon: Icons.search_off,
                  ),
                ),
              if (!_loading &&
                  _error == null &&
                  _hits.isNotEmpty &&
                  filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.l),
                  child: EmptyPanel(
                    message: strings.inspireFilterNoResults,
                    icon: Icons.filter_alt_off_outlined,
                  ),
                ),
              if (_hits.isNotEmpty) ...[
                const SizedBox(height: Insets.m),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = Text(
                      _activeFilters.isNotEmpty ||
                              _filterController.text.trim().isNotEmpty
                          ? strings.inspireFilteredShowing(
                              filtered.length,
                              _hits.length,
                            )
                          : _total > _hits.length
                          ? strings.inspireShowing(_hits.length, _total)
                          : strings.inspireSearchResults(_total),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: palette.textSecondary),
                    );
                    final controls = Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _pageSizeControl(context, strings),
                        _sortControl(context, strings),
                      ],
                    );
                    if (constraints.maxWidth < 620) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [count, const SizedBox(height: 4), controls],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: count),
                        const SizedBox(width: 12),
                        controls,
                      ],
                    );
                  },
                ),
                for (final hit in filtered) _hitTile(context, hit, strings),
                _pagination(context, strings),
              ],
            ],
          );
          if (!showContextSidebar(context, constraints.maxWidth)) {
            return content;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              ResizableContextSidebar(
                viewportWidth: constraints.maxWidth,
                child: ContextSidebar(
                  facts: const <SidebarFact>[],
                  sections: const <Widget>[InspireSearchHelp()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pagination(BuildContext context, AppStrings strings) {
    final pages = _total <= 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.m, bottom: Insets.m),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: strings.inspirePrevious,
            onPressed: _loading || _page <= 1
                ? null
                : () => _search(page: _page - 1),
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          Text(
            strings.inspirePage(_page, pages),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          IconButton(
            tooltip: strings.inspireNext,
            onPressed: _loading || _page >= pages
                ? null
                : () => _search(page: _page + 1),
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }

  String _publicationLine(
    BuildContext context,
    InspireLiteratureHit hit,
    AppStrings strings,
  ) {
    final journal = hit.journal.trim();
    final publication = <String>[
      if (journal.isNotEmpty) journal,
      if (hit.journalVolume.isNotEmpty) hit.journalVolume,
      if (hit.year != null) journal.isEmpty ? '${hit.year}' : '(${hit.year})',
      if (hit.journalPage.isNotEmpty) hit.journalPage,
    ].join(' ');
    return [
      if (publication.isNotEmpty) publication,
      if (hit.doi.isNotEmpty) 'DOI ${hit.doi}',
      if (hit.arxivId.isNotEmpty) 'arXiv:${hit.arxivId}',
      strings.inspireCitations(hit.citationCount),
    ].join(' · ');
  }

  Widget _zoteroButton(
    BuildContext context,
    InspireLiteratureHit hit,
    AppStrings strings,
  ) {
    final palette = context.palette;
    final canAdd = _zoteroInspireStatus?.canAdd == true;
    final busy = _zoteroBusy == hit.recid || _zoteroAddBusy == hit.recid;
    final disabled = _zoteroBusy != null || _zoteroAddBusy != null;
    if (_zoteroCache == null) {
      // Zotero is running but no item index has been built yet. Let the
      // single-button flow do the lookup only when pressed, instead of one
      // HTTP query per row.
      return Tooltip(
        message: canAdd
            ? strings.inspireZoteroFindOrAdd
            : strings.inspireZoteroFind,
        child: OutlinedButton.icon(
          onPressed: disabled
              ? null
              : () => canAdd ? _addToZotero(hit) : _retryZotero(hit),
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const ZoteroIcon(size: 16),
          label: Text(strings.inspireZotero),
        ),
      );
    }
    return FutureBuilder<String?>(
      future: _zoteroKey(hit),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final key = snapshot.data;
        final inZotero = key != null && key.isNotEmpty;
        return Tooltip(
          message: loading
              ? strings.commonLoading
              : inZotero
              ? strings.zoteroOpen
              : canAdd
              ? strings.inspireZoteroFindOrAdd
              : strings.inspireZoteroRetry,
          child: OutlinedButton.icon(
            style: inZotero
                ? null
                : OutlinedButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                    side: BorderSide(color: palette.divider),
                  ),
            onPressed: loading || disabled
                ? null
                : () => inZotero
                      ? _openZoteroItem(hit, key)
                      : canAdd
                      ? _addToZotero(hit)
                      : _retryZotero(hit),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const ZoteroIcon(size: 16),
            label: Text(strings.inspireZotero),
          ),
        );
      },
    );
  }

  Widget _hitTile(
    BuildContext context,
    InspireLiteratureHit hit,
    AppStrings strings,
  ) {
    final palette = context.palette;
    return Card(
      margin: const EdgeInsets.only(top: Insets.s),
      child: Padding(
        padding: const EdgeInsets.all(Insets.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DescriptionText(
              hit.title,
              selectable: true,
              maxLines: 3,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                // Tighten the default 1.5 line box: the card title sits right
                // above the byline and the theme's regular leading left a
                // visible gap.
                height: 1.25,
              ),
            ),
            if (hit.bylineShort.isNotEmpty) ...[
              const SizedBox(height: 2),
              SelectableText(
                hit.bylineShort,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary, height: 1.3),
              ),
            ],
            const SizedBox(height: 4),
            SelectableText(
              _publicationLine(context, hit, strings),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FutureBuilder<({int? id, PdgNoteReference? patch})>(
                  future: _localTarget(hit.doi),
                  builder: (context, snapshot) {
                    final target = snapshot.data;
                    final id = target?.id;
                    final patch = target?.patch;
                    final enabled = id != null || patch != null;
                    return Tooltip(
                      message: enabled
                          ? strings.inspireSearchOpenLocal
                          : strings.inspireSearchNoLocal,
                      child: OutlinedButton.icon(
                        onPressed: !enabled
                            ? null
                            : () => AppNav.push<void>(
                                context,
                                id != null
                                    ? ReferencePage(referenceId: id)
                                    : ReferencePage.patch(patch: patch!),
                              ),
                        icon: Icon(
                          enabled ? Icons.menu_book_outlined : Icons.menu_book,
                          size: 16,
                        ),
                        label: Text(strings.inspireSearchOpenLocal),
                      ),
                    );
                  },
                ),
                if (_zoteroSupported && _zoteroAvailable == true)
                  _zoteroButton(context, hit, strings),
                Tooltip(
                  message: strings.referenceCopyBibtex,
                  child: OutlinedButton.icon(
                    onPressed: _bibtexBusy == null
                        ? () => _copyBibtex(hit)
                        : null,
                    icon: _bibtexBusy == hit.recid
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.copy_all, size: 16),
                    label: Text(
                      _bibtexBusy == hit.recid
                          ? strings.referenceCopyBibtexRunning
                          : strings.referenceCopyBibtex,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(hit.inspireUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(strings.inspireSearchOpenInspire),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
