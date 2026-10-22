import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/pdg_database.dart';
import '../../data/pdg_notes.dart';
import '../../domain/aliases.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/reference_title.dart';
import '../../domain/models.dart';
import '../../domain/views.dart';
import '../common/async_view.dart';
import '../common/context_sidebar.dart';
import '../common/citation_text.dart';
import '../common/description_text.dart';
import '../common/pdg_live_text.dart';
import '../common/display_value.dart';
import '../common/favorite_button.dart';
import '../common/math_text.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/raw_fields.dart';
import '../common/ui.dart';
import '../catalog/catalog_groups.dart';
import '../reviews/reviews_page.dart';
import '../decay/decay_catalog.dart';
import '../notes/notes_anchor.dart';
import '../notes/notes_entity.dart';

class ParticlePage extends StatefulWidget {
  const ParticlePage({super.key, required this.entry});

  final Entry entry;

  @override
  State<ParticlePage> createState() => _ParticlePageState();
}

class _ParticlePageState extends State<ParticlePage> {
  late Future<ParticleView> _future;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.loadParticle(widget.entry);
  }

  void _retry() {
    setState(() {
      _future = AppScope.of(context).repository.loadParticle(widget.entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final title = widget.entry.description;
    final notes = particleNotesContext(
      widget.entry,
      snapshotHash: scope.snapshotHash,
    );
    return PageScaffold(
      showSidebarToggle: true,
      maxWidth: 1480,
      noteAnchors: notes.anchors,
      noteLabel: notes.label,
      title: ParticleSymbol(title, fontSize: 20),
      subtitle: 'PDG ${scope.database.currentEdition} · ${widget.entry.pdgid}',
      actions: [
        FavoriteButton(
          favorite: entryFavorite(
            entry: widget.entry,
            snapshotHash: scope.snapshotHash,
          ),
        ),
        EntityNotesButton(targets: notes.targets, anchors: notes.anchors),
        CopyButton(
          text: [
            title,
            'PDG ${widget.entry.pdgid}',
            'PDG ${scope.database.currentEdition}',
          ].join('\n'),
          compact: true,
        ),
      ],
      body: AsyncView<ParticleView>(
        future: _future,
        onRetry: _retry,
        builder: (context, view) => _ParticleBody(view: view),
      ),
    );
  }
}

class _ParticleBody extends StatefulWidget {
  const _ParticleBody({required this.view});

  final ParticleView view;

  @override
  State<_ParticleBody> createState() => _ParticleBodyState();
}

class _ParticleBodyState extends State<_ParticleBody> {
  int _tab = 0;
  PdgNote? _pdgNote;
  Map<String, PdgCitation> _citations = const <String, PdgCitation>{};
  final GlobalKey _overviewKey = GlobalKey();
  final GlobalKey _tabsKey = GlobalKey();
  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _keyPropertiesKey = GlobalKey();
  final GlobalKey _notesKey = GlobalKey();
  final GlobalKey _textsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPdgNote());
    });
  }

  Future<void> _loadPdgNote() async {
    final note = await PdgNotes.forPdgid(widget.view.entry.pdgid);
    if (!mounted || note == null || note.isEmpty) return;
    var localIds = const <String, int>{};
    if (note.citations.isNotEmpty) {
      try {
        localIds = await AppScope.of(context).database
            .referenceIdsForCitationKeys(note.citations.keys.toSet());
      } catch (_) {
        // Links fall back to INSPIRE.
      }
    }
    final patchReferences = <String, PdgNoteReference>{};
    for (final label in note.citations.keys) {
      if (localIds[label] != null) continue;
      final reference = await PdgNotes.referenceFor(label);
      if (reference != null) patchReferences[label] = reference;
    }
    if (!mounted) return;
    setState(() {
      _pdgNote = note;
      _citations = {
        for (final entry in note.citations.entries)
          entry.key: PdgCitation(
            localId: localIds[entry.key],
            inspireRecid: entry.value,
            reference: patchReferences[entry.key],
          ),
      };
    });
  }

  Future<void> _openRelatedReviews(
    BuildContext context,
    CategoryInfo? category,
  ) async {
    final related = await PdgNotes.reviewFilesFor(widget.view.entry.pdgid);
    if (!context.mounted) return;
    final files = related.isNotEmpty
        ? related.toSet()
        : (category == null
              ? const <String>{}
              : categoryReviewFiles[category.category]?.toSet() ??
                    const <String>{});
    await AppNav.push<void>(context, ReviewsPage(initialFiles: files));
  }

  void _selectTab(int tab) {
    setState(() => _tab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToOutlineTarget(_tabsKey);
    });
  }

  void _showIdentity() {
    final target = _identityKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        alignment: 0.05,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final category = categoryFromFlags(view.entry.flags);
    final flagsLabel = decodedFlags(view.entry.flags, strings.lang);
    final detailed = scope.settings.detailedMode;
    final aliases = aliasesForPdgid(view.entry.pdgid);
    final notes = particleNotesContext(
      view.entry,
      snapshotHash: scope.snapshotHash,
    );
    final path = [...view.ancestors, view.entry];
    final outlineItems = <PageOutlineItem>[
      PageOutlineItem(
        label: strings.pageOverview,
        target: _overviewKey,
        icon: Icons.info_outline,
      ),
      if (view.hasIdentity)
        PageOutlineItem(
          label: strings.pageIdentity,
          target: _identityKey,
          icon: Icons.fingerprint,
        ),
      PageOutlineItem(
        label: strings.pageKeyProperties,
        target: _keyPropertiesKey,
        icon: Icons.star_outline,
      ),
      PageOutlineItem(
        label: strings.particleProperties,
        onTap: () => _selectTab(0),
        icon: Icons.functions,
      ),
      PageOutlineItem(
        label: strings.particleDecays,
        onTap: () => _selectTab(1),
        icon: Icons.call_split,
      ),
      PageOutlineItem(
        label: strings.particleReferences,
        onTap: () => _selectTab(2),
        icon: Icons.menu_book_outlined,
      ),
      PageOutlineItem(
        label: strings.notesTitle,
        target: _notesKey,
        icon: Icons.sticky_note_2_outlined,
      ),
      PageOutlineItem(
        label: strings.pageTexts,
        target: _textsKey,
        icon: Icons.subject,
      ),
    ];
    final content = PageOutlineScaffold(
      label: strings.pageOutline,
      items: outlineItems,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.m,
                Insets.l,
                0,
              ),
              child: BreadcrumbBar(
                entries: path,
                onOpen: (pdgid) => AppNav.openPdgid(context, pdgid),
              ),
            ),
            ContentHeader(
              key: _overviewKey,
              title: ParticleSymbol(
                view.entry.description,
                fontSize: MediaQuery.sizeOf(context).width < 600 ? 26 : 34,
              ),
              subtitle: Text(
                [
                  'PDG ${view.currentEdition}',
                  view.entry.pdgid,
                  if (category != null) category.label(strings.lang),
                  if (detailed && flagsLabel.isNotEmpty) flagsLabel,
                ].join(' · '),
              ),
              meta: [
                if (category != null)
                  MetaChip(category.label(strings.lang), tone: BadgeTone.info),
                for (final alias in aliases)
                  MetaChip(
                    strings.particleAlsoKnownAs(alias),
                    tooltip: strings.particleAliasSource,
                  ),
                if (detailed && flagsLabel.isNotEmpty)
                  MetaChip(flagsLabel, tooltip: 'flags ${view.entry.flags}'),
                MetaChip(
                  '${view.particles.length} ${strings.particleIdentityCount}',
                  onTap: view.hasIdentity ? _showIdentity : null,
                  tooltip: strings.particleIdentityCount,
                ),
                MetaChip(
                  strings.propertyCount(view.properties.length),
                  onTap: () => _selectTab(0),
                  tooltip: strings.particleProperties,
                ),
                MetaChip(
                  strings.modeCount(view.decayCount),
                  onTap: () => _selectTab(1),
                  tooltip: strings.particleDecays,
                ),
                MetaChip(
                  strings.referenceCount(view.referenceCount),
                  onTap: () => _selectTab(2),
                  tooltip: strings.particleReferences,
                ),
              ],
              actions: [
                IconButton(
                  tooltip: strings.reviewsTitle,
                  icon: const Icon(Icons.menu_book_outlined, size: 19),
                  onPressed: () =>
                      unawaited(_openRelatedReviews(context, category)),
                ),
                CopyIconButton(
                  text: _copyParticle(context, view),
                  tooltip: strings.commonCopy,
                ),
              ],
            ),
            if (_pdgNote?.was case final was?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.s,
                  Insets.l,
                  0,
                ),
                child: PdgLiveText(
                  'was $was',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
            if (_pdgNote?.summary case final summary?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.s,
                  Insets.l,
                  0,
                ),
                child: PdgLiveText(
                  summary,
                  citations: _citations,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            if (!view.hasIdentity)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: Container(
                  padding: const EdgeInsets.all(Insets.m),
                  decoration: BoxDecoration(
                    color: palette.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: palette.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: palette.warning,
                        size: 18,
                      ),
                      const SizedBox(width: Insets.s),
                      Expanded(child: Text(strings.particleMissingIdentity)),
                    ],
                  ),
                ),
              )
            else ...[
              Padding(
                key: _identityKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.l,
                  vertical: Insets.s,
                ),
                child: _IdentityList(view: view),
              ),
              if (view.particles.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.l,
                    0,
                    Insets.l,
                    Insets.s,
                  ),
                  child: Text(
                    strings.particleSharedListing,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
            ],
            const SizedBox(height: Insets.s),
            Padding(
              key: _keyPropertiesKey,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: _KeyProperties(view: view),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              key: _tabsKey,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.functions, size: 17),
                      label: Text(
                        '${strings.particleProperties} · ${view.properties.length}',
                      ),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.call_split, size: 17),
                      label: Text(
                        '${strings.particleDecays} · ${view.decays.length}',
                      ),
                    ),
                    ButtonSegment(
                      value: 2,
                      icon: const Icon(Icons.menu_book_outlined, size: 17),
                      label: Text(
                        '${strings.particleReferences} · ${view.referenceCount}',
                      ),
                    ),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
              ),
            ),
            const SizedBox(height: Insets.s),
            if (_tab == 0)
              _PropertiesTab(view: view)
            else if (_tab == 1)
              DecayCatalog(
                parent: view.entry,
                decays: view.decays,
                summariesByEntry: view.summariesByEntry,
                summaryCounts: view.summaryCounts,
                measurementCounts: view.measurementCounts,
                currentEdition: view.currentEdition,
              )
            else
              _ReferencesTab(entry: view.entry, total: view.referenceCount),
            const SizedBox(height: Insets.m),
            EntityNotesSection(
              key: _notesKey,
              targets: notes.targets,
              anchors: notes.anchors,
            ),
            const SizedBox(height: Insets.l),
            Padding(
              key: _textsKey,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: _EntryTexts(view: view),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: RawFieldsPanel(
                fields: view.entry.rawFields,
                title: 'pdgid',
              ),
            ),
            for (final particle in view.particles)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.s,
                  Insets.l,
                  0,
                ),
                child: RawFieldsPanel(fields: particle.rawFields),
              ),
            const SizedBox(height: Insets.m),
            SnapshotFooter(hash: scope.snapshotHash),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showContextSidebar(context, constraints.maxWidth)) return content;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            ResizableContextSidebar(
              viewportWidth: constraints.maxWidth,
              child: ParticleContextSidebar(view: view),
            ),
          ],
        );
      },
    );
  }

  String _copyParticle(BuildContext context, ParticleView view) {
    final strings = AppScope.of(context).strings;
    final lines = <String>[
      view.entry.description,
      for (final alias in aliasesForPdgid(view.entry.pdgid))
        '${strings.particleAlsoKnownAs(alias)} (${strings.particleAliasSource})',
      'PDG ${view.entry.pdgid} · PDG ${view.currentEdition}',
      for (final particle in view.particles)
        [
          particle.name,
          'charge ${chargeWithUnit(particle.charge)}',
          ccTypeLabel(particle.ccType, strings.lang),
          if (particle.mcid != null) 'MC ${particle.mcid}',
        ].join(' · '),
      for (final property in view.properties)
        if (view.summaryFor(property.id).preferred != null)
          '${property.description}: ${DisplayQuantity.fromSummary(view.summaryFor(property.id).preferred!).text}',
    ];
    return lines.join('\n');
  }
}

