import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../notes/notes.dart';
import '../notes/note_capture.dart';
import '../notes/note_context.dart';
import 'description_text.dart';
import 'display_value.dart';
import 'raw_fields.dart';
import 'ui.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    this.preferred = false,
    this.showSeriesLink = false,
    this.onOpenSeries,
    this.compact = false,
    this.quantityLabel,
  });

  final Summary summary;
  final bool preferred;
  final bool showSeriesLink;
  final VoidCallback? onOpenSeries;
  final bool compact;
  final String? quantityLabel;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final detailed = scope.settings.detailedMode;
    final palette = context.palette;
    final quantity = DisplayQuantity.fromSummary(summary);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? Insets.m : Insets.l),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: preferred
              ? palette.primary.withValues(alpha: 0.55)
              : palette.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (preferred)
                      MetaChip(
                        strings.seriesPreferred,
                        tone: BadgeTone.info,
                        icon: Icons.check_circle_outline,
                      ),
                    MetaChip(
                      valueTypeShortLabel(summary.valueType, strings.lang),
                      tone: BadgeTone.neutral,
                      tooltip:
                          '${strings.summaryTypeLabel}: ${valueTypeLabel(summary.valueType, strings.lang)}',
                    ),
                    if (summary.inSummaryTable)
                      MetaChip(
                        strings.seriesInSummaryTable,
                        tone: BadgeTone.accent,
                      ),
                    if (summary.edition != null)
                      MetaChip(
                        'PDG ${summary.edition}',
                        tone: BadgeTone.neutral,
                      ),
                    if (quantity.isLimit || quantity.isRange)
                      MetaChip(
                        limitTypeLabel(summary.limitType, strings.lang),
                        tone: BadgeTone.warning,
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (scope.notes != null && summary.pdgid.isNotEmpty)
                    IconButton(
                      tooltip: strings.notesAddSummary,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final quantityLabel =
                            this.quantityLabel?.trim().isNotEmpty == true
                            ? this.quantityLabel!.trim()
                            : summary.pdgid;
                        final label = [
                          quantityLabel,
                          'PDG ${summary.pdgid}',
                          if (summary.edition != null) '${summary.edition}',
                          valueTypeLabel(summary.valueType, strings.lang),
                        ].join(' · ');
                        captureTextToNote(
                          context,
                          text: quantity.text,
                          anchors: [
                            NoteAnchorInput.pdgid(
                              summary.pdgid,
                              snapshotHash: scope.snapshotHash,
                              targetLabel: label,
                              context: summaryNoteContext(
                                summary,
                                displayText: quantity.text,
                                edition: scope.database.currentEdition,
                                quantityLabel: quantityLabel,
                              ),
                            ),
                          ],
                          label: label,
                        );
                      },
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                    ),
                  CopyIconButton(
                    text: _copyText(context, summary, quantity),
                    tooltip: strings.commonCopy,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Insets.s),
          SummaryValueLine(quantity: quantity, fontSize: compact ? 20 : 26),
          if (summary.comment != null && summary.comment!.isNotEmpty) ...[
            const SizedBox(height: Insets.s),
            DescriptionText(
              summary.comment!,
              selectable: true,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: Insets.s),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (summary.scaleFactor != null &&
                  (summary.scaleFactor! - 1).abs() > 1e-12)
                Text(
                  scaleFactorNote(summary.scaleFactor, strings.lang),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.warning),
                ),
              if (detailed)
                Text(
                  'pdgdata #${summary.id}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontFeatures: const [],
                  ),
                ),
            ],
          ),
          if (showSeriesLink && onOpenSeries != null) ...[
            const SizedBox(height: Insets.s),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onOpenSeries,
                child: Text(strings.commonDetails),
              ),
            ),
          ],
          RawFieldsPanel(fields: summary.rawFields),
        ],
      ),
    );
  }

  String _copyText(
    BuildContext context,
    Summary summary,
    DisplayQuantity quantity,
  ) {
    final strings = AppScope.of(context).strings;
    return [
      'PDG ${summary.edition ?? ''} · ${quantity.text}',
      '${strings.summaryTypeLabel}: ${valueTypeLabel(summary.valueType, strings.lang)} (${summary.valueType})',
      if (summary.inSummaryTable) strings.seriesInSummaryTable,
      if (summary.limitType != null)
        limitTypeLabel(summary.limitType, strings.lang),
      if (summary.comment != null && summary.comment!.isNotEmpty)
        summary.comment!,
      'pdgid ${summary.pdgid} · pdgdata #${summary.id}',
    ].join('\n');
  }
}

