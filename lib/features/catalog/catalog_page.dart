import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/pdg_database.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../common/async_view.dart';
import '../common/description_text.dart';
import '../common/page.dart';
import '../common/ui.dart';
import '../reviews/reviews_page.dart';
import 'catalog_groups.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late Future<List<CatalogRoot>> _future;
  ParticleCategory? _category;
  CatalogGroupKind? _subcategory;
  final TextEditingController _filter = TextEditingController();

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.catalog();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return PageScaffold(
      title: Text(strings.catalogTitle),
      subtitle: strings.catalogSubtitle,
      body: AsyncView<List<CatalogRoot>>(
        future: _future,
        onRetry: () => setState(() {
          _future = AppScope.of(context).repository.catalog();
        }),
        builder: (context, roots) {
          final query = _filter.text.trim().toLowerCase();
          // PDG keeps a few section rows with nothing under them; a tile for
          // those opens an empty page, so they are not listed.
          final visibleRoots = roots
              .where((root) => root.hasContent)
              .toList(growable: false);
          final categoryRoots = visibleRoots
              .where((root) {
                if (_category == null) return true;
                return catalogCategoryForRoot(root) == _category;
              })
              .toList(growable: false);
          final groups = _category == null
              ? const <CatalogGroup>[]
              : catalogGroups(_category!);
          final groupCounts = <CatalogGroupKind, int>{};
          for (final root in categoryRoots) {
            final kind = catalogGroupForRoot(root)?.kind;
            if (kind != null) groupCounts[kind] = (groupCounts[kind] ?? 0) + 1;
          }
          final filtered = categoryRoots
              .where((root) {
                if (_subcategory != null &&
                    catalogGroupForRoot(root)?.kind != _subcategory) {
                  return false;
                }
                return query.isEmpty ||
                    root.entry.description.toLowerCase().contains(query) ||
                    root.entry.pdgid.toLowerCase().contains(query);
              })
              .toList(growable: false);
          final counts = <ParticleCategory, int>{};
          for (final root in visibleRoots) {
            final category = catalogCategoryForRoot(root);
            counts[category] = (counts[category] ?? 0) + 1;
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Insets.xxl),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.m,
                  Insets.l,
                  Insets.s,
                ),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: strings.catalogSearch,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label: Text(
                        '${strings.commonAll} · ${visibleRoots.length}',
                      ),
                      selected: _category == null,
                      onSelected: (_) => setState(() {
                        _category = null;
                        _subcategory = null;
                      }),
                    ),
                    for (final category in particleCategories)
                      FilterChip(
                        label: Text(
                          '${category.label(strings.lang)} · ${counts[category.category] ?? 0}',
                        ),
                        selected: _category == category.category,
                        onSelected: (_) => setState(() {
                          _category = category.category;
                          _subcategory = null;
                        }),
                      ),
                    if ((counts[ParticleCategory.unknown] ?? 0) > 0)
                      FilterChip(
                        label: Text(
                          '${strings.catalogUncategorized} · ${counts[ParticleCategory.unknown] ?? 0}',
                        ),
                        selected: _category == ParticleCategory.unknown,
                        onSelected: (_) => setState(() {
                          _category = ParticleCategory.unknown;
                          _subcategory = null;
                        }),
                      ),
                    if (_category != null &&
                        _category != ParticleCategory.unknown)
                      OutlinedButton.icon(
                        onPressed: () => AppNav.push<void>(
                          context,
                          ReviewsPage(
                            initialFiles:
                                categoryReviewFiles[_category]?.toSet() ??
                                const <String>{},
                          ),
                        ),
                        icon: const Icon(Icons.menu_book_outlined, size: 17),
                        label: Text(strings.reviewsTitle),
                      ),
                  ],
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        label: Text(
                          '${strings.commonAll} · ${categoryRoots.length}',
                        ),
                        selected: _subcategory == null,
                        onSelected: (_) => setState(() => _subcategory = null),
                      ),
                      for (final group in groups)
                        if ((groupCounts[group.kind] ?? 0) > 0)
                          FilterChip(
                            label: DescriptionText(
                              '${group.label(strings.lang)} · ${groupCounts[group.kind]}',
                              maxLines: 1,
                            ),
                            selected: _subcategory == group.kind,
                            onSelected: (_) =>
                                setState(() => _subcategory = group.kind),
                          ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Insets.s),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: Text(
                  '${strings.catalogRoots}: ${filtered.length} / ${visibleRoots.length} · ${strings.commonSnapshot} PDG 2026',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
              if (filtered.isEmpty)
                EmptyPanel(
                  message: strings.searchNoResults,
                  icon: Icons.search_off,
                )
              else
                for (final root in filtered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      0,
                      Insets.l,
                      Insets.s,
                    ),
                    child: _CatalogRootTile(root: root),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _CatalogRootTile extends StatefulWidget {
  const _CatalogRootTile({required this.root});

  final CatalogRoot root;

  @override
  State<_CatalogRootTile> createState() => _CatalogRootTileState();
}

class _CatalogRootTileState extends State<_CatalogRootTile> {
  List<Entry>? _children;
  bool _expanded = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final detailed = scope.settings.detailedMode;
    final palette = context.palette;
    final entry = widget.root.entry;
    final category = widget.root.particleCount == 0
        ? null
        : categoryFromFlags(entry.flags);
    final type = dataTypeInfo(entry.dataType);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => AppNav.openPdgid(context, entry.pdgid),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.m,
                Insets.m,
                Insets.s,
                Insets.m,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DescriptionText(
                          entry.description,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 5,
                          runSpacing: 3,
                          children: [
                            MetaChip(
                              type.label(strings.lang),
                              tone: type.group == PropertyGroup.search
                                  ? BadgeTone.warning
                                  : BadgeTone.neutral,
                            ),
                            if (category != null)
                              MetaChip(category.label(strings.lang)),
                            MetaChip(entry.pdgid),
                            if (detailed &&
                                decodedFlags(
                                  entry.flags,
                                  strings.lang,
                                ).isNotEmpty)
                              MetaChip(
                                decodedFlags(entry.flags, strings.lang),
                                tooltip: 'flags ${entry.flags}',
                              ),
                            if (widget.root.particleCount > 0)
                              MetaChip(
                                '${widget.root.particleCount} ${strings.particleIdentityCount}',
                                tone: BadgeTone.info,
                              ),
                            if (widget.root.childCount > 0)
                              MetaChip(
                                strings.entryCount(widget.root.childCount),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.root.childCount > 0)
                    IconButton(
                      tooltip: _expanded
                          ? strings.commonShowLess
                          : strings.commonShowMore,
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: _toggle,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right, size: 18),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.m,
                0,
                Insets.m,
                Insets.m,
              ),
              child: _loading
                  ? const Center(child: LoadingPanel(compact: true))
                  : Column(
                      children: [
                        for (final child in _children ?? const <Entry>[])
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: DescriptionText(
                              child.description,
                              maxLines: 2,
                            ),
                            subtitle: Text(
                              '${child.pdgid} · ${dataTypeInfo(child.dataType).label(strings.lang)}'
                              '${child.modeNumber == null ? '' : ' · mode ${child.modeNumber}'}',
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 17),
                            onTap: () => AppNav.openPdgid(context, child.pdgid),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loading = _children == null;
    });
    if (_children != null) return;
    try {
      final children = await AppScope.of(context).database
          .children(widget.root.entry.id);
      if (mounted) {
        setState(() {
          _children = children;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
}
