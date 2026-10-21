import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../domain/display.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../data/pdg_database.dart';
import '../../domain/views.dart';
import 'description_text.dart';
import '../notes/notes_anchor.dart';
import '../notes/notes_entity.dart';
import 'resize_handle.dart';

bool showContextSidebar(BuildContext context, double width) {
  final mode = AppScope.of(context).settings.sidebarMode;
  if (mode == 'off') return false;
  if (mode == 'always') return width >= 480;
  return width >= 620;
}

double contextSidebarWidth(double width) =>
    width >= 1120 ? 320 : (width >= 720 ? 280 : 240);

double? _contextSidebarOverride;

/// Context rail with a draggable divider on its left edge.
///
/// The width is shared for the current session, so resizing a series page
/// carries over to particle/mode/topic/reference pages. Double-click resets to
/// the responsive default.
class ResizableContextSidebar extends StatefulWidget {
  const ResizableContextSidebar({
    super.key,
    required this.viewportWidth,
    required this.child,
  });

  final double viewportWidth;
  final Widget child;

  @override
  State<ResizableContextSidebar> createState() =>
      _ResizableContextSidebarState();
}

class _ResizableContextSidebarState extends State<ResizableContextSidebar> {
  late double _width;

  @override
  void initState() {
    super.initState();
    _width =
        _contextSidebarOverride ?? contextSidebarWidth(widget.viewportWidth);
  }

  double get _minWidth => 220;
  double get _maxWidth => (widget.viewportWidth - 360).clamp(_minWidth, 520.0);

  double get _currentWidth => _width.clamp(_minWidth, _maxWidth);

  @override
  Widget build(BuildContext context) {
    final width = _currentWidth;
    return CollapsibleSidePanel(
      width: width,
      handleOnLeft: true,
      tooltip: AppScope.of(context).strings.contextSidebarResizeTooltip,
      onDrag: (delta) {
        final next = (width - delta).clamp(_minWidth, _maxWidth);
        // Pulling the rail all the way to its minimum collapses it, and the
        // app-bar toggle can bring it back.
        if (delta < 0 && next <= _minWidth + 2) {
          _contextSidebarOverride = null;
          unawaited(AppScope.of(context).settings.setSidebarMode('off'));
          return;
        }
        setState(() => _width = next);
        _contextSidebarOverride = next;
      },
      onReset: () {
        final auto = contextSidebarWidth(widget.viewportWidth);
        setState(() => _width = auto);
        _contextSidebarOverride = null;
      },
      child: widget.child,
    );
  }
}

class SidebarFact {
  const SidebarFact(this.label, this.value);
  final String label;
  final String value;
}

class ContextSidebar extends StatefulWidget {
  const ContextSidebar({
    super.key,
    required this.facts,
    required this.sections,
    this.notes,
  });

  final List<SidebarFact> facts;
  final List<Widget> sections;

  /// Optional Notes tab. When present, the rail switches between entity
  /// context and notes without mixing the two.
  final Widget? notes;

  @override
  State<ContextSidebar> createState() => _ContextSidebarState();
}

