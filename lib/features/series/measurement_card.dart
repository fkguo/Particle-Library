import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../domain/display.dart';
import '../../domain/filters.dart';
import '../../domain/labels.dart';
import '../../domain/reference_title.dart';
import '../../data/reference_metadata.dart';
import '../../user/user_store.dart';
import '../../domain/models.dart';
import '../../notes/notes.dart';
import '../notes/notes_entity.dart';
import '../notes/note_capture.dart';
import '../notes/note_context.dart';
import '../notes/notes_format.dart';
import '../common/description_text.dart';
import '../common/display_value.dart';
import '../common/raw_fields.dart';
import '../common/ui.dart';

final Map<String, Future<String?>> _referenceTitleFutures =
    <String, Future<String?>>{};

Future<String?> _resolveReferenceTitle(UserStore store, Reference reference) {
  final doi = ReferenceMetadataService.normalizeDoi(reference.doi);
  final key = doi.toLowerCase();
  return _referenceTitleFutures.putIfAbsent(key, () async {
    try {
      final result = await const ReferenceMetadataService().fetchTitleByDoi(
        doi,
      );
      await store.cacheReferenceTitle(doi, result.title, source: result.source);
      return result.title;
    } catch (_) {
      return null;
    }
  });
}

class MeasurementCard extends StatelessWidget {
  const MeasurementCard({
    super.key,
    required this.bundle,
    this.filter = const MeasurementFilter(),
    this.showFilterHighlight = false,
    this.compact = false,
    this.seriesLabel = '',
  });

  final MeasurementBundle bundle;
  final MeasurementFilter filter;
  final bool showFilterHighlight;
  final bool compact;
  final String seriesLabel;

  Future<void> _addToNote(BuildContext context) async {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final measurement = bundle.measurement;
    final key = '${measurement.pdgid}:${measurement.id}';
    final series = seriesLabel.trim().isEmpty
        ? measurement.pdgid
        : seriesLabel.trim();
    final label = [
      series,
      if (measurement.technique.isNotEmpty)
        techniqueFullName(measurement.technique),
      '#${measurement.id}',
    ].join(' · ');
    final primary = bundle.primaryValue;
    final valueText = primary == null
        ? strings.measurementNoColumns
        : DisplayQuantity.fromValue(primary).text;
    await captureTextToNote(
      context,
      text: valueText,
      anchors: [
        NoteAnchorInput.measurement(
          key,
          snapshotHash: scope.snapshotHash,
          targetLabel: label,
          context: measurementNoteContext(
            measurement: measurement,
            value: primary,
            displayText: valueText,
            edition: scope.database.currentEdition,
            reference: bundle.reference,
            quantityLabel: series,
          ),
        ),
      ],
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final detailed = scope.settings.detailedMode;
    final palette = context.palette;
    final measurement = bundle.measurement;
    final reference = bundle.reference;
    final matching = bundle.values.where(filter.matchesValue).toSet();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.m, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (measurement.technique.isNotEmpty)
                        MetaChip(
                          techniqueFullName(measurement.technique),
                          tooltip: techniqueIsExpanded(measurement.technique)
                              ? strings.measurementTechniqueExpanded(
                                  measurement.technique,
                                )
                              : strings.measurementTechniqueUninterpreted,
                        ),
                      if (measurement.charge.isNotEmpty)
                        MetaChip(
                          'charge ${measurement.charge}',
                          tone: BadgeTone.info,
                          tooltip: strings.measurementCharge,
                        ),
                      if (measurement.place.isNotEmpty)
                        MetaChip(
                          'place ${measurement.place}',
                          tooltip: strings.measurementPlaceMeaning(
                            measurement.place,
                          ),
                        ),
                      if (detailed && measurement.changebar)
                        MetaChip(
                          strings.measurementChangebar,
                          tone: BadgeTone.warning,
                        ),
                      if (detailed)
                        MetaChip('pdgmeasurement #${measurement.id}'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.notesMeasurementAdd,
                  onPressed: () => _addToNote(context),
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                ),
                CopyButton(text: _copyText(context), compact: true),
              ],
            ),
          ),
          if (reference != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.s,
                Insets.l,
                0,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => AppNav.openReference(context, reference.id),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MeasurementReferenceTitle(
                        reference: reference,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: palette.primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          reference.documentId,
                          if (reference.publicationYear != null)
                            '${reference.publicationYear}',
                          if (reference.publicationName.isNotEmpty)
                            reference.publicationName,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.s,
                Insets.l,
                0,
              ),
              child: Text(
                strings.measurementNoReference,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.warning),
              ),
            ),
          if (measurement.eventCount.isNotEmpty ||
              measurement.confidenceLevel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.s,
                Insets.l,
                0,
              ),
              child: Wrap(
                spacing: 12,
                children: [
                  if (measurement.eventCount.isNotEmpty)
                    Text(
                      '${strings.measurementEvents}: ${measurement.eventCount}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (measurement.confidenceLevel != null)
                    Text(
                      'CL ${formatConfidence(measurement.confidenceLevel!)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          if (measurement.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.s,
                Insets.l,
                0,
              ),
              child: DescriptionText(
                '${strings.measurementComment}: ${measurement.comment}',
                selectable: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: Insets.s),
          if (bundle.values.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                0,
                Insets.l,
                Insets.m,
              ),
              child: Text(
                strings.measurementNoColumns,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            )
          else
            for (final value in bundle.values)
              _ValueBlock(
                value: value,
                measurement: measurement,
                highlighted: showFilterHighlight && matching.contains(value),
                showFilterHighlight: showFilterHighlight,
              ),
          if (bundle.footnotes.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(
                Insets.l,
                4,
                Insets.l,
                Insets.s,
              ),
              padding: const EdgeInsets.all(Insets.m),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.measurementFootnotes,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  for (final footnote in bundle.footnotes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MetaChip(
                            '#${footnote.footnoteIndex ?? footnote.id}',
                            tone: footnote.changebar
                                ? BadgeTone.warning
                                : BadgeTone.neutral,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DescriptionText(
                                  footnote.text,
                                  selectable: true,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                RawFieldsPanel(fields: footnote.rawFields),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.m),
            child: _MeasurementNotes(measurement: measurement),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.m),
            child: RawFieldsPanel(fields: measurement.rawFields),
          ),
        ],
      ),
    );
  }

  String _copyText(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final measurement = bundle.measurement;
    final lines = <String>[
      'pdgmeasurement #${measurement.id} · sort ${measurement.sort}',
      if (bundle.reference != null)
        cleanReferenceTitle(bundle.reference!.displayTitle),
      if (bundle.reference != null) bundle.reference!.documentId,
      if (measurement.technique.isNotEmpty)
        'technique ${measurement.technique}',
      if (measurement.charge.isNotEmpty) 'charge ${measurement.charge}',
      if (measurement.place.isNotEmpty) 'place ${measurement.place}',
      if (measurement.eventCount.isNotEmpty) 'events ${measurement.eventCount}',
      if (measurement.comment.isNotEmpty) measurement.comment,
      for (final value in bundle.values)
        [
          value.columnName.isEmpty ? strings.unnamedColumn : value.columnName,
          DisplayQuantity.fromValue(value).text,
          inclusionLabel(value.usedInAverage, 'average', strings.lang),
          inclusionLabel(value.usedInFit, 'fit', strings.lang),
          if (value.limitType != null)
            limitTypeLabel(value.limitType, strings.lang),
        ].where((part) => part.isNotEmpty).join(' | '),
      for (final footnote in bundle.footnotes)
        '[${footnote.footnoteIndex}] ${footnote.text}',
    ];
    return lines.join('\n');
  }
}