class SummaryList extends StatelessWidget {
  const SummaryList({
    super.key,
    required this.selection,
    this.onOpenSeries,
    this.compact = false,
    this.quantityLabel,
  });

  final SummarySelection selection;
  final VoidCallback? onOpenSeries;
  final bool compact;
  final String? quantityLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    if (selection.candidates.isEmpty) {
      return EmptyPanel(
        message: strings.seriesNoSummary,
        icon: Icons.functions,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selection.isAmbiguous)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: context.palette.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    strings.seriesMultipleCandidates,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.palette.warning),
                  ),
                ),
              ],
            ),
          ),
        for (final summary in selection.candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.s),
            child: SummaryCard(
              summary: summary,
              preferred: selection.preferred?.id == summary.id,
              showSeriesLink: onOpenSeries != null,
              onOpenSeries: onOpenSeries,
              compact: compact,
              quantityLabel: quantityLabel,
            ),
          ),
      ],
    );
  }
}

class HistoryTable extends StatefulWidget {
  const HistoryTable({
    super.key,
    required this.summaries,
    required this.currentEdition,
  });

  final List<Summary> summaries;
  final String currentEdition;

  @override
  State<HistoryTable> createState() => _HistoryTableState();
}

class _HistoryTableState extends State<HistoryTable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    if (widget.summaries.isEmpty) {
      return EmptyPanel(message: strings.seriesNoHistory, icon: Icons.history);
    }
    final editions = <String>[];
    for (final row in widget.summaries) {
      final edition = row.edition ?? '—';
      if (!editions.contains(edition)) editions.add(edition);
    }
    final visible = _expanded ? editions : editions.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.s),
          child: Text(
            '${editions.length} ${strings.seriesHistoryCount}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ),
        for (final edition in visible) ...[
          _EditionBlock(
            edition: edition,
            rows: widget.summaries
                .where((row) => (row.edition ?? '—') == edition)
                .toList(),
            isCurrent: edition == widget.currentEdition,
          ),
          const SizedBox(height: 6),
        ],
        if (editions.length > 6)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _expanded ? strings.commonShowLess : strings.commonShowMore,
              ),
            ),
          ),
      ],
    );
  }
}

class _EditionBlock extends StatelessWidget {
  const _EditionBlock({
    required this.edition,
    required this.rows,
    required this.isCurrent,
  });

  final String edition;
  final List<Summary> rows;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      padding: const EdgeInsets.all(Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PDG $edition',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                MetaChip(strings.seriesCurrentSummaries, tone: BadgeTone.info),
              const Spacer(),
              Text(
                '${rows.length} ${strings.commonCount}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in rows) _HistoryRow(row: row),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final Summary row;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final detailed = scope.settings.detailedMode;
    final palette = context.palette;
    final quantity = DisplayQuantity.fromSummary(row);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DisplayValueView(quantity, fontSize: 15),
              MetaChip(valueTypeShortLabel(row.valueType, strings.lang)),
              if (row.inSummaryTable) MetaChip(strings.seriesInSummaryTable),
              if (row.limitType != null)
                MetaChip(
                  limitTypeLabel(row.limitType, strings.lang),
                  tone: BadgeTone.warning,
                ),
              if (detailed)
                Text(
                  'pdgdata #${row.id}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
            ],
          ),
          if (row.comment != null && row.comment!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: DescriptionText(
                row.comment!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
          RawFieldsPanel(fields: row.rawFields),
        ],
      ),
    );
  }
}