class _IdentityList extends StatelessWidget {
  const _IdentityList({required this.view});

  final ParticleView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Wrap(
      spacing: Insets.s,
      runSpacing: Insets.s,
      children: [
        for (final particle in view.particles)
          Container(
            padding: const EdgeInsets.all(Insets.m),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ParticleSymbol(particle.name, fontSize: 21),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 3,
                  children: [
                    MetaChip(
                      '${strings.particleCharge} ${chargeWithUnit(particle.charge)}',
                      tone: BadgeTone.info,
                    ),
                    MetaChip(ccTypeLabel(particle.ccType, strings.lang)),
                    if (particle.mcid != null) MetaChip('MC ${particle.mcid}'),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 3,
                  children: [
                    if (particle.quantumJ != null &&
                        particle.quantumJ!.isNotEmpty)
                      MetaChip('J = ${particle.quantumJ}'),
                    if (particle.quantumP != null &&
                        particle.quantumP!.isNotEmpty)
                      MetaChip('P = ${particle.quantumP}'),
                    if (particle.quantumC != null &&
                        particle.quantumC!.isNotEmpty)
                      MetaChip('C = ${particle.quantumC}'),
                    if (particle.quantumI != null &&
                        particle.quantumI!.isNotEmpty)
                      MetaChip('I = ${particle.quantumI}'),
                    if (particle.quantumG != null &&
                        particle.quantumG!.isNotEmpty)
                      MetaChip('G = ${particle.quantumG}'),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyProperties extends StatelessWidget {
  const _KeyProperties({required this.view});

  final ParticleView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final candidates = view.properties
        .where((row) {
          final group = propertyGroupOf(row.dataType);
          return row.id != view.entry.id &&
              (group == PropertyGroup.mass ||
                  group == PropertyGroup.width ||
                  group == PropertyGroup.lifetime);
        })
        .take(8)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return SectionCard(
        title: strings.particleMainProperties,
        child: Text(
          strings.particleNoMainProperties,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: palette.textSecondary),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        final width = twoColumns
            ? (constraints.maxWidth - Insets.s) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: Insets.s,
          runSpacing: Insets.s,
          children: [
            for (final property in candidates)
              SizedBox(
                width: width,
                child: _KeyPropertyCard(property: property, view: view),
              ),
          ],
        );
      },
    );
  }
}

class _KeyPropertyCard extends StatelessWidget {
  const _KeyPropertyCard({required this.property, required this.view});

  final Entry property;
  final ParticleView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final selection = view.summaryFor(property.id);
    final quantity = selection.preferred == null
        ? null
        : DisplayQuantity.fromSummary(selection.preferred!);
    return PropertySummaryCard(
      titleWidget: DescriptionText(
        property.description,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.textSecondary,
        ),
      ),
      badge: MetaChip(
        dataTypeInfo(property.dataType).label(strings.lang),
        tone: BadgeTone.neutral,
      ),
      value: quantity != null
          ? DisplayValueView(quantity, fontSize: 21)
          : Text(
              selection.isEmpty
                  ? strings.seriesNoSummary
                  : strings.seriesMultipleCandidates,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.warning),
            ),
      subtitle: Text(
        [
          'PDG ${view.currentEdition}',
          if (selection.preferred != null)
            valueTypeShortLabel(selection.preferred!.valueType, strings.lang),
          if (selection.preferred != null &&
              selection.preferred!.limitType != null)
            limitTypeLabel(selection.preferred!.limitType, strings.lang),
          '${view.measurementCount(property.id)} ${strings.seriesMeasurements}',
        ].join(' · '),
      ),
      onTap: () => AppNav.openPdgid(context, property.pdgid),
    );
  }
}

