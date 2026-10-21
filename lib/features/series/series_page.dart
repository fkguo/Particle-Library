import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../app/debug_hooks.dart';
import '../../data/pdg_database.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/views.dart';
import '../common/async_view.dart';
import '../common/context_sidebar.dart';
import '../common/citation_text.dart';
import '../common/description_text.dart';
import '../common/favorite_button.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/raw_fields.dart';
import '../common/summary_views.dart';
import '../common/ui.dart';
import '../notes/notes_anchor.dart';
import '../notes/notes_entity.dart';
import '../plot/plot_chart.dart';
import '../plot/plot_data.dart';
import 'measurement_list.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key, required this.entry});

  final Entry entry;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  late Future<SeriesView> _future;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.loadSeries(widget.entry);
  }

  void _retry() {
    setState(() {
      _future = AppScope.of(context).repository.loadSeries(widget.entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final capture = seriesNotesContext(
      widget.entry,
      snapshotHash: scope.snapshotHash,
    );
    return PageScaffold(
      showSidebarToggle: true,
      maxWidth: 1480,
      noteAnchors: capture.anchors,
      noteLabel: capture.label,
      title: DescriptionText(
        widget.entry.description,
        maxLines: 1,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle:
          '${widget.entry.pdgid} · ${dataTypeInfo(widget.entry.dataType).label(strings.lang)}',
      actions: [
        FutureBuilder<SeriesView>(
          future: _future,
          builder: (context, snapshot) {
            final view = snapshot.data;
            if (view == null) return const SizedBox.shrink();
            final notes = seriesNotesContext(
              view.entry,
              parent: view.ancestors.isEmpty ? null : view.ancestors.last,
              snapshotHash: scope.snapshotHash,
            );
            return EntityNotesButton(
              targets: notes.targets,
              anchors: notes.anchors,
            );
          },
        ),
        FavoriteButton(
          favorite: entryFavorite(
            entry: widget.entry,
            snapshotHash: scope.snapshotHash,
            subtitle: widget.entry.pdgid,
          ),
        ),
        CopyIconButton(
          text: _entryCopyText(context, widget.entry),
          tooltip: strings.commonCopy,
        ),
      ],
      body: AsyncView<SeriesView>(
        future: _future,
        onRetry: _retry,
        builder: (context, view) => _SeriesBody(view: view),
      ),
    );
  }

  String _entryCopyText(BuildContext context, Entry entry) => [
    entry.description,
    'PDG ${entry.pdgid} · ${dataTypeInfo(entry.dataType).label(TextLang.en)}',
    if (entry.flags.isNotEmpty) 'flags ${entry.flags}',
    '${AppScope.of(context).strings.commonEdition}: PDG ${AppScope.of(context).database.currentEdition}',
  ].join('\n');
}

class _SeriesBody extends StatelessWidget {
  _SeriesBody({required this.view});

  final SeriesView view;
  final GlobalKey _overviewKey = GlobalKey();
  final GlobalKey _measurementsKey = GlobalKey();
  final GlobalKey _notesKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _relatedKey = GlobalKey();
  final GlobalKey _footnotesKey = GlobalKey();
  final GlobalKey _textKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final entry = view.entry;
    final typeInfo = dataTypeInfo(entry.dataType);
    final official = scope.database.docFor(
      'PDGID',
      'DATA_TYPE',
      entry.dataType.isEmpty ? null : entry.dataType,
    );
    final flagsLabel = decodedFlags(entry.flags, strings.lang);
    final detailed = scope.settings.detailedMode;
    final notes = seriesNotesContext(
      entry,
      parent: view.ancestors.isEmpty ? null : view.ancestors.last,
      snapshotHash: scope.snapshotHash,
    );
    final path = [...view.ancestors, entry];
    final trend = buildEditionTrend(
      view.summaries,
      label: entry.description,
      currentEdition: view.currentEdition,
    );
    debugTrendHook = () =>
        showTrendDialog(context, data: trend, title: entry.description);
    final outlineItems = <PageOutlineItem>[
      PageOutlineItem(
        label: strings.pageOverview,
        target: _overviewKey,
        icon: Icons.info_outline,
      ),
      PageOutlineItem(
        label: strings.seriesMeasurements,
        target: _measurementsKey,
        icon: Icons.straighten,
      ),
      PageOutlineItem(
        label: strings.notesTitle,
        target: _notesKey,
        icon: Icons.sticky_note_2_outlined,
      ),
      PageOutlineItem(
        label: strings.seriesHistory,
        target: _historyKey,
        icon: Icons.history,
      ),
      if (view.relatedSources.isNotEmpty)
        PageOutlineItem(
          label: strings.seriesRelatedModes,
          target: _relatedKey,
          icon: Icons.account_tree_outlined,
        ),
      if (view.footnotes.isNotEmpty)
        PageOutlineItem(
          label: strings.seriesFootnotes,
          target: _footnotesKey,
          icon: Icons.notes,
        ),
      if (view.texts.any((text) => text.pdgidId != entry.id))
        PageOutlineItem(
          label: strings.pageTexts,
          target: _textKey,
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
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.m,
                Insets.l,
                Insets.s,
              ),
              title: DescriptionText(
                entry.description,
                maxLines: entry.description.length > 48 ? 3 : 2,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  fontSize: entry.description.length > 48 ? 20 : null,
                ),
              ),
              subtitle: Text(
                [
                  'PDG ${view.currentEdition}',
                  entry.pdgid,
                  typeInfo.label(strings.lang),
                  if (official != null && official.description.isNotEmpty)
                    official.description,
                ].join(' · '),
              ),
              meta: [
                MetaChip(typeInfo.label(strings.lang), tone: BadgeTone.info),
                if (detailed && flagsLabel.isNotEmpty)
                  MetaChip(flagsLabel, tooltip: 'flags ${entry.flags}'),
                if (entry.modeNumber != null)
                  MetaChip('mode #${entry.modeNumber}'),
                !view.selection.isEmpty
                    ? MetaChip(
                        '${view.selection.count} ${strings.commonCount}',
                        tone: BadgeTone.accent,
                      )
                    : MetaChip(
                        strings.seriesNoSummary,
                        tone: BadgeTone.warning,
                      ),
                MetaChip(strings.measurementCount(view.directMeasurementCount)),
              ],
              actions: [
                CopyIconButton(
                  text: _definitionCopyText(context, view),
                  tooltip: strings.seriesCopyDefinition,
                ),
              ],
            ),
            if (view.definitionTexts.isNotEmpty)
              SectionCard(
                title: strings.seriesDefinition,
                child: _TextBlocks(texts: view.definitionTexts),
              ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, 0),
              child: SummaryList(
                selection: view.selection,
                compact: true,
                quantityLabel: entry.description,
              ),
            ),
            const SizedBox(height: Insets.m),
            SectionHeading(
              strings.seriesMeasurements,
              key: _measurementsKey,
              subtitle: strings.measurementCount(view.directMeasurementCount),
            ),
            MeasurementList(entry: entry),
            const SizedBox(height: Insets.m),
            EntityNotesSection(
              key: _notesKey,
              targets: notes.targets,
              anchors: notes.anchors,
            ),
            const SizedBox(height: Insets.m),
            SectionHeading(
              strings.seriesHistory,
              key: _historyKey,
              trailing: TrendChartButton(data: trend, title: entry.description),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: HistoryTable(
                summaries: view.summaries,
                currentEdition: view.currentEdition,
              ),
            ),
            if (view.relatedSources.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.seriesRelatedModes, key: _relatedKey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: Column(
                  children: [
                    for (final related in view.relatedSources)
                      _RelatedSourceTile(related: related),
                  ],
                ),
              ),
            ],
            if (view.footnotes.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(
                strings.seriesFootnotes,
                key: _footnotesKey,
                subtitle: '${view.footnotes.length} ${strings.commonCount}',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: _SectionFootnotes(footnotes: view.footnotes),
              ),
            ],
            if (view.texts.any((text) => text.pdgidId != entry.id)) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.seriesSectionText, key: _textKey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: SectionCard(
                  child: _TextBlocks(
                    texts: [
                      for (final ancestor in view.ancestors)
                        ...view.texts.where(
                          (text) => text.pdgidId == ancestor.id,
                        ),
                    ],
                  ),
                ),
              ),
            ],
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
              child: SeriesContextSidebar(view: view),
            ),
          ],
        );
      },
    );
  }

  String _definitionCopyText(BuildContext context, SeriesView view) {
    final strings = AppScope.of(context).strings;
    final entry = view.entry;
    final lines = <String>[
      '${entry.description} · PDG ${entry.pdgid}',
      'PDG ${view.currentEdition} · ${dataTypeInfo(entry.dataType).label(strings.lang)}',
      if (entry.flags.isNotEmpty) 'flags ${entry.flags}',
      for (final text in view.definitionTexts) text.text,
      for (final summary in view.currentSummaries)
        '${DisplayQuantity.fromSummary(summary).text} · ${valueTypeLabel(summary.valueType, strings.lang)} · pdgdata #${summary.id}',
    ];
    return lines.join('\n');
  }
}

