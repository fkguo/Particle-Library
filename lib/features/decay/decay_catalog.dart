import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../common/description_text.dart';
import '../common/display_value.dart';
import '../common/ui.dart';

class DecayCatalog extends StatefulWidget {
  const DecayCatalog({
    super.key,
    required this.parent,
    required this.decays,
    required this.summariesByEntry,
    required this.summaryCounts,
    required this.measurementCounts,
    required this.currentEdition,
  });

  final Entry parent;
  final List<Entry> decays;
  final Map<int, List<Summary>> summariesByEntry;
  final Map<int, int> summaryCounts;
  final Map<int, int> measurementCounts;
  final String currentEdition;

  @override
  State<DecayCatalog> createState() => _DecayCatalogState();
}

class _DecayCatalogState extends State<DecayCatalog> {
  static const int _pageSize = 80;

  final TextEditingController _filter = TextEditingController();
  final Set<int> _expanded = {};
  bool _flat = false;
  int _visibleLimit = _pageSize;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Map<int, List<Entry>> _children() {
    final ids = {for (final row in widget.decays) row.id};
    final map = <int, List<Entry>>{};
    for (final row in widget.decays) {
      final parent = row.parentId != null && ids.contains(row.parentId)
          ? row.parentId!
          : widget.parent.id;
      map.putIfAbsent(parent, () => []).add(row);
    }
    for (final list in map.values) {
      list.sort(
        (a, b) =>
            a.sort != b.sort ? a.sort.compareTo(b.sort) : a.id.compareTo(b.id),
      );
    }
    return map;
  }

  List<Entry> _path(Entry row, Map<int, Entry> byId) {
    final path = <Entry>[];
    var current = byId[row.parentId];
    var guard = 0;
    while (current != null && current.id != widget.parent.id && guard < 20) {
      path.insert(0, current);
      current = byId[current.parentId];
      guard++;
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final children = _children();
    final query = _filter.text.trim().toLowerCase();
    final byId = {for (final row in widget.decays) row.id: row};
    final filtered = query.isEmpty
        ? const <Entry>[]
        : widget.decays
              .where((row) => row.description.toLowerCase().contains(query))
              .toList(growable: false);
    final roots = children[widget.parent.id] ?? const <Entry>[];
    final visibleRoots = roots.take(_visibleLimit).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() => _visibleLimit = _pageSize),
                  decoration: InputDecoration(
                    hintText: strings.decaySearchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Insets.s),
              IconButton(
                tooltip: _flat ? strings.decayTree : strings.decayFlat,
                icon: Icon(
                  _flat
                      ? Icons.account_tree_outlined
                      : Icons.view_list_outlined,
                ),
                onPressed: () => setState(() => _flat = !_flat),
              ),
              IconButton(
                tooltip: strings.decayExpandAll,
                icon: const Icon(Icons.unfold_more, size: 19),
                onPressed: () => setState(
                  () => _expanded.addAll(widget.decays.map((row) => row.id)),
                ),
              ),
              IconButton(
                tooltip: strings.decayCollapseAll,
                icon: const Icon(Icons.unfold_less, size: 19),
                onPressed: () => setState(_expanded.clear),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
          child: Row(
            children: [
              MetaChip(
                '${widget.decays.length} ${strings.decayModeCount}',
                tone: BadgeTone.info,
              ),
            ],
          ),
        ),
        if (widget.decays.isEmpty)
          EmptyPanel(message: strings.particleNoDecays, icon: Icons.call_split)
        else if (query.isNotEmpty)
          if (filtered.isEmpty)
            EmptyPanel(
              message: strings.decayNoModesMatch,
              icon: Icons.search_off,
            )
          else ...[
            for (final row in filtered.take(_visibleLimit))
              _DecayTile(
                entry: row,
                depth: 0,
                path: _path(row, byId),
                summaryRows: widget.summariesByEntry[row.id] ?? const [],
                measurementCount: widget.measurementCounts[row.id] ?? 0,
                hasChildren: false,
                expanded: false,
                onToggle: null,
                onOpen: () => AppNav.openPdgid(context, row.pdgid),
              ),
            if (filtered.length > _visibleLimit)
              _showMore(context, strings, filtered.length - _visibleLimit),
          ]
        else ...[
          for (final root in visibleRoots) ..._buildTree(root, children, 0),
          if (roots.length > _visibleLimit)
            _showMore(context, strings, roots.length - _visibleLimit),
        ],
      ],
    );
  }

  Widget _showMore(BuildContext context, AppStrings strings, int remaining) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
        child: TextButton.icon(
          onPressed: () => setState(() => _visibleLimit += _pageSize),
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text(strings.decayMoreModes(remaining)),
        ),
      ),
    );
  }

  List<Widget> _buildTree(
    Entry row,
    Map<int, List<Entry>> children,
    int depth,
  ) {
    final childList = children[row.id] ?? const <Entry>[];
    final isExpanded = _flat || _expanded.contains(row.id);
    return [
      _DecayTile(
        entry: row,
        depth: depth,
        path: const [],
        summaryRows: widget.summariesByEntry[row.id] ?? const [],
        measurementCount: widget.measurementCounts[row.id] ?? 0,
        hasChildren: childList.isNotEmpty,
        expanded: isExpanded,
        onToggle: childList.isEmpty
            ? null
            : () => setState(() {
                if (_expanded.contains(row.id)) {
                  _expanded.remove(row.id);
                } else {
                  _expanded.add(row.id);
                }
              }),
        onOpen: () => AppNav.openPdgid(context, row.pdgid),
      ),
      if (isExpanded)
        for (final child in childList)
          ..._buildTree(child, children, depth + 1),
    ];
  }
}