class _PropertiesTab extends StatefulWidget {
  const _PropertiesTab({required this.view});

  final ParticleView view;

  @override
  State<_PropertiesTab> createState() => _PropertiesTabState();
}

class _PropertiesTabState extends State<_PropertiesTab> {
  static const int _pageSize = 80;

  final TextEditingController _search = TextEditingController();
  final Set<int> _expanded = {};
  int _visibleLimit = _pageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final strings = AppScope.of(context).strings;
    if (view.properties.isEmpty) {
      return EmptyPanel(
        message: strings.particleNoProperties,
        icon: Icons.functions,
      );
    }
    final query = _search.text.trim().toLowerCase();
    final filterActive = query.isNotEmpty;
    final filtered = filterActive
        ? view.properties
              .where((row) => row.description.toLowerCase().contains(query))
              .toList(growable: false)
        : const <Entry>[];
    final treeNodes = filterActive
        ? const <_PropertyNode>[]
        : _buildNodes(view, view.entry.id, 0);
    final visibleTree = treeNodes.take(_visibleLimit).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() => _visibleLimit = _pageSize),
                  decoration: InputDecoration(
                    hintText: strings.particlePropertyDirectory,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Insets.s),
              MetaChip('${view.properties.length}', tone: BadgeTone.info),
            ],
          ),
        ),
        if (filterActive) ...[
          if (filtered.isEmpty)
            EmptyPanel(
              message: strings.particleNoPropertiesMatch,
              icon: Icons.search_off,
            )
          else ...[
            for (final row in filtered.take(_visibleLimit))
              _PropertyRow(
                property: row,
                view: view,
                depth: 0,
                path: view.sectionPathFor(row),
                onOpen: () => AppNav.openPdgid(context, row.pdgid),
              ),
            if (filtered.length > _visibleLimit)
              _showMore(context, strings, filtered.length - _visibleLimit),
          ],
        ] else ...[
          for (final node in visibleTree) _nodeWidget(context, view, node),
          if (treeNodes.length > _visibleLimit)
            _showMore(context, strings, treeNodes.length - _visibleLimit),
        ],
      ],
    );
  }

  List<_PropertyNode> _buildNodes(ParticleView view, int parentId, int depth) {
    final children =
        view.properties
            .where((row) => (row.parentId ?? view.entry.id) == parentId)
            .toList(growable: false)
          ..sort(
            (a, b) => a.sort != b.sort
                ? a.sort.compareTo(b.sort)
                : a.id.compareTo(b.id),
          );
    final result = <_PropertyNode>[];
    for (final row in children) {
      final subChildren = view.properties
          .where((child) => child.parentId == row.id)
          .toList();
      if (row.dataType == 'SEC') {
        result.add(
          _PropertyNode(
            entry: row,
            depth: depth,
            isSection: true,
            count: subChildren.length,
          ),
        );
        if (_expanded.contains(row.id)) {
          result.addAll(_buildNodes(view, row.id, depth + 1));
        }
      } else {
        result.add(_PropertyNode(entry: row, depth: depth, isSection: false));
        if (subChildren.isNotEmpty) {
          result.addAll(_buildNodes(view, row.id, depth + 1));
        }
      }
    }
    return result;
  }

  Widget _nodeWidget(
    BuildContext context,
    ParticleView view,
    _PropertyNode node,
  ) {
    if (node.isSection) {
      return _PropertySectionRow(
        section: node.entry,
        count: node.count,
        expanded: _expanded.contains(node.entry.id),
        depth: node.depth,
        onToggle: () => setState(() {
          if (_expanded.contains(node.entry.id)) {
            _expanded.remove(node.entry.id);
          } else {
            _expanded.add(node.entry.id);
          }
        }),
      );
    }
    return _PropertyRow(
      property: node.entry,
      view: view,
      depth: node.depth,
      path: const [],
      onOpen: () => AppNav.openPdgid(context, node.entry.pdgid),
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
          label: Text(strings.particleMoreProperties(remaining)),
        ),
      ),
    );
  }
}

