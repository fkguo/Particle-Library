import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../app/debug_hooks.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/views.dart';
import '../common/async_view.dart';
import '../common/context_sidebar.dart';
import '../common/citation_text.dart';
import '../common/description_text.dart';
import '../common/favorite_button.dart';
import '../common/math_text.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/raw_fields.dart';
import '../common/summary_views.dart';
import '../common/ui.dart';
import '../notes/notes_anchor.dart';
import '../series/measurement_list.dart';
import '../plot/plot_chart.dart';
import '../plot/plot_data.dart';

class DecayModePage extends StatefulWidget {
  const DecayModePage({super.key, required this.entry});

  final Entry entry;

  @override
  State<DecayModePage> createState() => _DecayModePageState();
}

class _DecayModePageState extends State<DecayModePage> {
  late Future<ModeView> _future;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).repository.loadMode(widget.entry);
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
      title: Text(widget.entry.pdgid),
      subtitle:
          '${dataTypeInfo(widget.entry.dataType).label(strings.lang)} · ${strings.commonEdition} ${scope.database.currentEdition}',
      actions: [
        FavoriteButton(
          favorite: entryFavorite(
            entry: widget.entry,
            snapshotHash: scope.snapshotHash,
          ),
        ),
        CopyIconButton(
          text: _copyOriginal(scope, widget.entry),
          tooltip: strings.decayCopyOriginal,
        ),
      ],
      body: AsyncView<ModeView>(
        future: _future,
        onRetry: () => setState(() {
          _future = AppScope.of(context).repository.loadMode(widget.entry);
        }),
        builder: (context, view) => _ModeBody(view: view),
      ),
    );
  }

  static String _copyOriginal(AppScope scope, Entry entry) => [
    entry.description,
    'PDG ${entry.pdgid}',
    'PDG ${scope.database.currentEdition}',
    if (entry.modeNumber != null) 'mode_number ${entry.modeNumber}',
    'data_type ${entry.dataType}',
  ].join('\n');
}

class _ModeBody extends StatelessWidget {
  const _ModeBody({required this.view});