class _ContextSidebarState extends State<ContextSidebar> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.divider)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.sidebarTitle,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (widget.notes != null) ...[
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment(value: 0, label: Text(strings.sidebarTitle)),
                ButtonSegment(value: 1, label: Text(strings.sidebarNotes)),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) {
                setState(() => _tab = selection.first);
              },
            ),
          ],
          const SizedBox(height: 10),
          if (widget.notes != null && _tab == 1)
            widget.notes!
          else ...[
            _FactsCard(facts: widget.facts),
            const SizedBox(height: 14),
            for (final section in widget.sections) ...[
              section,
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});
  final List<SidebarFact> facts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    facts[i].label,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    facts[i].value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SidebarSection extends StatelessWidget {
  const SidebarSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class SidebarEntryTile extends StatelessWidget {
  const SidebarEntryTile({
    super.key,
    required this.entry,
    this.subtitle,
    this.value,
    this.last = false,
  });

  final Entry entry;
  final String? subtitle;
  final String? value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: palette.accent.withValues(alpha: 0.08),
      onTap: () => AppNav.openPdgid(context, entry.pdgid),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 8, 8, last ? 8 : 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DescriptionText(entry.description, maxLines: 2),
            const SizedBox(height: 2),
            Text(
              subtitle ?? entry.pdgid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            if (value != null && value!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String sidebarType(Entry entry, TextLang lang) =>
    dataTypeInfo(entry.dataType).label(lang);

class SeriesContextSidebar extends StatelessWidget {
  const SeriesContextSidebar({super.key, required this.view});

  final SeriesView view;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final lang = strings.lang;
    final entry = view.entry;
    final notes = seriesNotesContext(
      entry,
      parent: view.ancestors.isEmpty ? null : view.ancestors.last,
      snapshotHash: scope.snapshotHash,
    );
    final related = view.relatedSources
        .where((row) => row.target.pdgid != entry.pdgid)
        .take(8)
        .toList(growable: false);
    final parents = view.ancestors.reversed.take(4).toList(growable: false);
    return ContextSidebar(
      notes: SidebarNotesSection(
        targets: notes.targets,
        anchors: notes.anchors,
      ),
      facts: [
        SidebarFact('PDG ID', entry.pdgid),
        SidebarFact(strings.sidebarType, sidebarType(entry, lang)),
        SidebarFact(strings.sidebarEdition, view.currentEdition),
        SidebarFact(
          strings.sidebarSummaries,
          '${view.currentSummaries.length}',
        ),
        SidebarFact(
          strings.sidebarMeasurements,
          '${view.directMeasurementCount}',
        ),
        SidebarFact(strings.sidebarHistory, '${view.historyEditions.length}'),
      ],
      sections: [
        if (related.isNotEmpty)
          SidebarSection(
            title: strings.sidebarSeeAlso,
            children: [
              for (var i = 0; i < related.length; i++)
                SidebarEntryTile(
                  entry: related[i].target,
                  subtitle: sidebarType(related[i].target, lang),
                  value: related[i].summaryCount > 0
                      ? '${related[i].summaryCount} ${strings.sidebarSummariesShort}'
                      : null,
                  last: i == related.length - 1,
                ),
            ],
          ),
        if (view.siblings.isNotEmpty)
          SidebarSection(
            title: strings.sidebarSiblings,
            children: [
              for (var i = 0; i < view.siblings.take(8).length; i++)
                SidebarEntryTile(
                  entry: view.siblings[i],
                  subtitle: sidebarType(view.siblings[i], lang),
                  last: i == view.siblings.take(8).length - 1,
                ),
            ],
          ),
        if (parents.isNotEmpty)
          SidebarSection(
            title: strings.sidebarParents,
            children: [
              for (var i = 0; i < parents.length; i++)
                SidebarEntryTile(
                  entry: parents[i],
                  subtitle: parents[i].pdgid,
                  last: i == parents.length - 1,
                ),
            ],
          ),
      ],
    );
  }
}

class ParticleContextSidebar extends StatelessWidget {
  const ParticleContextSidebar({super.key, required this.view});

  final ParticleView view;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final lang = strings.lang;
    final notes = particleNotesContext(
      view.entry,
      snapshotHash: scope.snapshotHash,
    );
    final properties = view.properties.take(6).toList(growable: false);
    final decays = view.decays.take(5).toList(growable: false);
    return ContextSidebar(
      notes: SidebarNotesSection(
        targets: notes.targets,
        anchors: notes.anchors,
      ),
      facts: [
        SidebarFact('PDG ID', view.entry.pdgid),
        SidebarFact(strings.sidebarType, sidebarType(view.entry, lang)),
        SidebarFact(strings.sidebarEdition, view.currentEdition),
        SidebarFact(strings.sidebarIdentities, '${view.particles.length}'),
        SidebarFact(strings.sidebarProperties, '${view.properties.length}'),
        SidebarFact(strings.sidebarDecays, '${view.decays.length}'),
        SidebarFact(strings.sidebarReferences, '${view.referenceCount}'),
      ],
      sections: [
        if (properties.isNotEmpty)
          SidebarSection(
            title: '${strings.sidebarSeeAlso} · ${strings.sidebarProperties}',
            children: [
              for (var i = 0; i < properties.length; i++)
                SidebarEntryTile(
                  entry: properties[i],
                  subtitle: sidebarType(properties[i], lang),
                  value: propertyPreview(view, properties[i]),
                  last: i == properties.length - 1,
                ),
            ],
          ),
        if (decays.isNotEmpty)
          SidebarSection(
            title: '${strings.sidebarSeeAlso} · ${strings.sidebarDecays}',
            children: [
              for (var i = 0; i < decays.length; i++)
                SidebarEntryTile(
                  entry: decays[i],
                  subtitle: sidebarType(decays[i], lang),
                  last: i == decays.length - 1,
                ),
            ],
          ),
      ],
    );
  }

  String? propertyPreview(ParticleView view, Entry property) {
    final selection = view.summaryFor(property.id);
    final summary = selection.preferred;
    if (summary == null) return null;
    return DisplayQuantity.fromSummary(summary).text;
  }
}

class TopicContextSidebar extends StatelessWidget {
  const TopicContextSidebar({super.key, required this.view});

  final EntryView view;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final lang = strings.lang;
    final children = view.children.take(8).toList(growable: false);
    final parents = view.ancestors.reversed.take(4).toList(growable: false);
    final notes = particleNotesContext(
      view.entry,
      snapshotHash: AppScope.of(context).snapshotHash,
    );
    return ContextSidebar(
      notes: SidebarNotesSection(
        targets: notes.targets,
        anchors: notes.anchors,
      ),
      facts: [
        SidebarFact('PDG ID', view.entry.pdgid),
        SidebarFact(strings.sidebarType, sidebarType(view.entry, lang)),
        SidebarFact(strings.sidebarEdition, view.currentEdition),
        SidebarFact(strings.sidebarChildren, '${view.children.length}'),
        SidebarFact(strings.sidebarMeasurements, '${view.measurementCount}'),
      ],
      sections: [
        if (children.isNotEmpty)
          SidebarSection(
            title: '${strings.sidebarSeeAlso} · ${strings.sidebarChildren}',
            children: [
              for (var i = 0; i < children.length; i++)
                SidebarEntryTile(
                  entry: children[i],
                  subtitle: sidebarType(children[i], lang),
                  value: _childValue(view, children[i]),
                  last: i == children.length - 1,
                ),
            ],
          ),
        if (parents.isNotEmpty)
          SidebarSection(
            title: strings.sidebarParents,
            children: [
              for (var i = 0; i < parents.length; i++)
                SidebarEntryTile(
                  entry: parents[i],
                  subtitle: parents[i].pdgid,
                  last: i == parents.length - 1,
                ),
            ],
          ),
      ],
    );
  }

  String? _childValue(EntryView view, Entry child) {
    final preferred = view.selectionForChild(child.id).preferred;
    return preferred == null
        ? null
        : DisplayQuantity.fromSummary(preferred).text;
  }
}

class ModeContextSidebar extends StatelessWidget {
  const ModeContextSidebar({super.key, required this.view});

  final ModeView view;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final lang = strings.lang;
    final related = view.related.take(8).toList(growable: false);
    final children = view.children.take(6).toList(growable: false);
    final parents = view.ancestors.reversed.take(4).toList(growable: false);
    final notes = particleNotesContext(
      view.entry,
      snapshotHash: scope.snapshotHash,
    );
    return ContextSidebar(
      notes: SidebarNotesSection(
        targets: notes.targets,
        anchors: notes.anchors,
      ),
      facts: [
        SidebarFact('PDG ID', view.entry.pdgid),
        SidebarFact(strings.sidebarType, sidebarType(view.entry, lang)),
        SidebarFact(strings.sidebarEdition, view.currentEdition),
        SidebarFact(
          strings.sidebarSummaries,
          '${view.currentSummaries.length}',
        ),
        SidebarFact(
          strings.sidebarMeasurements,
          '${view.directMeasurementCount}',
        ),
        SidebarFact(strings.sidebarChildren, '${view.children.length}'),
      ],
      sections: [
        if (related.isNotEmpty)
          SidebarSection(
            title: strings.sidebarSeeAlso,
            children: [
              for (var i = 0; i < related.length; i++)
                SidebarEntryTile(
                  entry: related[i].target,
                  subtitle: sidebarType(related[i].target, lang),
                  value: related[i].summaryCount > 0
                      ? '${related[i].summaryCount} ${strings.sidebarSummariesShort}'
                      : null,
                  last: i == related.length - 1,
                ),
            ],
          ),
        if (children.isNotEmpty)
          SidebarSection(
            title: strings.sidebarChildren,
            children: [
              for (var i = 0; i < children.length; i++)
                SidebarEntryTile(
                  entry: children[i],
                  subtitle: sidebarType(children[i], lang),
                  last: i == children.length - 1,
                ),
            ],
          ),
        if (parents.isNotEmpty)
          SidebarSection(
            title: strings.sidebarParents,
            children: [
              for (var i = 0; i < parents.length; i++)
                SidebarEntryTile(
                  entry: parents[i],
                  subtitle: parents[i].pdgid,
                  last: i == parents.length - 1,
                ),
            ],
          ),
      ],
    );
  }
}

