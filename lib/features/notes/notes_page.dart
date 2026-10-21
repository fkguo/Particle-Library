import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../notes/notes.dart';
import '../common/async_view.dart';
import '../common/export_file.dart';
import '../common/resize_handle.dart';
import '../common/snack_bars.dart';
import '../common/ui.dart';
import 'note_editor.dart';
import 'notes_entity.dart';
import 'notes_format.dart';
import 'tag_tools.dart';

/// Fourth primary destination: local notes.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return NotesWorkspace(
      store: scope.notes,
      storeError: scope.notesError,
      strings: scope.strings,
      changes: scope.notesChanges,
      newNoteRequests: scope.noteRequests,
    );
  }
}

/// The Notes page without an AppScope dependency, so it can be widget-tested
/// with a real temporary notes database.
class NotesWorkspace extends StatefulWidget {
  const NotesWorkspace({
    super.key,
    required this.store,
    required this.storeError,
    required this.strings,
    required this.changes,
    this.wideBreakpoint = 900,
    this.newNoteRequests,
  });

  final NotesStore? store;
  final Object? storeError;
  final AppStrings strings;
  final ValueNotifier<int> changes;
  final double wideBreakpoint;
  final ValueNotifier<int>? newNoteRequests;

  @override
  State<NotesWorkspace> createState() => _NotesWorkspaceState();
}