  final ModeView view;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final detailed = scope.settings.detailedMode;
    final entry = view.entry;
    final path = [...view.ancestors, entry];
    final type = dataTypeInfo(entry.dataType);
    final trend = buildEditionTrend(
      view.summaries,
      label: entry.description,
      currentEdition: view.currentEdition,
    );
    debugTrendHook = () =>
        showTrendDialog(context, data: trend, title: entry.description);
    final overviewKey = GlobalKey();
    final originalKey = GlobalKey();
    final structureKey = GlobalKey();
    final summaryKey = GlobalKey();
    final relatedKey = GlobalKey();
    final measurementsKey = GlobalKey();
    final childrenKey = GlobalKey();
    final historyKey = GlobalKey();
    final textKey = GlobalKey();
    final footnotesKey = GlobalKey();
    final outlineItems = <PageOutlineItem>[
      PageOutlineItem(
        label: strings.pageOverview,
        target: overviewKey,
        icon: Icons.info_outline,
      ),
      PageOutlineItem(
        label: strings.decayOriginal,
        target: originalKey,
        icon: Icons.code,
      ),
      PageOutlineItem(
        label: strings.decayStructure,
        target: structureKey,
        icon: Icons.account_tree_outlined,
      ),
      PageOutlineItem(
        label: strings.decaySummary,
        target: summaryKey,
        icon: Icons.functions,
      ),
      PageOutlineItem(
        label: strings.decayRelatedQuantities,
        target: relatedKey,
        icon: Icons.link,
      ),
      PageOutlineItem(
        label: strings.decayDirectMeasurements,
        target: measurementsKey,
        icon: Icons.straighten,
      ),
      if (view.children.isNotEmpty)
        PageOutlineItem(
          label: strings.decayDirectoryChildren,
          target: childrenKey,
          icon: Icons.call_split,
        ),
      PageOutlineItem(
        label: strings.seriesHistory,
        target: historyKey,
        icon: Icons.history,
      ),
      if (view.texts.isNotEmpty)
        PageOutlineItem(
          label: strings.pageTexts,
          target: textKey,
          icon: Icons.subject,
        ),
      if (view.footnotes.isNotEmpty)
        PageOutlineItem(
          label: strings.measurementFootnotes,
          target: footnotesKey,
          icon: Icons.notes,
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
              title: view.tokens.isEmpty
                  ? SelectableText(
                      entry.description,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    )
                  : DecayEquation(
                      view.tokens,
                      fallback: entry.description,
                      fontSize: 23,
                    ),
              subtitle: Text(
                [
                  'PDG ${view.currentEdition}',
                  entry.pdgid,
                  type.label(strings.lang),
                  if (entry.modeNumber != null)
                    '${strings.decayModeNumber} ${entry.modeNumber}',
                ].join(' · '),
              ),
              meta: [
                MetaChip(type.label(strings.lang), tone: BadgeTone.info),
                if (detailed && entry.flags.isNotEmpty)
                  MetaChip(
                    decodedFlags(
                      entry.flags,
                      strings.lang,
                      includeCategory: true,
                    ),
                    tooltip: 'flags ${entry.flags}',
                  ),
                MetaChip(strings.measurementCount(view.directMeasurementCount)),
                MetaChip(
                  '${view.related.length} ${strings.relatedQuantitiesLabel}',
                ),
                if (view.hasInclusive)
                  MetaChip(
                    strings.decayInclusiveToken,
                    tone: BadgeTone.warning,
                  ),
                if (view.isMultiStage)
                  MetaChip(
                    strings.decayMultiStageBadge,
                    tone: BadgeTone.warning,
                  ),
              ],
              actions: [
                CopyIconButton(
                  text: _copySummary(context, view),
                  tooltip: strings.decayCopySummary,
                ),
              ],
            ),
            Padding(
              key: originalKey,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.decayOriginal,
                trailing: CopyIconButton(text: entry.description),
                child: SelectableText(
                  entry.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (view.isStructureIncomplete)
              _Notice(
                icon: Icons.info_outline,
                tone: BadgeTone.warning,
                text: strings.decayNoOutgoingNote,
              ),
            const SizedBox(height: Insets.m),
            SectionHeading(strings.decayStructure, key: structureKey),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: _TokenSequence(view: view),
            ),
            const SizedBox(height: Insets.m),
            SectionHeading(strings.decaySummary, key: summaryKey),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SummaryList(
                selection: view.selection,
                compact: true,
                quantityLabel: entry.description,
              ),
            ),
            const SizedBox(height: Insets.m),
            SectionHeading(strings.decayRelatedQuantities, key: relatedKey),
            if (view.related.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: EmptyPanel(
                  message: strings.decayNoRelated,
                  icon: Icons.share_outlined,
                ),
              )
            else
              for (final related in view.related)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.l,
                    0,
                    Insets.l,
                    Insets.s,
                  ),
                  child: _RelatedQuantityCard(related: related),
                ),
            const SizedBox(height: Insets.m),
            SectionHeading(
              strings.decayDirectMeasurements,
              key: measurementsKey,
              subtitle: view.directMeasurementCount > 0
                  ? strings.measurementCount(view.directMeasurementCount)
                  : strings.decayNoDirectMeasurements,
            ),
            if (view.directMeasurementCount > 0)
              MeasurementList(entry: entry)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: Text(
                  view.relatedWithMeasurements.isEmpty
                      ? strings.decayNoRelatedMeasurements
                      : strings.decayNoDirectMeasurements,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
            if (view.children.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.decayDirectoryChildren, key: childrenKey),
              for (final child in view.children)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.l,
                    vertical: 2,
                  ),
                  child: Card(
                    child: ListTile(
                      title: Text(child.description),
                      subtitle: Text(
                        '${child.pdgid} · ${dataTypeInfo(child.dataType).label(strings.lang)}'
                        '${child.modeNumber == null ? '' : ' · mode ${child.modeNumber}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => AppNav.openPdgid(context, child.pdgid),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Insets.m),
            SectionHeading(
              strings.seriesHistory,
              key: historyKey,
              trailing: TrendChartButton(data: trend, title: entry.description),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: HistoryTable(
                summaries: view.summaries,
                currentEdition: view.currentEdition,
              ),
            ),
            if (view.definitionTexts.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.seriesSectionText, key: textKey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final text in view.definitionTexts)
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
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (view.footnotes.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              SectionHeading(strings.measurementFootnotes, key: footnotesKey),
              for (final footnote in view.footnotes)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.l,
                    0,
                    Insets.l,
                    Insets.s,
                  ),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MetaChip(
                          '#${footnote.footnoteIndex ?? footnote.id}',
                          tone: footnote.changebar
                              ? BadgeTone.warning
                              : BadgeTone.neutral,
                        ),
                        const SizedBox(height: 4),
                        DescriptionText(
                          footnote.text,
                          selectable: true,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        RawFieldsPanel(fields: footnote.rawFields),
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
              child: ModeContextSidebar(view: view),
            ),
          ],
        );
      },
    );
  }

  String _copySummary(BuildContext context, ModeView view) {
    final strings = AppScope.of(context).strings;
    final entry = view.entry;
    return [
      entry.description,
      'PDG ${entry.pdgid} · PDG ${view.currentEdition}',
      'data_type ${entry.dataType}${entry.modeNumber == null ? '' : ' · mode ${entry.modeNumber}'}',
      for (final summary in view.summaries)
        if (summary.edition == view.currentEdition)
          '${strings.summaryTypeLabel}: ${valueTypeLabel(summary.valueType, strings.lang)}: '
              '${DisplayQuantity.fromSummary(summary).text}'
              '${summary.comment == null || summary.comment!.isEmpty ? '' : ' — ${summary.comment}'}'
              ' [pdgdata #${summary.id}]',
      for (final related in view.related)
        'related ${related.target.pdgid} (${dataTypeInfo(related.target.dataType).label(strings.lang)}): ${related.target.description}',
    ].join('\n');
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.tone, required this.text});

  final IconData icon;
  final BadgeTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tone == BadgeTone.warning ? palette.warning : palette.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
      padding: const EdgeInsets.all(Insets.m),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Insets.s),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenSequence extends StatelessWidget {
  const _TokenSequence({required this.view});

  final ModeView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    if (view.tokens.isEmpty) {
      return EmptyPanel(
        message: strings.decayNoOutgoingNote,
        icon: Icons.call_split,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < view.tokens.length; i++)
            _TokenRow(
              token: view.tokens[i],
              resolution: view.resolutions[view.tokens[i].pdgitemId],
              isLast: i == view.tokens.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({
    required this.token,
    required this.resolution,
    required this.isLast,
  });

  final DecayToken token;
  final ItemResolution? resolution;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final isArrow = token.name.contains('-->');
    if (isArrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.arrow_downward, size: 16, color: palette.textSecondary),
            const SizedBox(width: 6),
            Text(
              '${token.name} · ${strings.decayMultiStageNote}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.warning),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: palette.divider)),
            RawFieldsPanel(fields: token.rawFields),
          ],
        ),
      );
    }
    final isText = token.itemType == 'T';
    final isInclusive = token.itemType == 'I';
    return Container(
      padding: const EdgeInsets.fromLTRB(Insets.l, 8, Insets.l, 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: palette.divider.withValues(alpha: 0.7),
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetaChip(
                token.isOutgoing
                    ? strings.decayOutgoing
                    : strings.decayIncoming,
                tone: token.isOutgoing ? BadgeTone.info : BadgeTone.neutral,
              ),
              const SizedBox(width: 6),
              if (token.multiplier > 1)
                MetaChip('×${token.multiplier}', tone: BadgeTone.accent),
              const SizedBox(width: 6),
              Expanded(
                child: isText || isInclusive
                    ? SelectableText(
                        token.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : ParticleSymbol(token.name, fontSize: 17),
              ),
              MetaChip(itemTypeLabel(token.itemType, strings.lang)),
            ],
          ),
          const SizedBox(height: 4),
          if (isInclusive)
            Text(
              strings.decayInclusiveToken,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.warning),
            )
          else if (isText)
            Text(
              strings.decayTextToken,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            )
          else if (resolution == null || resolution!.candidates.isEmpty)
            Text(
              strings.decayTokenNoIdentity,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.warning),
            )
          else ...[
            if (resolution!.isGeneric)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  strings.decayTokenGeneric(resolution!.candidates.length),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              )
            else if (resolution!.isAmbiguous)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  strings.decayTokenConflict,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.warning),
                ),
              ),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              children: [
                for (final particle in resolution!.candidates)
                  ActionChip(
                    tooltip: particle.name,
                    label: Text(
                      '${particle.name} · ${particle.pdgid}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    onPressed: () => AppNav.openPdgid(context, particle.pdgid),
                  ),
              ],
            ),
            if (resolution!.isMapped)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  strings.decayExpandedFromPdgItemMap(
                    resolution!.chain
                        .map((item) => '${item.name} [${item.itemType}]')
                        .join(' → '),
                  ),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
          ],
          const SizedBox(height: 2),
          RawFieldsPanel(fields: token.rawFields),
        ],
      ),
    );
  }
}

