import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/pdg_notes.dart';
import '../common/description_text.dart';

/// PDG Live group header (title plus valence-quark content), shared by the
/// full catalog and particle pages.
class GroupHeaderCard extends StatelessWidget {
  const GroupHeaderCard({super.key, required this.header});

  final PdgGroupHeader header;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Insets.m, 12, Insets.m, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DescriptionText(
            header.title,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (header.content.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            DescriptionText(
              header.content,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
