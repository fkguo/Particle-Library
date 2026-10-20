import 'package:flutter/material.dart';

import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../notes/note_evidence.dart';
import '../common/ui.dart';

/// Read-only Evidence view for one Notes scope. It receives already-derived
/// rows so it never queries the PDG snapshot or writes anything itself.
class NotesEvidenceView extends StatelessWidget {
  const NotesEvidenceView({
    super.key,
    required this.rows,
    required this.strings,
    this.onOpenRow,
    this.onOpenNote,
    this.onExport,
  });

  final List<NoteEvidenceRow> rows;
  final AppStrings strings;
  final ValueChanged<NoteEvidenceRow>? onOpenRow;
  final ValueChanged<String>? onOpenNote;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyPanel(
        message: strings.notesEvidenceEmpty,
        icon: Icons.table_chart_outlined,
        action: onExport == null
            ? null
            : OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(strings.notesExportCsv),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 1280;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.s,
                Insets.l,
                Insets.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${strings.notesEvidence} · ${rows.length}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: context.palette.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      if (onExport != null)
                        TextButton.icon(
                          onPressed: onExport,
                          icon: const Icon(Icons.download_outlined, size: 17),
                          label: Text(strings.notesExportCsv),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      strings.notesEvidenceHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: wide ? _table(context) : _cards(context)),
          ],
        );
      },
    );
  }

  Widget _table(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.xxl),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.4),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(0.9),
          4: FlexColumnWidth(0.7),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: palette.divider),
          bottom: BorderSide(color: palette.divider),
        ),
        children: [
          TableRow(
            children: [
              _header(context, strings.notesEvidenceQuantity),
              _header(context, strings.notesEvidenceCaptured),
              _header(context, strings.notesEvidenceCurrent),
              _header(context, strings.notesEvidenceStatusLabel),
              _header(context, strings.notesCollectionNoteCount),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                _cell(
                  context,
                  row.title,
                  onTap: onOpenRow == null ? null : () => onOpenRow!(row),
                ),
                _cell(context, _captured(row), muted: true),
                _cell(context, _current(row)),
                _status(context, row.status),
                _cell(context, '${row.noteCount}'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cards(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.xxl),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final palette = context.palette;
        return Card(
          margin: const EdgeInsets.only(bottom: Insets.s),
          child: InkWell(
            onTap: onOpenRow == null ? null : () => onOpenRow!(row),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(Insets.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      _statusChip(context, row.status),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    '${strings.notesEvidenceCaptured}: ${_captured(row)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${strings.notesEvidenceCurrent}: ${_current(row)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: Insets.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${row.noteCount} ${strings.notesCollectionNoteCount}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ),
                      if (onOpenNote != null && row.noteIds.isNotEmpty)
                        TextButton(
                          onPressed: () => onOpenNote!(row.noteIds.first),
                          child: Text(strings.commonDetails),
                        ),
                      if (onOpenRow != null)
                        IconButton(
                          tooltip: strings.commonOpen,
                          onPressed: () => onOpenRow!(row),
                          icon: const Icon(Icons.open_in_new, size: 17),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.palette.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _cell(
    BuildContext context,
    String text, {
    bool muted = false,
    VoidCallback? onTap,
  }) {
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: muted ? context.palette.textSecondary : null),
      ),
    );
    return onTap == null
        ? child
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: child),
          );
  }

  Widget _status(BuildContext context, NoteEvidenceStatus status) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: _statusChip(context, status),
    ),
  );

  Widget _statusChip(BuildContext context, NoteEvidenceStatus status) {
    final color = switch (status) {
      NoteEvidenceStatus.current => context.palette.primary,
      NoteEvidenceStatus.changed => context.palette.warning,
      NoteEvidenceStatus.missing => context.palette.error,
      NoteEvidenceStatus.fuzzy => context.palette.warning,
      NoteEvidenceStatus.unresolved => context.palette.error,
      NoteEvidenceStatus.uncompared => context.palette.textSecondary,
    };
    final label = switch (status) {
      NoteEvidenceStatus.current => strings.notesEvidenceStatusCurrent,
      NoteEvidenceStatus.changed => strings.notesEvidenceStatusChanged,
      NoteEvidenceStatus.missing => strings.notesEvidenceStatusMissing,
      NoteEvidenceStatus.fuzzy => strings.notesEvidenceStatusFuzzy,
      NoteEvidenceStatus.unresolved => strings.notesEvidenceStatusUnresolved,
      NoteEvidenceStatus.uncompared => strings.notesEvidenceStatusUncompared,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  String _captured(NoteEvidenceRow row) {
    final value = row.capturedValue;
    final edition = row.captured?.edition;
    if (value == '—' && edition == null) {
      return strings.notesEvidenceNotRecorded;
    }
    return [value, if (edition != null) 'PDG $edition'].join(' · ');
  }

  String _current(NoteEvidenceRow row) {
    final value = row.currentValue;
    final edition = row.current?.edition;
    if (value == '—' && edition == null) return '—';
    return [value, if (edition != null) 'PDG $edition'].join(' · ');
  }
}
