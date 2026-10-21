import 'package:flutter/material.dart';

import '../../app/app_strings.dart';
import '../../app/error_text.dart';
import '../../app/app_theme.dart';
import '../../notes/notes.dart';
import 'notes_format.dart';

/// All-tag overview with rename/delete actions. Tag edits affect every note,
/// so they run through [NotesStore.renameTag]/[NotesStore.deleteTag] rather
/// than rewriting notes one by one in the UI.
Future<void> showTagManager(
  BuildContext context, {
  required NotesStore store,
  required AppStrings strings,
  required Future<void> Function() onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _TagManagerDialog(store: store, strings: strings, onChanged: onChanged),
  );
}

class _TagManagerDialog extends StatefulWidget {
  const _TagManagerDialog({
    required this.store,
    required this.strings,
    required this.onChanged,
  });

  final NotesStore store;
  final AppStrings strings;
  final Future<void> Function() onChanged;

  @override
  State<_TagManagerDialog> createState() => _TagManagerDialogState();
}

class _TagManagerDialogState extends State<_TagManagerDialog> {
  late Future<Map<String, int>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.store.tagCounts(limit: 1000);
  }

  void _reload() {
    setState(() => _future = widget.store.tagCounts(limit: 1000));
  }

  Future<void> _rename(String tag) async {
    final controller = TextEditingController(text: tag);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.notesTagsRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.strings.notesTagsHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(widget.strings.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == tag || !mounted) return;
    try {
      final changed = await widget.store.renameTag(tag, next);
      if (!mounted) return;
      _reload();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.notesTagsRenamed(tag, next, changed)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.strings.notesSaveFailed}: ${errorText(error, widget.strings)}',
          ),
        ),
      );
    }
  }

  Future<void> _delete(String tag, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.notesTagsDelete),
        content: Text(widget.strings.notesTagsDeleteConfirm(tag, count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.strings.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.store.deleteTag(tag);
      if (!mounted) return;
      _reload();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.notesTagsDeleted(tag))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.strings.notesSaveFailed}: ${errorText(error, widget.strings)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.strings.notesTagsManage),
      content: SizedBox(
        width: 520,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.strings.notesTagsManagerHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<Map<String, int>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tags = snapshot.data ?? const <String, int>{};
                  if (tags.isEmpty) {
                    return Center(
                      child: Text(
                        widget.strings.notesTagsEmpty,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: tags.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: palette.divider),
                    itemBuilder: (context, index) {
                      final entry = tags.entries.elementAt(index);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.sell_outlined, size: 18),
                        title: Text(entry.key),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${entry.value}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                            IconButton(
                              tooltip: widget.strings.notesTagsRename,
                              onPressed: () => _rename(entry.key),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                            ),
                            IconButton(
                              tooltip: widget.strings.notesTagsDelete,
                              onPressed: () => _delete(entry.key, entry.value),
                              icon: const Icon(Icons.delete_outline, size: 17),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.commonClose),
        ),
      ],
    );
  }
}

/// Shows the notes carrying one tag. [onOpen] lets the caller choose the
/// navigation host (root page, note editor, or detail pane).
Future<void> showNotesForTag(
  BuildContext context, {
  required NotesStore store,
  required AppStrings strings,
  required String tag,
  required ValueChanged<NoteRecord> onOpen,
}) async {
  final notes = await store.notesByTags([tag], limit: 100);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.notesTagsFor(tag)),
      content: SizedBox(
        width: 520,
        height: 420,
        child: notes.isEmpty
            ? Center(
                child: Text(
                  strings.notesTagsNoNotes,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              )
            : ListView.separated(
                itemCount: notes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      noteDisplayTitle(note, strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      noteBodyPreview(note),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      onOpen(note);
                    },
                  );
                },
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