class _ValueBlock extends StatefulWidget {
  const _ValueBlock({
    required this.value,
    required this.measurement,
    required this.highlighted,
    required this.showFilterHighlight,
  });

  final MeasurementValue value;
  final Measurement measurement;
  final bool highlighted;
  final bool showFilterHighlight;

  @override
  State<_ValueBlock> createState() => _ValueBlockState();
}

class _ValueBlockState extends State<_ValueBlock> {
  bool _showErrors = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final value = widget.value;
    final quantity = DisplayQuantity.fromValue(value);
    final column = value.columnName.trim().isEmpty
        ? strings.unnamedColumn
        : value.columnName;
    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.s),
      padding: const EdgeInsets.all(Insets.m),
      decoration: BoxDecoration(
        color: widget.highlighted
            ? palette.primary.withValues(alpha: 0.055)
            : palette.measurementSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.highlighted ? palette.primary : palette.divider,
          width: widget.highlighted ? 1.3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                column,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (value.limitType != null)
                MetaChip(
                  limitTypeLabel(value.limitType, strings.lang),
                  tone: BadgeTone.warning,
                ),
              if (widget.highlighted && widget.showFilterHighlight)
                MetaChip(strings.commonFilter, tone: BadgeTone.info),
              MetaChip(
                inclusionLabel(value.usedInAverage, 'average', strings.lang),
                tone: _inclusionTone(value.usedInAverage),
                tooltip: strings.measurementFlagNote,
              ),
              MetaChip(
                inclusionLabel(value.usedInFit, 'fit', strings.lang),
                tone: _inclusionTone(value.usedInFit),
                tooltip: strings.measurementFlagNote,
              ),
            ],
          ),
          const SizedBox(height: 4),
          DisplayValueView(quantity, fontSize: 22),
          if (value.displayValueText.isEmpty &&
              value.value == null &&
              value.valueText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${strings.measurementSourceText}: ${value.valueText}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.warning),
              ),
            ),
          if (_hasErrors(value))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => setState(() => _showErrors = !_showErrors),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showErrors ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      strings.measurementErrors,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          if (_showErrors) ...[
            const SizedBox(height: 4),
            _ErrorTable(value: value),
          ],
          const SizedBox(height: 2),
          RawFieldsPanel(
            fields: value.rawFields,
            title: strings.commonRawFields,
          ),
        ],
      ),
    );
  }

  static bool _hasErrors(MeasurementValue value) =>
      value.errorPositive != null ||
      value.errorNegative != null ||
      value.statErrorPositive != null ||
      value.statErrorNegative != null ||
      value.systErrorPositive != null ||
      value.systErrorNegative != null;

  static BadgeTone _inclusionTone(bool? value) => value == null
      ? BadgeTone.warning
      : (value ? BadgeTone.accent : BadgeTone.neutral);
}