class _NotesWorkspaceState extends State<NotesWorkspace> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<NoteRecord> _notes = const <NoteRecord>[];
  List<NoteCollection> _collections = const <NoteCollection>[];
  String? _collectionFilter;
  bool _loading = true;
  Object? _error;
  int _generation = 0;
  int _pageSize = 50;
  double _listWidth = 370;
  bool _listVisible = true;
  final Set<String> _tagFilters = <String>{};
  Map<String, int> _tagCounts = const <String, int>{};
  NoteRecord? _selected;
  bool _draftActive = false;
  int _editorSession = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.changes.addListener(_onNotesChanged);
    widget.newNoteRequests?.addListener(_onNewNoteRequested);
    _reload();
  }

  @override
  void didUpdateWidget(covariant NotesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes)) {
      oldWidget.changes.removeListener(_onNotesChanged);
      widget.changes.addListener(_onNotesChanged);
    }
    if (!identical(oldWidget.newNoteRequests, widget.newNoteRequests)) {
      oldWidget.newNoteRequests?.removeListener(_onNewNoteRequested);
      widget.newNoteRequests?.addListener(_onNewNoteRequested);
    }
    if (!identical(oldWidget.store, widget.store)) {
      _selected = null;
      _draftActive = false;
      _editorSession++;
      _reload(showLoading: true);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    widget.changes.removeListener(_onNotesChanged);
    widget.newNoteRequests?.removeListener(_onNewNoteRequested);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    if (mounted) setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _reload(showLoading: true);
    });
  }

  void _onNotesChanged() {
    if (!mounted) return;
    _reload();
  }

  void _onNewNoteRequested() {
    if (!mounted) return;
    _newNote(wide: MediaQuery.sizeOf(context).width >= widget.wideBreakpoint);
  }

  Future<void> _reload({bool showLoading = false}) async {
    final store = widget.store;
    final generation = ++_generation;
    if (store == null) {
      if (!mounted) return;
      setState(() {
        _notes = const <NoteRecord>[];
        _collections = const <NoteCollection>[];
        _tagCounts = const <String, int>{};
        _loading = false;
        _error = null;
      });
      return;
    }
    if (showLoading && mounted) setState(() => _loading = true);
    final query = _searchController.text.trim();
    try {
      final collections = await store.collections();
      final tagCounts = await store.tagCounts(limit: 30);
      if (_collectionFilter != null &&
          !collections.any((c) => c.id == _collectionFilter)) {
        _collectionFilter = null;
      }
      var notes = _tagFilters.isNotEmpty
          ? await store.notesByTags(
              _tagFilters,
              collectionId: _collectionFilter,
              limit: _pageSize,
            )
          : query.isEmpty
          ? (_collectionFilter == null
                ? await store.recent(limit: _pageSize)
                : await store.notesInCollection(
                    _collectionFilter!,
                    limit: _pageSize,
                  ))
          : await store.search(
              query,
              limit: _pageSize,
              collectionId: _collectionFilter,
            );
      if (_tagFilters.isNotEmpty && query.isNotEmpty) {
        notes = notes
            .where((note) => noteMatchesQuery(note, query))
            .toList(growable: false);
      }
      if (!mounted || generation != _generation) return;
      final selectedId = _selected?.id;
      final selectedGone =
          selectedId != null &&
          !_draftActive &&
          !notes.any((note) => note.id == selectedId);
      setState(() {
        _notes = notes;
        _collections = collections;
        _tagCounts = tagCounts;
        _loading = false;
        _error = null;
        if (selectedGone) {
          _selected = null;
          _editorSession++;
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _newNote({required bool wide}) {
    final initialCollections = _collectionFilter == null
        ? const <String>[]
        : <String>[_collectionFilter!];
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    } else {
      unawaited(_reload(showLoading: true));
    }
    if (!wide) {
      unawaited(
        openNoteComposer(
          context,
          anchors: const <NoteAnchorInput>[],
          initialCollectionIds: initialCollections,
        ),
      );
      return;
    }
    setState(() {
      _draftActive = true;
      _selected = null;
      _editorSession++;
    });
  }

  void _select(NoteRecord note, {required bool wide}) {
    if (!wide) {
      unawaited(openNoteEditor(context, note));
      return;
    }
    setState(() {
      _selected = note;
      _draftActive = false;
      _editorSession++;
    });
  }

  void _onDraftSaved(NoteRecord saved) {
    if (!mounted) return;
    setState(() {
      _selected = saved;
      _draftActive = false;
    });
  }

  void _onDeleted() {
    if (!mounted) return;
    setState(() {
      _selected = null;
      _draftActive = false;
      _editorSession++;
    });
  }

  Future<bool> _confirmNoteDelete(NoteRecord note) async {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.notesDeleteConfirmTitle),
        content: Text(
          '${strings.notesDeleteConfirmBody}\n\n${noteDisplayTitle(note, strings)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.notesDeleteConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteNoteFromList(NoteRecord note) async {
    final store = widget.store;
    if (store == null) return;
    final strings = AppScope.of(context).strings;
    final messenger = ScaffoldMessenger.of(context);
    await store.delete(note.id);
    if (!mounted) return;
    widget.changes.value++;
    if (_selected?.id == note.id) {
      _onDeleted();
    }
    await _reload();
    showUndoSnackBar(
      messenger,
      message: strings.notesDeleted,
      undoLabel: strings.notesUndo,
      onUndo: () async {
        await store.restore(note.id);
        widget.changes.value++;
        await _reload();
      },
    );
  }

  void _filterByTag(String tag) {
    setState(() {
      if (_tagFilters.contains(tag)) {
        _tagFilters.remove(tag);
      } else {
        _tagFilters.add(tag);
      }
      _pageSize = 50;
    });
    _reload(showLoading: true);
  }

  Future<void> _openTagManager() async {
    final store = widget.store;
    if (store == null) return;
    await showTagManager(
      context,
      store: store,
      strings: widget.strings,
      onChanged: () async {
        if (!mounted) return;
        final counts = await store.tagCounts(limit: 1000);
        if (!mounted) return;
        AppScope.of(context).notesChanges.value++;
        setState(() {
          _tagCounts = counts;
          _tagFilters.removeWhere((tag) => !counts.containsKey(tag));
        });
        await _reload(showLoading: false);
      },
    );
  }

  void _filterByCollection(NoteCollection collection) {
    _pageSize = 50;
    setState(() => _collectionFilter = collection.id);
    _reload(showLoading: true);
  }

  Future<void> _addToCollection(NoteRecord note) async {
    final store = widget.store;
    if (store == null) return;
    if (_collections.isEmpty) {
      final collection = await _createCollection(selectFilter: false);
      if (collection == null || !mounted) return;
      try {
        await store.setNoteCollections(note.id, [collection.id]);
        await _reload();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.strings.notesCollectionFailed}: $error'),
          ),
        );
      }
      return;
    }
    final selected = {for (final collection in note.collections) collection.id};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.strings.notesAddToCollection),
          content: SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final collection in _collections)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(collection.id),
                      title: Text(collection.name),
                      subtitle:
                          note.collections.any(
                            (member) => member.id == collection.id,
                          )
                          ? Text(widget.strings.notesAlreadyInCollection)
                          : null,
                      onChanged:
                          note.collections.any(
                            (member) => member.id == collection.id,
                          )
                          ? null
                          : (checked) => setDialogState(() {
                              if (checked ?? false) {
                                selected.add(collection.id);
                              } else {
                                selected.remove(collection.id);
                              }
                            }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.strings.commonCancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(Set<String>.of(selected)),
              child: Text(widget.strings.commonSave),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await store.setNoteCollections(note.id, result);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.strings.notesCollectionFailed}: $error'),
        ),
      );
    }
  }

  Future<NoteCollection?> _createCollection({bool selectFilter = true}) async {
    final store = widget.store;
    if (store == null) return null;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.notesNewCollection),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.strings.notesCollectionName,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(widget.strings.commonCreate),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return null;
    try {
      final collection = await store.createCollection(name);
      if (!mounted) return collection;
      if (selectFilter) setState(() => _collectionFilter = collection.id);
      await _reload();
      return collection;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.strings.notesCollectionFailed}: $error'),
        ),
      );
      return null;
    }
  }

  Future<void> _openTrash() async {
    final store = widget.store;
    if (store == null) return;
    List<NoteRecord> deleted;
    try {
      deleted = await store.deleted();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.strings.notesLoadFailed}: $error')),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.notesTrash),
        content: SizedBox(
          width: 480,
          child: deleted.isEmpty
              ? Text(widget.strings.notesTrashEmpty)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final note in deleted)
                        ListTile(
                          dense: true,
                          title: Text(
                            noteDisplayTitle(note, widget.strings),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            note.updatedAt.toLocal().toString(),
                            maxLines: 1,
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await store.restore(note.id);
                                widget.changes.value++;
                                if (!mounted || !dialogContext.mounted) {
                                  return;
                                }
                                Navigator.of(dialogContext).pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(widget.strings.notesRestored),
                                  ),
                                );
                                await _reload();
                              } catch (error) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${widget.strings.notesSaveFailed}: $error',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(widget.strings.notesRestore),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(widget.strings.commonClose),
          ),
        ],
      ),
    );
  }

  Future<XTypeGroup> _jsonType() async => const XTypeGroup(
    label: 'Particle Library notes',
    extensions: <String>['json'],
  );

  Future<void> _exportJsonFile() async {
    final store = widget.store;
    if (store == null) return;
    final strings = widget.strings;
    try {
      final notes = await store.allForExport();
      if (notes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(strings.notesExportEmpty)));
        }
        return;
      }
      final exported = await saveOrShareBytes(
        suggestedName:
            'ParticleLibrary-notes-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        bytes: utf8.encode(notesExportJson(notes)),
        type: await _jsonType(),
        mimeType: 'application/json',
      );
      if (!exported || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.notesExportFileDone)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.notesExportFileFailed}: $error')),
      );
    }
  }

  Future<void> _exportMarkdownFile() async {
    final store = widget.store;
    if (store == null) return;
    final strings = widget.strings;
    try {
      final notes = await store.allForExport();
      if (notes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(strings.notesExportEmpty)));
        }
        return;
      }
      final buffer = StringBuffer()
        ..writeln('# Particle Library notes')
        ..writeln()
        ..writeln('Exported: ${DateTime.now().toUtc().toIso8601String()}')
        ..writeln();
      for (final note in notes) {
        buffer
          ..writeln('---')
          ..writeln()
          ..writeln(noteAsMarkdown(note, untitled: strings.notesUntitled))
          ..writeln();
      }
      final exported = await saveOrShareBytes(
        suggestedName:
            'ParticleLibrary-notes-${DateTime.now().toIso8601String().substring(0, 10)}.md',
        bytes: utf8.encode(buffer.toString()),
        type: const XTypeGroup(label: 'Markdown', extensions: ['md']),
        mimeType: 'text/markdown',
      );
      if (!exported || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.notesExportFileDone)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.notesExportFileFailed}: $error')),
      );
    }
  }

  Future<void> _importJsonFile() async {
    final store = widget.store;
    if (store == null) return;
    final strings = widget.strings;
    try {
      final file = await openFile(acceptedTypeGroups: [await _jsonType()]);
      if (file == null) return;
      final decoded = jsonDecode(await file.readAsString());
      final result = await store.importJson(decoded);
      widget.changes.value++;
      await _reload(showLoading: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.notesImportDone}: '
            '${strings.notesImportSummary(result.added, result.skipped, result.failed)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.notesImportFailed}: $error')),
      );
    }
  }

  Future<void> _exportAll() async {
    final store = widget.store;
    if (store == null) return;
    final strings = widget.strings;
    try {
      final notes = await store.allForExport();
      if (!mounted) return;
      if (notes.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.notesExportEmpty)));
        return;
      }
      await copyText(
        context,
        notesExportJson(notes),
        message: strings.notesExportAllDone,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.notesLoadFailed}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final palette = context.palette;
    if (widget.store == null) return _unavailable(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= widget.wideBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.l,
                Insets.l,
                Insets.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.notesTitle,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                        ),
                        Text(
                          strings.notesLocalOnly,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Insets.s),
                  Wrap(
                    spacing: Insets.s,
                    runSpacing: Insets.s,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (wide)
                        IconButton(
                          tooltip: _listVisible
                              ? strings.sidebarHide
                              : strings.sidebarShow,
                          onPressed: () =>
                              setState(() => _listVisible = !_listVisible),
                          icon: Icon(
                            _listVisible
                                ? Icons.vertical_split
                                : Icons.vertical_split_outlined,
                            size: 20,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: () => _newNote(wide: wide),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(strings.notesNew),
                      ),
                      IconButton(
                        tooltip: strings.notesTagsManage,
                        onPressed: _openTagManager,
                        icon: const Icon(Icons.sell_outlined, size: 20),
                      ),
                      IconButton(
                        tooltip: strings.notesTrash,
                        onPressed: _openTrash,
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                      PopupMenuButton<String>(
                        tooltip: strings.notesExportAll,
                        icon: const Icon(Icons.import_export, size: 20),
                        onSelected: (value) {
                          switch (value) {
                            case 'json':
                              _exportJsonFile();
                            case 'markdown':
                              _exportMarkdownFile();
                            case 'import':
                              _importJsonFile();
                            case 'copy':
                              _exportAll();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'json',
                            child: Text(strings.notesExportJsonFile),
                          ),
                          PopupMenuItem(
                            value: 'markdown',
                            child: Text(strings.notesExportMarkdownFile),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'import',
                            child: Text(strings.notesImportJsonFile),
                          ),
                          PopupMenuItem(
                            value: 'copy',
                            child: Text(strings.notesExportAll),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: wide
                  ? Builder(
                      builder: (context) {
                        final maxListWidth = (constraints.maxWidth - 360).clamp(
                          300.0,
                          520.0,
                        );
                        final width = _listWidth
                            .clamp(260.0, maxListWidth)
                            .toDouble();
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CollapsibleSidebar(
                              expanded: _listVisible,
                              width: width,
                              tooltip: '拖动调整笔记列表宽度；拉到最窄可隐藏，双击恢复默认',
                              railIcon: Icons.sticky_note_2_outlined,
                              railTooltip: widget.strings.sidebarShow,
                              onExpand: () =>
                                  setState(() => _listVisible = true),
                              onDrag: (delta) {
                                final next = (width + delta)
                                    .clamp(260.0, maxListWidth)
                                    .toDouble();
                                if (delta < 0 && next <= 262) {
                                  setState(() => _listVisible = false);
                                  return;
                                }
                                setState(() => _listWidth = next);
                              },
                              onReset: () {
                                setState(() => _listWidth = 370);
                              },
                              child: _listPane(context, wide: true),
                            ),
                            Expanded(child: _editorPane(context)),
                          ],
                        );
                      },
                    )
                  : _listPane(context, wide: false),
            ),
          ],
        );
      },
    );
  }

  Widget _listPane(BuildContext context, {required bool wide}) {
    final strings = widget.strings;
    final searching = _searchController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(strings.notesAllCollections),
                        selected: _collectionFilter == null,
                        onSelected: (_) {
                          setState(() => _collectionFilter = null);
                          _reload(showLoading: true);
                        },
                      ),
                      for (final collection in _collections) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(collection.name),
                          selected: _collectionFilter == collection.id,
                          onSelected: (_) {
                            setState(() => _collectionFilter = collection.id);
                            _reload(showLoading: true);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.notesNewCollection,
                icon: const Icon(Icons.create_new_folder_outlined, size: 19),
                onPressed: () => _createCollection(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.s,
            Insets.l,
            Insets.s,
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: strings.notesSearchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: strings.notesSearchClear,
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close, size: 16),
                    ),
              isDense: true,
            ),
          ),
        ),
        if (_tagCounts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.l,
              0,
              Insets.l,
              Insets.xs,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in _tagCounts.entries.take(10)) ...[
                    FilterChip(
                      label: Text('${entry.key} ${entry.value}'),
                      selected: _tagFilters.contains(entry.key),
                      onSelected: (_) {
                        setState(() {
                          if (_tagFilters.contains(entry.key)) {
                            _tagFilters.remove(entry.key);
                          } else {
                            _tagFilters.add(entry.key);
                          }
                          _pageSize = 50;
                        });
                        _reload(showLoading: true);
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (_tagFilters.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _tagFilters.clear();
                          _pageSize = 50;
                        });
                        _reload(showLoading: true);
                      },
                      child: Text(strings.commonClear),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _listBody(
            context,
            wide: wide,
            searching: searching || _tagFilters.isNotEmpty,
          ),
        ),
      ],
    );
  }

  Widget _listBody(
    BuildContext context, {
    required bool wide,
    required bool searching,
  }) {
    final strings = widget.strings;
    final palette = context.palette;
    if (_loading) {
      return const Center(child: LoadingPanel(compact: true));
    }
    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.l),
        child: ErrorPanel(
          error: _error!,
          compact: true,
          onRetry: () => _reload(showLoading: true),
        ),
      );
    }
    if (_notes.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Insets.l),
        child: EmptyPanel(
          message: searching
              ? strings.notesNoSearchResults
              : strings.notesEmpty,
          icon: searching ? Icons.search_off : Icons.sticky_note_2_outlined,
          action: searching
              ? null
              : FilledButton.icon(
                  onPressed: () => _newNote(wide: wide),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(strings.notesNew),
                ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.l,
              Insets.xs,
              Insets.l,
              Insets.xs,
            ),
            child: Text(
              strings.notesRecent,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: Insets.l),
            itemCount: _notes.length + (_notes.length >= _pageSize ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _notes.length) {
                return Padding(
                  padding: const EdgeInsets.all(Insets.l),
                  child: Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _pageSize += 50;
                        _reload(showLoading: true);
                      }),
                      child: Text(strings.notesLoadMore),
                    ),
                  ),
                );
              }
              final note = _notes[index];
              return Dismissible(
                key: ValueKey<String>('note-swipe-${note.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmNoteDelete(note),
                onDismissed: (_) => _deleteNoteFromList(note),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: Insets.l),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                child: _NoteListTile(
                  note: note,
                  strings: strings,
                  selected: wide && !_draftActive && _selected?.id == note.id,
                  onTap: () => _select(note, wide: wide),
                  onAddToCollection: () => _addToCollection(note),
                  onCollectionTap: _filterByCollection,
                  onTagTap: _filterByTag,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _editorPane(BuildContext context) {
    final store = widget.store;
    final strings = widget.strings;
    if (store == null) return const SizedBox.shrink();
    if (_draftActive) {
      return NoteEditor(
        key: ValueKey<String>('notes-editor-$_editorSession'),
        store: store,
        strings: strings,
        changeSignal: widget.changes,
        initialCollectionIds: _collectionFilter == null
            ? const <String>[]
            : <String>[_collectionFilter!],
        autofocusTitle: true,
        onSaved: _onDraftSaved,
      );
    }
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EmptyPanel(
            message: strings.notesSelectPrompt,
            icon: Icons.sticky_note_2_outlined,
            action: FilledButton.icon(
              onPressed: () => _newNote(wide: true),
              icon: const Icon(Icons.add, size: 18),
              label: Text(strings.notesNew),
            ),
          ),
        ),
      );
    }
    return NoteEditor(
      key: ValueKey<String>('notes-editor-$_editorSession'),
      store: store,
      strings: strings,
      note: selected,
      changeSignal: widget.changes,
      onDeleted: _onDeleted,
    );
  }

  Widget _unavailable(BuildContext context) {
    final strings = widget.strings;
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.only(bottom: Insets.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.l,
            Insets.l,
            Insets.s,
          ),
          child: Text(
            strings.notesTitle,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.l),
          child: Container(
            padding: const EdgeInsets.all(Insets.l),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.speaker_notes_off_outlined,
                      size: 20,
                      color: palette.warning,
                    ),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: Text(
                        strings.notesUnavailable,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.s),
                Text(
                  strings.notesUnavailableHint,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
                if (widget.storeError != null) ...[
                  const SizedBox(height: Insets.s),
                  SelectableText(
                    '${widget.storeError}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      fontFamily: AppFonts.monospaceFamily,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.strings,
    required this.selected,
    required this.onTap,
    required this.onAddToCollection,
    required this.onCollectionTap,
    required this.onTagTap,
  });

  final NoteRecord note;
  final AppStrings strings;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAddToCollection;
  final ValueChanged<NoteCollection> onCollectionTap;
  final ValueChanged<String> onTagTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final anchorPreview = noteAnchorPreview(note);
    final preview = noteBodyPreview(note);
    return Material(
      color: selected
          ? palette.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Insets.l, 10, Insets.l, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? palette.primary : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: palette.divider),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      noteDisplayTitle(note, strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip:
                        '${strings.notesAddToCollection}: ${noteDisplayTitle(note, strings)}',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: onAddToCollection,
                    icon: const Icon(Icons.playlist_add),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    noteUpdatedLabel(note.updatedAt, strings),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              if (anchorPreview.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.link, size: 13, color: palette.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        anchorPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ],
              if (note.collections.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    for (final collection in note.collections.take(3))
                      MetaChip(
                        '▸ ${collection.name}',
                        onTap: () => onCollectionTap(collection),
                      ),
                  ],
                ),
              ],
              if (note.tagNames.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    for (final tag in note.tagNames.take(4))
                      MetaChip(tag, onTap: () => onTagTap(tag)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
