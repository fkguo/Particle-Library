import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/views.dart';
import '../common/async_view.dart';
import '../common/context_sidebar.dart';
import '../common/citation_text.dart';
import '../common/description_text.dart';
import '../common/display_value.dart';
import '../common/favorite_button.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/raw_fields.dart';
import '../common/summary_views.dart';
import '../common/ui.dart';
import '../notes/notes_anchor.dart';
import '../notes/notes_entity.dart';

class TopicPage extends StatefulWidget {
  const TopicPage({super.key, required this.entry});

  final Entry entry;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  late Future<EntryView> _future;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.loadEntry(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final notes = particleNotesContext(
      widget.entry,
      snapshotHash: scope.snapshotHash,
    );
    return PageScaffold(
      noteAnchors: notes.anchors,
      noteLabel: notes.label,
      showSidebarToggle: true,
      maxWidth: 1480,
      title: DescriptionText(
        widget.entry.description,
        maxLines: 1,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle:
          '${widget.entry.pdgid} · ${dataTypeInfo(widget.entry.dataType).label(strings.lang)}',
      actions: [
        FavoriteButton(
          favorite: entryFavorite(
            entry: widget.entry,
            snapshotHash: scope.snapshotHash,
          ),
        ),
        EntityNotesButton(targets: notes.targets, anchors: notes.anchors),
      ],
      body: AsyncView<EntryView>(
        future: _future,
        onRetry: () => setState(() {
          _future = AppScope.of(context).repository.loadEntry(widget.entry);
        }),
        builder: (context, view) => _TopicBody(view: view),
      ),
    );
  }
}

class _TopicBody extends StatelessWidget {
  const _TopicBody({required this.view});

  final EntryView view;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final detailed = scope.settings.detailedMode;
    final entry = view.entry;
    final category = categoryFromFlags(entry.flags);
    final type = dataTypeInfo(entry.dataType);
    final path = [...view.ancestors, entry];
    final texts = view.texts
        .where(
          (text) => {
            for (final row in view.ancestors) row.id,
            entry.id,
          }.contains(text.pdgidId),
        )
        .toList(growable: false);
    final overviewKey = GlobalKey();
    final textsKey = GlobalKey();
    final summariesKey = GlobalKey();
    final childrenKey = GlobalKey();
    final outlineItems = <PageOutlineItem>[
      PageOutlineItem(
        label: strings.pageOverview,
        target: overviewKey,
        icon: Icons.info_outline,
      ),
      if (texts.isNotEmpty)
        PageOutlineItem(
          label: strings.pageTexts,
          target: textsKey,
          icon: Icons.subject,
        ),
      if (view.currentSummaries.isNotEmpty)
        PageOutlineItem(
          label: strings.seriesCurrentSummaries,
          target: summariesKey,
          icon: Icons.functions,
        ),
      PageOutlineItem(
        label: strings.catalogChildren,
        target: childrenKey,
        icon: Icons.account_tree_outlined,
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
              key: overviewKey,
              title: DescriptionText(
                entry.description,
                maxLines: 2,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  'PDG ${view.currentEdition}',
                  entry.pdgid,
                  type.label(strings.lang),
                  if (detailed && entry.flags.isNotEmpty)
                    'flags ${entry.flags}',
                ].join(' · '),
              ),
              meta: [
                MetaChip(
                  type.label(strings.lang),
                  tone: type.group == PropertyGroup.search
                      ? BadgeTone.warning
                      : BadgeTone.info,
                ),
                if (category != null) MetaChip(category.label(strings.lang)),
                if (detailed && entry.flags.isNotEmpty)
                  MetaChip('flags ${entry.flags}'),
                MetaChip(strings.entryCount(view.children.length)),
                MetaChip(strings.measurementCount(view.measurementCount)),
              ],
            ),
            if (texts.isNotEmpty)
              Padding(
                key: textsKey,
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: SectionCard(
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
                ),
              ),
            if (view.currentSummaries.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.seriesCurrentSummaries, key: summariesKey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: SummaryList(
                  selection: view.selection,
                  quantityLabel: entry.description,
                ),
              ),
            ],
            const SizedBox(height: Insets.m),
            SectionHeading(
              strings.catalogChildren,
              key: childrenKey,
              subtitle: '${view.children.length} ${strings.commonCount}',
            ),
            if (view.children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: EmptyPanel(
                  message: strings.catalogNoChildren,
                  icon: Icons.folder_open,
                ),
              )
            else
              for (final child in view.children)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.l,
                    vertical: 2,
                  ),
                  child: Card(
                    child: Builder(
                      builder: (context) {
                        final selection = view.selectionForChild(child.id);
                        final preferred = selection.preferred;
                        return ListTile(
                          title: DescriptionText(
                            child.description,
                            maxLines: 2,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${child.pdgid} · ${dataTypeInfo(child.dataType).label(strings.lang)}'
                                '${!detailed || child.flags.isEmpty ? '' : ' · flags ${child.flags}'}',
                              ),
                              const SizedBox(height: 2),
                              if (preferred != null)
                                DisplayValueView(
                                  DisplayQuantity.fromSummary(preferred),
                                  fontSize: 13,
                                )
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
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => AppNav.openPdgid(context, child.pdgid),
                        );
                      },
                    ),
                  ),
                ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: RawFieldsPanel(
                fields: entry.rawFields,
                title: strings.commonRawRecord,
              ),
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
              child: TopicContextSidebar(view: view),
            ),
          ],
        );
      },
    );
  }
}