class _ErrorTable extends StatelessWidget {
  const _ErrorTable({required this.value});

  final MeasurementValue value;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final style = Theme.of(context).textTheme.bodySmall;
    String number(double? value) => value == null ? '—' : rawNumber(value);
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            Text('', style: style),
            Text('+', style: style),
            Text('−', style: style),
          ],
        ),
        TableRow(
          children: [
            Text(strings.measurementTotal, style: style),
            Text(number(value.errorPositive), style: style),
            Text(number(value.errorNegative), style: style),
          ],
        ),
        TableRow(
          children: [
            Text(strings.measurementStat, style: style),
            Text(number(value.statErrorPositive), style: style),
            Text(number(value.statErrorNegative), style: style),
          ],
        ),
        TableRow(
          children: [
            Text(strings.measurementSyst, style: style),
            Text(number(value.systErrorPositive), style: style),
            Text(number(value.systErrorNegative), style: style),
          ],
        ),
      ],
    );
  }
}

/// Compact backlink list for notes attached to this exact measurement row.
class _MeasurementReferenceTitle extends StatelessWidget {
  const _MeasurementReferenceTitle({
    required this.reference,
    required this.style,
  });

  final Reference reference;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final local = cleanReferenceTitle(reference.displayTitle);
    final cached = store.cachedReferenceTitle(reference.doi);
    final cachedTitle = cached == null
        ? null
        : cleanReferenceTitle(cached.title);
    final current = cachedTitle ?? local;
    final needsEnrichment = referenceTitleLooksTruncated(current);
    if (!needsEnrichment ||
        !ReferenceMetadataService.isValidDoi(reference.doi)) {
      return DescriptionText(current, maxLines: 2, style: style);
    }
    return FutureBuilder<String?>(
      future: _resolveReferenceTitle(store, reference),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        final title = resolved == null
            ? '$current…'
            : cleanReferenceTitle(resolved);
        return DescriptionText(title, maxLines: 2, style: style);
      },
    );
  }
}

class _MeasurementNotes extends StatefulWidget {
  const _MeasurementNotes({required this.measurement});

  final Measurement measurement;

  @override
  State<_MeasurementNotes> createState() => _MeasurementNotesState();
}

class _MeasurementNotesState extends State<_MeasurementNotes> {
  List<NoteRecord> _notes = const <NoteRecord>[];
  bool _loaded = false;
  ValueNotifier<int>? _changes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (!identical(scope.notesChanges, _changes)) {
      _changes?.removeListener(_onNotesChanged);
      _changes = scope.notesChanges..addListener(_onNotesChanged);
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _changes?.removeListener(_onNotesChanged);
    super.dispose();
  }

  void _onNotesChanged() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    final store = AppScope.of(context).notes;
    if (store == null) return;
    final notes = await store.notesForTarget(
      NoteTargetKinds.measurement,
      _key,
      limit: 20,
    );
    if (!mounted) return;
    setState(() => _notes = notes);
  }

  String get _key => '${widget.measurement.pdgid}:${widget.measurement.id}';

  Future<void> _show() async {
    final strings = AppScope.of(context).strings;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.notesTitle),
        content: SizedBox(
          width: 480,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final note in _notes)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.sticky_note_2_outlined, size: 18),
                    title: Text(
                      noteDisplayTitle(note, strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      noteBodyPreview(note, maxLength: 100),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      openNoteEditor(context, note);
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.commonClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_notes.isEmpty) return const SizedBox.shrink();
    final strings = AppScope.of(context).strings;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _show,
        icon: const Icon(Icons.sticky_note_2_outlined, size: 15),
        label: Text('${strings.notesTitle} · ${_notes.length}'),
      ),
    );
  }
}