class ReferenceContextSidebar extends StatelessWidget {
  const ReferenceContextSidebar({
    super.key,
    required this.reference,
    required this.groups,
    required this.displayTitle,
  });

  final Reference reference;
  final List<ReferenceSeriesGroup> groups;
  final String displayTitle;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final lang = strings.lang;
    final notes = referenceNotesContext(
      reference,
      snapshotHash: scope.snapshotHash,
      displayTitle: displayTitle,
    );
    return ContextSidebar(
      notes: SidebarNotesSection(
        targets: notes.targets,
        anchors: notes.anchors,
      ),
      facts: [
        SidebarFact('Document', reference.documentId),
        if (reference.publicationYear != null)
          SidebarFact(strings.commonYear, '${reference.publicationYear}'),
        SidebarFact('DOI', reference.doi.isEmpty ? '—' : reference.doi),
        SidebarFact(
          'INSPIRE',
          reference.inspireId.isEmpty ? '—' : reference.inspireId,
        ),
      ],
      sections: [
        if (groups.isNotEmpty)
          SidebarSection(
            title: strings.sidebarSeeAlso,
            children: [
              for (var i = 0; i < groups.take(8).length; i++)
                SidebarEntryTile(
                  entry: Entry({
                    'id': groups[i].entryId,
                    'pdgid': groups[i].pdgid,
                    'description': groups[i].description,
                    'data_type': groups[i].dataType,
                    'flags': '',
                    'parent_id': null,
                    'sort': 0,
                  }),
                  subtitle:
                      '${sidebarType(Entry({'data_type': groups[i].dataType}), lang)} · ${groups[i].count} ${strings.commonCount}',
                  last: i == groups.take(8).length - 1,
                ),
            ],
          ),
      ],
    );
  }
}
