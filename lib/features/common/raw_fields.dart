import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../domain/models.dart';
import 'ui.dart';

class RawFieldsPanel extends StatefulWidget {
  const RawFieldsPanel({
    super.key,
    required this.fields,
    this.title,
    this.initiallyExpanded = false,
  });

  final List<RawField> fields;
  final String? title;
  final bool initiallyExpanded;

  @override
  State<RawFieldsPanel> createState() => _RawFieldsPanelState();
}

class _RawFieldsPanelState extends State<RawFieldsPanel> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (!scope.settings.detailedMode) return const SizedBox.shrink();
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    final title = widget.title ?? strings.commonRawFields;
    final header = InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_expanded ? Icons.expand_less : Icons.code,
                size: 14, color: palette.textSecondary),
            const SizedBox(width: 4),
            Text('$title · ${widget.fields.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    )),
            if (!_expanded)
              IconButton(
                tooltip: strings.commonCopyRaw,
                icon: const Icon(Icons.copy_all_outlined, size: 14),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: () => copyText(context, _allFields(widget.fields)),
              ),
          ],
        ),
      ),
    );
    if (!_expanded) {
      return Align(alignment: Alignment.centerLeft, child: header);
    }
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
            child: Row(
              children: [
                Expanded(child: header),
                IconButton(
                  tooltip: strings.commonCopyRaw,
                  icon: const Icon(Icons.copy_all_outlined, size: 15),
                  onPressed: () => copyText(context, _allFields(widget.fields)),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                strings.rawRecordHint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final field in widget.fields) _RawRow(field: field),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _allFields(List<RawField> fields) =>
      fields.map((field) => '${field.qualifiedName}\t${_value(field)}').join('\n');

  static String _value(RawField field) {
    if (field.value == null) return 'NULL';
    if (field.value is String && (field.value as String).isEmpty) return '""';
    return field.value.toString();
  }
}

class _RawRow extends StatelessWidget {
  const _RawRow({required this.field});

  final RawField field;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = field.value;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              field.qualifiedName,
              style: style?.copyWith(
                color: palette.textSecondary,
                fontFamily: AppFonts.monospaceFamily,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: value == null
                ? const _NullValue()
                : value is String && value.isEmpty
                    ? Text('""  (${AppScope.of(context).strings.emptyStringValue})',
                        style: style?.copyWith(color: palette.textSecondary))
                    : SelectableText(value.toString(), style: style),
          ),
        ],
      ),
    );
  }
}

class _NullValue extends StatelessWidget {
  const _NullValue();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text('NULL',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.warning,
              fontFamily: AppFonts.monospaceFamily,
              fontSize: 11.5,
            ));
  }
}