class _PropertyNode {
  const _PropertyNode({
    required this.entry,
    required this.depth,
    required this.isSection,
    this.count = 0,
  });

  final Entry entry;
  final int depth;
  final bool isSection;
  final int count;
}

class _PropertySectionRow extends StatelessWidget {
  const _PropertySectionRow({
    required this.section,
    required this.count,
    required this.expanded,
    required this.depth,
    required this.onToggle,
  });

  final Entry section;
  final int count;
  final bool expanded;
  final int depth;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Insets.l + (depth * 12.0).clamp(0, 48),
          9,
          Insets.m,
          9,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: DescriptionText(
                section.description,
                maxLines: 2,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            MetaChip('$count ${strings.commonCount}'),
          ],
        ),
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.property,
    required this.view,
    required this.depth,
    required this.path,
    required this.onOpen,
  });

  final Entry property;
  final ParticleView view;
  final int depth;
  final List<Entry> path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final selection = view.summaryFor(property.id);
    final quantity = selection.preferred == null
        ? null
        : DisplayQuantity.fromSummary(selection.preferred!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Insets.l + (depth * 12.0).clamp(0, 48),
            5,
            Insets.m,
            5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (path.isNotEmpty)
                      Text(
                        path.map((row) => row.description).join(' › '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    DescriptionText(
                      property.description,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MetaChip(
                          dataTypeInfo(property.dataType).label(strings.lang),
                        ),
                        if (quantity != null)
                          DisplayValueView(quantity, fontSize: 13)
                        else if (selection.isAmbiguous)
                          MetaChip(
                            strings.candidateCount(selection.count),
                            tone: BadgeTone.warning,
                          )
                        else
                          Text(
                            strings.seriesNoSummary,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        if (view.measurementCount(property.id) > 0)
                          Text(
                            '${view.measurementCount(property.id)} ${strings.seriesMeasurements}',
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

class _ReferencesTab extends StatefulWidget {
  const _ReferencesTab({required this.entry, required this.total});

  final Entry entry;
  final int total;

  @override
  State<_ReferencesTab> createState() => _ReferencesTabState();
}

class _ReferencesTabState extends State<_ReferencesTab> {
  final List<ReferenceWithCount> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _offset = 0;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _items.clear();
        _offset = 0;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await AppScope.of(context).repository.referencesForSubtree(
        widget.entry,
        limit: 50,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _offset = _items.length;
        _hasMore = page.items.length == 50 && _items.length < page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    if (_loading) {
      return const Center(child: LoadingPanel(compact: true));
    }
    if (_error != null) {
      return ErrorPanel(error: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return EmptyPanel(
        message: strings.particleNoReferences,
        icon: Icons.menu_book_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
          child: Text(
            '${strings.referenceCount(_items.length)} / ${widget.total}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ),
        for (final item in _items)
          Card(
            margin: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
            child: ListTile(
              title: DescriptionText(
                cleanReferenceTitle(item.reference.displayTitle),
                maxLines: 2,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              subtitle: Text(
                [
                  item.reference.documentId,
                  if (item.reference.publicationYear != null)
                    '${item.reference.publicationYear}',
                  '${item.measurementCount} ${strings.seriesMeasurements}',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => AppNav.openReference(context, item.reference.id),
            ),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.m),
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : () => _load(reset: false),
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text(strings.commonShowMore),
            ),
          ),
      ],
    );
  }
}

class _EntryTexts extends StatelessWidget {
  const _EntryTexts({required this.view});

  final ParticleView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final ids = {...view.ancestors.map((row) => row.id), view.entry.id};
    final texts = view.texts
        .where((text) => ids.contains(text.pdgidId))
        .toList();
    if (texts.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: strings.seriesSectionText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final text in texts)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MetaChip(
                    '${text.pdgid} · ${textTypeLabel(text.type, strings.lang)}',
                  ),
                  const SizedBox(height: 3),
                  CitationText(
                    text.text,
                    selectable: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  RawFieldsPanel(fields: text.rawFields),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
