import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/navigation.dart';
import '../../notes/notes.dart';
import '../common/floating_panel.dart';
import 'note_editor.dart';
import 'notes_anchor.dart';
import 'notes_format.dart';

/// Last collection explicitly chosen in the capture sheet. This is an
/// in-memory convenience default, not a second source of collection truth.
abstract final class NoteCaptureDefaults {
  static String? lastCollectionId;
}

String selectedQuoteBlock(String text, String label) {
  final quote = text
      .trim()
      .split('\n')
      .map((line) => line.trim().isEmpty ? '>' : '> $line')
      .join('\n');
  return '$quote\n\n**${label.trim()}**';
}

Future<void> captureTextToNote(
  BuildContext context, {
  required String text,
  required List<NoteAnchorInput> anchors,
  required String label,
  bool anchorOnly = false,
  List<NoteTarget> lookupTargets = const <NoteTarget>[],
}) async {
  final scope = AppScope.of(context);
  final store = scope.notes;
  final strings = scope.strings;
  if (store == null || (!anchorOnly && text.trim().isEmpty)) return;

  final existing = <NoteRecord>[];
  final targets = <String, NoteTarget>{
    for (final target in lookupTargets)
      '${target.kind}\u0000${target.key}': target,
    for (final anchor in anchors)
      '${anchor.targetKind}\u0000${anchor.targetKey}': NoteTarget(
        kind: anchor.targetKind,
        key: anchor.targetKey,
      ),
  }.values;
  for (final target in targets) {
    existing.addAll(
      await store.notesForTarget(target.kind, target.key, limit: 8),
    );
  }
  final recent = await store.recent(limit: 30);
  final unique = <String, NoteRecord>{
    for (final note in [...existing, ...recent]) note.id: note,
  }.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final collections = await store.collections();
  var selectedCollectionId = NoteCaptureDefaults.lastCollectionId;
  if (!collections.any((collection) => collection.id == selectedCollectionId)) {
    selectedCollectionId = null;
  }

  if (!context.mounted) return;
  final searchController = TextEditingController();
  // The capture dialog is modal: hide floating lookup panels first, otherwise
  // they sit above the dialog (overlay entries) and cover part of it.
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final dialogContext = rootNavigator.context;
  FloatingPanelHost.suspendAll();
  final choice = await showDialog<_CaptureChoice>(
    context: dialogContext,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final query = searchController.text.trim();
        final visible = query.isEmpty
            ? unique.take(6).toList(growable: false)
            : unique
                  .where((note) => noteMatchesQuery(note, query))
                  .take(8)
                  .toList(growable: false);
        return AlertDialog(
          title: Text(strings.notesCaptureTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  if (!anchorOnly) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        text.trim().length > 600
                            ? '${text.trim().substring(0, 600)}…'
                            : text.trim(),
                        maxLines: 7,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (collections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: strings.notesCollections,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedCollectionId,
                          hint: Text(strings.notesNoCollections),
                          items: [
                            for (final collection in collections)
                              DropdownMenuItem<String>(
                                value: collection.id,
                                child: Text(collection.name),
                              ),
                          ],
                          onChanged: (value) => setDialogState(
                            () => selectedCollectionId = value,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    strings.notesCaptureAppendHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (unique.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: strings.notesCaptureSearchHint,
                        prefixIcon: const Icon(Icons.search, size: 17),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: visible.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                strings.notesNoSearchResults,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final note in visible)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.note_alt_outlined,
                                      size: 18,
                                    ),
                                    title: Text(
                                      noteDisplayTitle(note, strings),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      noteBodyPreview(note).isEmpty
                                          ? [
                                              noteUpdatedLabel(
                                                note.updatedAt,
                                                strings,
                                              ),
                                              if (note.anchors.isNotEmpty)
                                                anchorDisplayLabel(
                                                  note.anchors.first,
                                                ),
                                            ].join(' · ')
                                          : noteBodyPreview(note),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => Navigator.of(dialogContext)
                                        .pop(_CaptureChoice(existing: note)),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.commonCancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const _CaptureChoice()),
              child: Text(strings.notesCaptureSave),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(dialogContext)
                      .pop(const _CaptureChoice(openAfterSave: true)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(strings.notesCaptureSaveAndOpen),
            ),
          ],
        );
      },
    ),
  );
  searchController.dispose();
  if (choice == null) {
    FloatingPanelHost.resumeAll();
    return;
  }
  if (choice.openAfterSave) {
    FloatingPanelHost.closeAll();
  } else {
    FloatingPanelHost.resumeAll();
  }

  final sourceLines = <String>[];
  final seenSources = <String>{};
  for (final anchor in anchors) {
    final sourceLabel = anchor.targetLabel.trim().isEmpty
        ? label
        : anchor.targetLabel;
    final line =
        '[${strings.notesSourceLine(sourceLabel)}](${anchor.targetId})';
    if (seenSources.add(line)) sourceLines.add(line);
  }
  final quote = anchorOnly
      ? sourceLines.join('\n')
      : [
          selectedQuoteBlock(text, label),
          if (sourceLines.isNotEmpty) sourceLines.join('\n'),
        ].join('\n\n');
  final NoteRecord record;
  try {
    if (choice.existing != null) {
      final note = choice.existing!;
      final body = note.bodyMarkdown.trim().isEmpty
          ? quote
          : '${note.bodyMarkdown.trim()}\n\n$quote';
      final mergedByKey = <String, NoteAnchorInput>{};
      for (final anchor in note.anchors) {
        mergedByKey['${anchor.targetId}\u0000${anchor.snapshotHash}'] =
            NoteAnchorInput(
              targetKind: anchor.targetKind,
              targetKey: anchor.targetKey,
              snapshotHash: anchor.snapshotHash.isEmpty
                  ? null
                  : anchor.snapshotHash,
              targetLabel: anchor.targetLabel,
              status: anchor.status,
              context: anchor.context,
            );
      }
      for (final anchor in anchors) {
        final key = '${anchor.targetId}\u0000${anchor.snapshotHash ?? ''}';
        final existing = mergedByKey[key];
        if (existing != null && anchor.context == null) {
          // Keep an existing context when appending a plain source link.
          continue;
        }
        mergedByKey[key] = anchor;
      }
      final merged = mergedByKey.values.toList(growable: false);
      record = await store.update(
        note.id,
        bodyMarkdown: body,
        anchors: merged,
        expectedRevision: note.revision,
      );
      if (selectedCollectionId != null) {
        await store.addNoteToCollection(note.id, selectedCollectionId!);
      }
    } else {
      record = await store.create(
        title: defaultNoteTitle(
          label: label,
          anchors: anchors,
          quote: anchorOnly ? '' : text,
        ),
        bodyMarkdown: quote,
        anchors: anchors,
        collectionIds: selectedCollectionId == null
            ? const <String>[]
            : <String>[selectedCollectionId!],
      );
    }
    if (const bool.fromEnvironment('PDG_REVIEW_TRACE')) {
      debugPrint(
        'NOTE capture existing=${choice.existing?.id} saved=${record.id} '
        'bodyLen=${record.bodyMarkdown.length} rev=${record.revision} '
        'anchors=${record.anchors.length}',
      );
    }
    NoteCaptureDefaults.lastCollectionId = selectedCollectionId;
    scope.notesChanges.value++;
  } catch (error) {
    if (!dialogContext.mounted) return;
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: Text(
          '${strings.notesSaveFailed}: ${errorText(error, strings)}',
        ),
      ),
    );
    return;
  }
  if (!dialogContext.mounted) return;
  if (choice.openAfterSave) {
    await AppNav.push<void>(dialogContext, NoteEditorPage(note: record));
  } else {
    ScaffoldMessenger.of(dialogContext)
        .showSnackBar(SnackBar(content: Text(strings.notesCaptured)));
  }
}

/// Adds an entity link to a note, letting the user append to an existing note
/// or create a new one instead of silently creating a note.
Future<void> addEntityToNote(
  BuildContext context, {
  required List<NoteAnchorInput> anchors,
  required String label,
  List<NoteTarget> lookupTargets = const <NoteTarget>[],
}) => captureTextToNote(
  context,
  text: '',
  anchors: anchors,
  label: label,
  anchorOnly: true,
  lookupTargets: lookupTargets,
);

class _CaptureChoice {
  const _CaptureChoice({this.existing, this.openAfterSave = false});

  final NoteRecord? existing;
  final bool openAfterSave;
}