class _TextBlocks extends StatelessWidget {
  const _TextBlocks({required this.texts});

  final List<SectionText> texts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    if (texts.isEmpty) {
      return Text(
        strings.seriesNoSectionText,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: palette.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final text in texts)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MetaChip(text.pdgid, tone: BadgeTone.neutral),
                    const SizedBox(width: 6),
                    MetaChip(textTypeLabel(text.type, strings.lang)),
                  ],
                ),
                const SizedBox(height: 4),
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
    );
  }
}

class _SectionFootnotes extends StatefulWidget {
  const _SectionFootnotes({required this.footnotes});

  final List<Footnote> footnotes;

  @override
  State<_SectionFootnotes> createState() => _SectionFootnotesState();
}

class _SectionFootnotesState extends State<_SectionFootnotes> {
  final Map<int, List<FootnoteAttachment>> _attachments = {};

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Column(
      children: [
        for (final footnote in widget.footnotes)
          Container(
            margin: const EdgeInsets.only(bottom: Insets.s),
            padding: const EdgeInsets.all(Insets.m),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MetaChip(
                      '#${footnote.footnoteIndex ?? footnote.id}',
                      tone: footnote.changebar
                          ? BadgeTone.warning
                          : BadgeTone.neutral,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${strings.seriesFootnoteAttachments}: ${_attachments[footnote.id]?.length ?? '…'}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final attachments = await AppScope.of(context).database
                            .footnoteAttachments(footnote.id);
                        if (mounted) {
                          setState(
                            () => _attachments[footnote.id] = attachments,
                          );
                        }
                      },
                      child: Text(strings.commonShowMore),
                    ),
                  ],
                ),
                DescriptionText(
                  footnote.text,
                  selectable: true,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                RawFieldsPanel(fields: footnote.rawFields),
                if (_attachments[footnote.id] != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final attachment in _attachments[footnote.id]!)
                        ActionChip(
                          label: Text(
                            '${attachment.seriesPdgid} · #${attachment.measurementId}',
                          ),
                          onPressed: () =>
                              AppNav.openPdgid(context, attachment.seriesPdgid),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RelatedSourceTile extends StatelessWidget {
  const _RelatedSourceTile({required this.related});

  final RelatedQuantity related;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final type = dataTypeInfo(related.target.dataType).label(strings.lang);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.s),
      child: ListTile(
        title: DescriptionText(related.target.description, maxLines: 2),
        subtitle: Text('${related.target.pdgid} · $type'),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => AppNav.openPdgid(context, related.target.pdgid),
      ),
    );
  }
}
