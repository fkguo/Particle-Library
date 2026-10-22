import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../domain/labels.dart';

/// INSPIRE query cheat sheet, shared by the context sidebar and the Help page.
///
/// The text of the search box is forwarded to INSPIRE unchanged, so this only
/// documents the common forms.
class InspireSearchHelp extends StatelessWidget {
  const InspireSearchHelp({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final theme = Theme.of(context);
    final lang = strings.lang;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: palette.textSecondary,
    );
    final rows = <(String, String)>[
      ('a s weinberg', pick(lang, '作者', 'Author')),
      ('ea Weinberg, Steven', pick(lang, '精确作者', 'Exact author')),
      ('t muon', pick(lang, '题名', 'Title')),
      ('cn BESIII', pick(lang, '合作组', 'Collaboration')),
      ('doi 10.1103/...', 'DOI'),
      ('arXiv:1705.00141', 'arXiv'),
      ('recid 1597424', pick(lang, '记录号', 'Record id')),
      ('de 2020->2024', pick(lang, '日期', 'Date')),
      ('topcite 100+', pick(lang, '引用数', 'Citations')),
      ('ft <term>', pick(lang, '全文（= fulltext）', 'Full text (= fulltext)')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            strings.inspireHelpTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(strings.inspireHelpIntro, style: secondary),
        const SizedBox(height: 10),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  row.$1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 1),
                Text(row.$2, style: secondary),
              ],
            ),
          ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://help.inspirehep.net/knowledge-base/inspire-paper-search/',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(strings.inspireHelpOpenDocs),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://help.inspirehep.net/knowledge-base/full-listing-of-search-terms/',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(strings.inspireHelpOpenAllTerms),
            ),
          ],
        ),
      ],
    );
  }
}
