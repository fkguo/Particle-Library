import 'package:flutter/material.dart';

import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import 'notes_format.dart';

/// Shared tag input used by the full note editor and PDF annotation editor.
///
/// Tags are comma-separated text (the same grammar as `parseNoteTags`), with
/// one-tap suggestions from the user's existing tags. This intentionally keeps
/// the annotation editor from growing a second tag syntax.
class NoteTagField extends StatelessWidget {
  const NoteTagField({
    super.key,
    required this.controller,
    required this.knownTags,
    required this.strings,
    this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final List<String> knownTags;
  final AppStrings strings;
  final VoidCallback? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = parseNoteTags(controller.text);
    final suggestions = knownTags
        .where((tag) => !current.contains(tag))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          style: Theme.of(context).textTheme.bodySmall,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged?.call(),
          decoration: InputDecoration(
            hintText: strings.notesTagsHint,
            prefixIcon: Icon(
              Icons.sell_outlined,
              size: 16,
              color: palette.textSecondary,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 20,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              for (final tag in suggestions)
                ActionChip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () {
                    final next = parseNoteTags(controller.text)..add(tag);
                    controller.text = next.join(', ');
                    onChanged?.call();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
