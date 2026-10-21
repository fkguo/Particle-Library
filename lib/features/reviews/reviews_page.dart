import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/review_cache.dart';
import '../common/description_text.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/ui.dart';
import 'review_index.dart';
import 'review_viewer_page.dart';

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key, this.initialFiles = const <String>{}});

  /// Exact review PDFs for a PDG Live category-level reviews button.
  final Set<String> initialFiles;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  _ReviewCacheFilter _cacheFilter = _ReviewCacheFilter.all;
  ReviewCache? _cache;
  Set<String> _cached = {};
  final Map<String, GlobalKey> _groupKeys = {};
  int _cachedBytes = 0;
  String? _downloadingFile;
  double? _downloadProgress;
  bool _bulkRunning = false;
  bool _bulkCancel = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;
  String? _cacheError;

  List<ReviewEntry> get _allEntries => [
    for (final group in reviewGroups) ...group.entries,
  ];

  List<ReviewEntry> get _allowedEntries {
    final allowed = widget.initialFiles;
    return [
      for (final entry in _allEntries)
        if (allowed.isEmpty || allowed.contains(entry.file)) entry,
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    try {
      final cache = await ReviewCache.open();
      final names = _allEntries.map((entry) => entry.file).toList();
      final cached = await cache.cachedFiles(names);
      final bytes = await cache.cachedBytes(names);
      if (!mounted) return;
      setState(() {
        _cache = cache;
        _cached = cached;
        _cachedBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _cacheError = errorText(error, AppScope.of(context).strings),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(BuildContext context, ReviewEntry entry) async {
    final cache = _cache;
    if (cache == null) return;
    if (!_cached.contains(entry.file)) {
      final downloaded = await _download(entry);
      if (!downloaded) return;
    }
    final local = cache.fileFor(entry.file);
    if (!await local.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewsOpenFailed)),
      );
      return;
    }
    if (!context.mounted) return;
    await AppNav.push<void>(
      context,
      ReviewViewerPage(
        title: entry.title,
        path: local.path,
        officialUrl: entry.url,
      ),
    );
  }

  Future<bool> _download(ReviewEntry entry, {bool quiet = false}) async {
    final strings = AppScope.of(context).strings;
    final cache = _cache;
    if (cache == null) return false;
    if (_cached.contains(entry.file)) return true;
    setState(() {
      _downloadingFile = entry.file;
      _downloadProgress = null;
    });
    try {
      final file = await cache.download(
        fileName: entry.file,
        url: entry.url,
        onProgress: (received, total) {
          if (!mounted || _downloadingFile != entry.file) return;
          setState(() {
            _downloadProgress = total == null || total <= 0
                ? null
                : received / total;
          });
        },
      );
      final names = _allEntries.map((review) => review.file).toList();
      final bytes = await cache.cachedBytes(names);
      if (!mounted) return true;
      setState(() {
        _cached.add(entry.file);
        _cachedBytes = bytes;
        _downloadingFile = null;
        _downloadProgress = null;
      });
      final size = _formatBytes(await file.length());
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${strings.reviewsCached}: ${entry.title} ($size)'),
          ),
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _downloadingFile = null;
        _downloadProgress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.reviewsDownloadFailed} ${errorText(error, strings)}',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _downloadAll() async {
    if (_bulkRunning) return;
    final pending = _allEntries
        .where((entry) => !_cached.contains(entry.file))
        .toList(growable: false);
    if (pending.isEmpty) return;
    setState(() {
      _bulkRunning = true;
      _bulkCancel = false;
      _bulkDone = 0;
      _bulkTotal = pending.length;
    });
    var failed = 0;
    for (final entry in pending) {
      if (_bulkCancel) break;
      final ok = await _download(entry, quiet: true);
      if (!ok) failed++;
      if (!mounted) return;
      setState(() => _bulkDone++);
    }
    if (!mounted) return;
    setState(() {
      _bulkRunning = false;
      _downloadingFile = null;
      _downloadProgress = null;
    });
    final strings = AppScope.of(context).strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? strings.reviewsCacheAllDone
              : '${strings.reviewsCacheAllDone} ($failed)',
        ),
      ),
    );
  }

  Future<void> _manageCache() async {
    final cache = _cache;
    if (cache == null) return;
    final strings = AppScope.of(context).strings;
    final entries = [
      for (final entry in _allEntries)
        if (_cached.contains(entry.file)) entry,
    ];
    if (entries.isEmpty) return;
    final sizes = <String, int>{};
    for (final entry in entries) {
      sizes[entry.file] = await cache.cachedBytes([entry.file]);
    }
    if (!mounted) return;

    final selected = <String>{};
    final choice = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.reviewsManageCache),
          content: SizedBox(
            width: 520,
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.reviewsCacheSelectHint,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.palette.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(entries.map((entry) => entry.file));
                      }),
                      child: Text(strings.reviewsSelectAll),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(selected.clear),
                      child: Text(strings.reviewsSelectNone),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in entries)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(entry.file),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selected.add(entry.file);
                            } else {
                              selected.remove(entry.file);
                            }
                          }),
                          title: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${entry.file} · ${_formatBytes(sizes[entry.file] ?? 0)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.commonCancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected),
              child: Text(strings.reviewsDeleteSelected(selected.length)),
            ),
          ],
        ),
      ),
    );
    if (choice == null || choice.isEmpty || !mounted) return;
    await cache.removeFiles(choice);
    if (!mounted) return;
    final names = _allEntries.map((entry) => entry.file).toList();
    final cached = await cache.cachedFiles(names);
    final bytes = await cache.cachedBytes(names);
    if (!mounted) return;
    setState(() {
      _cached = cached;
      _cachedBytes = bytes;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.reviewsCacheRemoved(choice.length))),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<void> _showIntroHelp(BuildContext context, AppStrings strings) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.reviewsTitle),
        content: SingleChildScrollView(child: Text(strings.reviewsIntro)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.commonClose),
          ),
        ],
      ),
    );
  }

  GlobalKey _groupKey(ReviewGroup group) =>
      _groupKeys.putIfAbsent(group.titleEn, () => GlobalKey());

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final zh = strings.lang.name == 'zh';
    final query = _query.trim().toLowerCase();
    final groups = <({ReviewGroup group, List<ReviewEntry> entries})>[];
    final allowed = widget.initialFiles;
    for (final group in reviewGroups) {
      final groupMatches =
          query.isEmpty ||
          group.titleZh.toLowerCase().contains(query) ||
          group.titleEn.toLowerCase().contains(query);
      final entries = group.entries
          .where((entry) => allowed.isEmpty || allowed.contains(entry.file))
          .where(
            (entry) =>
                groupMatches || entry.title.toLowerCase().contains(query),
          )
          .where((entry) {
            return switch (_cacheFilter) {
              _ReviewCacheFilter.all => true,
              _ReviewCacheFilter.cached => _cached.contains(entry.file),
              _ReviewCacheFilter.notCached => !_cached.contains(entry.file),
            };
          })
          .toList(growable: false);
      if (entries.isNotEmpty) groups.add((group: group, entries: entries));
    }
    final total = groups.fold<int>(0, (sum, item) => sum + item.entries.length);
    final allCached = _cached.length >= _allEntries.length;
    final outlineItems = [
      for (final item in groups)
        PageOutlineItem(
          label: zh ? item.group.titleZh : item.group.titleEn,
          target: _groupKey(item.group),
          icon: Icons.folder_outlined,
        ),
    ];

    return PageScaffold(
      maxWidth: double.infinity,
      title: Text(strings.reviewsTitle),
      subtitle: strings.reviewsSubtitle,
      actions: [
        if (outlineItems.isNotEmpty)
          IconButton(
            tooltip: strings.reviewOutlineTab,
            onPressed: () => showPageOutlineSheet(
              context,
              label: strings.reviewOutlineTab,
              items: outlineItems,
              onSelect: (item) {
                if (item.onTap != null) {
                  item.onTap!();
                } else if (item.target != null) {
                  scrollToOutlineTarget(item.target!);
                }
              },
            ),
            icon: const Icon(Icons.toc, size: 20),
          ),
        IconButton(
          tooltip: strings.settingsHelp,
          onPressed: () => _showIntroHelp(context, strings),
          icon: const Icon(Icons.help_outline, size: 20),
        ),
      ],
      body: PageOutlineScaffold(
        label: strings.reviewOutlineTab,
        items: outlineItems,
        minWidth: 560,
        showNarrowButton: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Insets.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: TextField(
                  controller: _controller,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 19),
                    hintText: strings.reviewsSearchHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.commonClear,
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: Text(
                        '${strings.reviewsFilterAll} · ${_allowedEntries.length}',
                      ),
                      selected: _cacheFilter == _ReviewCacheFilter.all,
                      onSelected: (_) =>
                          setState(() => _cacheFilter = _ReviewCacheFilter.all),
                    ),
                    FilterChip(
                      label: Text(
                        '${strings.reviewsFilterCached} · ${_allowedEntries.where((entry) => _cached.contains(entry.file)).length}',
                      ),
                      selected: _cacheFilter == _ReviewCacheFilter.cached,
                      onSelected: (_) => setState(
                        () => _cacheFilter = _ReviewCacheFilter.cached,
                      ),
                    ),
                    FilterChip(
                      label: Text(
                        '${strings.reviewsFilterNotCached} · ${_allowedEntries.where((entry) => !_cached.contains(entry.file)).length}',
                      ),
                      selected: _cacheFilter == _ReviewCacheFilter.notCached,
                      onSelected: (_) => setState(
                        () => _cacheFilter = _ReviewCacheFilter.notCached,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh
                          ? '共 $total 篇 · PDG $reviewEdition'
                          : '$total reviews · PDG $reviewEdition',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          strings.reviewsCacheStatus(
                            _cached.length,
                            _allEntries.length,
                            _formatBytes(_cachedBytes),
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                        OutlinedButton.icon(
                          onPressed: _cache == null || _bulkRunning || allCached
                              ? null
                              : () => _downloadAll(),
                          icon: const Icon(
                            Icons.download_for_offline_outlined,
                            size: 17,
                          ),
                          label: Text(
                            allCached
                                ? strings.reviewsCached
                                : _bulkRunning
                                ? strings.reviewsBulkProgress(
                                    _bulkDone,
                                    _bulkTotal,
                                  )
                                : strings.reviewsCacheAll,
                          ),
                        ),
                        if (_bulkRunning)
                          TextButton(
                            onPressed: () => setState(() => _bulkCancel = true),
                            child: Text(strings.reviewsStop),
                          ),
                        if (_cached.isNotEmpty)
                          TextButton.icon(
                            onPressed: _bulkRunning ? null : _manageCache,
                            icon: const Icon(Icons.delete_outline, size: 17),
                            label: Text(strings.reviewsManageCache),
                          ),
                      ],
                    ),
                    if (_bulkRunning)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: _bulkTotal == 0
                              ? null
                              : _bulkDone / _bulkTotal,
                        ),
                      )
                    else if (_downloadProgress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                        ),
                      ),
                    if (_cacheError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _cacheError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.warning),
                        ),
                      ),
                  ],
                ),
              ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                  child: EmptyPanel(
                    message: strings.reviewsEmpty,
                    icon: Icons.menu_book_outlined,
                  ),
                )
              else
                for (final item in groups)
                  Padding(
                    key: _groupKey(item.group),
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      0,
                      Insets.l,
                      Insets.s,
                    ),
                    child: SectionCard(
                      titleWidget: DescriptionText(
                        zh ? item.group.titleZh : item.group.titleEn,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: zh
                          ? '${item.entries.length} 篇'
                          : '${item.entries.length} reviews',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < item.entries.length; i++)
                            _ReviewTile(
                              entry: item.entries[i],
                              last: i == item.entries.length - 1,
                              cached: _cached.contains(item.entries[i].file),
                              downloading:
                                  _downloadingFile == item.entries[i].file,
                              progress: _downloadingFile == item.entries[i].file
                                  ? _downloadProgress
                                  : null,
                              onTap: () => _open(context, item.entries[i]),
                              onDownload: _bulkRunning
                                  ? null
                                  : () => _download(item.entries[i]),
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.entry,
    required this.last,
    required this.cached,
    required this.downloading,
    required this.onTap,
    this.onDownload,
    this.progress,
  });

  final ReviewEntry entry;
  final bool last;
  final bool cached;
  final bool downloading;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: last ? 5 : 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DescriptionText(
                    entry.title,
                    maxLines: 3,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PDG $reviewEdition · PDF',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            // Keep every action in the same 40 px slot. The cached state used
            // to be a bare 18 px icon while the download state was a 48 px
            // IconButton, so the two columns visibly disagreed.
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: downloading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                        ),
                      )
                    : cached
                    ? Tooltip(
                        message: AppScope.of(context).strings.reviewsCached,
                        child: Icon(
                          Icons.offline_pin,
                          size: 18,
                          color: palette.accent,
                        ),
                      )
                    : IconButton(
                        tooltip: AppScope.of(context).strings.reviewsDownload,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        onPressed: onDownload,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReviewCacheFilter { all, cached, notCached }