class _RelatedQuantityCard extends StatelessWidget {
  const _RelatedQuantityCard({required this.related});

  final RelatedQuantity related;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final target = related.target;
    final type = dataTypeInfo(target.dataType).label(strings.lang);
    return Container(
      padding: const EdgeInsets.all(Insets.m),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DescriptionText(
                  target.description,
                  maxLines: 3,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    MetaChip(type, tone: BadgeTone.info),
                    MetaChip('PDG ${target.pdgid}'),
                    MetaChip('map type ${related.edge.type ?? '—'}'),
                    MetaChip('map sort ${related.edge.sort}'),
                    MetaChip(
                      '${related.summaryCount} ${strings.summaryCountLabel}',
                    ),
                    MetaChip(
                      strings.measurementCount(related.measurementCount),
                      tone: related.measurementCount > 0
                          ? BadgeTone.accent
                          : BadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RawFieldsPanel(
                  fields: [
                    for (final e in related.edge.raw.entries)
                      RawField('pdgid_map', e.key, e.value),
                  ],
                ),
                if (target.dataType == 'T' || target.dataType == 'G')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.decayTrueTypeNotFraction(
                        dataTypeInfo(target.dataType).label(strings.lang),
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Insets.s),
          FilledButton.tonal(
            onPressed: () => AppNav.openPdgid(context, target.pdgid),
            child: Text(
              related.measurementCount > 0
                  ? strings.seriesMeasurements
                  : strings.commonOpen,
            ),
          ),
        ],
      ),
    );
  }
}
