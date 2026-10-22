import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/pdg_notes.dart';
import '../../domain/models.dart';
import '../common/description_text.dart';
import '../common/math_text.dart';
import '../common/page.dart';

/// A citation that appears only in a pdgLive summary. The local PDG listings
/// have no measurements for it, so this page shows the bibliographic record
/// completed from INSPIRE plus a link to the INSPIRE entry.
class PdgNoteReferencePage extends StatefulWidget {
  const PdgNoteReferencePage({super.key, required this.reference});

  final PdgNoteReference reference;

  @override
  State<PdgNoteReferencePage> createState() => _PdgNoteReferencePageState();
}

class _PdgNoteReferencePageState extends State<PdgNoteReferencePage> {
  List<Entry> _entries = const <Entry>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadEntries());
    });
  }

  Future<void> _loadEntries() async {
    final ids = await PdgNotes.entriesForCitation(widget.reference.documentId);
    if (!mounted || ids.isEmpty) return;
    final database = AppScope.of(context).database;
    final entries = <Entry>[];
    for (final id in ids) {
      final entry = await database.entryByPdgid(id);
      if (entry != null) entries.add(entry);
    }
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.reference;
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: palette.textSecondary,
    );
    final details = [
      if (reference.year != null) '${reference.year}',
      if ((reference.publication ?? '').isNotEmpty) reference.publication!,
    ].join(' · ');
    final inspireRecid = reference.inspireRecid;
    final doi = reference.doi ?? '';
    final arxivId = reference.arxivId ?? '';
    return PageScaffold(
      title: Text(reference.documentId),
      subtitle: strings.referencePdgLiveNote,
      actions: [
        if (inspireRecid != null)
          IconButton(
            tooltip: strings.inspireSearchOpenInspire,
            icon: const Icon(Icons.open_in_new, size: 19),
            onPressed: () => launchUrl(
              Uri.parse('https://inspirehep.net/literature/$inspireRecid'),
              mode: LaunchMode.externalApplication,
            ),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.l,
          Insets.m,
          Insets.l,
          Insets.xxl,
        ),
        children: [
          if ((reference.title ?? '').isNotEmpty)
            DescriptionText(
              reference.title!,
              selectable: true,
              style: theme.textTheme.titleMedium,
            ),
          if ((reference.authors ?? '').isNotEmpty) ...[
            const SizedBox(height: Insets.s),
            SelectableText(reference.authors!, style: secondary),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: Insets.xs),
            Text(details, style: secondary),
          ],
          if (doi.isNotEmpty) ...[
            const SizedBox(height: Insets.s),
            _LinkLine(
              label: 'DOI',
              value: doi,
              uri: Uri.parse('https://doi.org/$doi'),
            ),
          ],
          if (arxivId.isNotEmpty) ...[
            const SizedBox(height: Insets.xs),
            _LinkLine(
              label: 'arXiv',
              value: arxivId,
              uri: Uri.parse('https://arxiv.org/abs/$arxivId'),
            ),
          ],
          const SizedBox(height: Insets.l),
          Text(strings.referencePdgLiveExplanation, style: secondary),
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: Insets.l),
            Text(
              strings.referenceCitedByEntries,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: Insets.xs),
            for (final entry in _entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.science_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
                title: ParticleSymbol(entry.description, fontSize: 16),
                subtitle: Text('PDG ${entry.pdgid}', style: secondary),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => AppNav.openPdgid(context, entry.pdgid),
              ),
          ],
        ],
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({
    required this.label,
    required this.value,
    required this.uri,
  });

  final String label;
  final String value;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.accent,
            decoration: TextDecoration.underline,
            decorationColor: palette.accent,
          ),
        ),
      ),
    );
  }
}