class _DecayTile extends StatelessWidget {
  const _DecayTile({
    required this.entry,
    required this.depth,
    required this.path,
    required this.summaryRows,
    required this.measurementCount,
    required this.hasChildren,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final Entry entry;
  final int depth;
  final List<Entry> path;
  final List<Summary> summaryRows;
  final int measurementCount;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final selection = selectBestSummary(summaryRows);
    final type = dataTypeInfo(entry.dataType);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Insets.l + (depth * 14.0).clamp(0, 56),
            7,
            Insets.m,
            7,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: hasChildren
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        tooltip: expanded
                            ? strings.commonShowLess
                            : strings.commonShowMore,
                        icon: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                        ),
                        onPressed: onToggle,
                      )
                    : Icon(Icons.circle, size: 4, color: palette.textSecondary),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (depth > 0 && path.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(
                          path.map((row) => row.description).join(' › '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textSecondary,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    DescriptionText(
                      entry.description,
                      maxLines: 3,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MetaChip(
                          type.label(strings.lang),
                          tone: isBranchingRatioType(entry.dataType)
                              ? BadgeTone.accent
                              : BadgeTone.neutral,
                        ),
                        if (entry.modeNumber != null)
                          MetaChip('mode ${entry.modeNumber}'),
                        if (entry.flags.isNotEmpty)
                          MetaChip('flags ${entry.flags}'),
                        _SummaryInline(selection: selection, strings: strings),
                        if (measurementCount > 0)
                          Text(
                            strings.measurementCount(measurementCount),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryInline extends StatelessWidget {
  const _SummaryInline({required this.selection, required this.strings});

  final SummarySelection selection;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (selection.isEmpty) {
      return MetaChip(strings.seriesNoSummary, tone: BadgeTone.warning);
    }
    if (selection.isAmbiguous) {
      return MetaChip(
        strings.candidateCount(selection.count),
        tone: BadgeTone.warning,
      );
    }
    final quantity = DisplayQuantity.fromSummary(selection.preferred!);
    return DisplayValueView(quantity, fontSize: 13);
  }
}
