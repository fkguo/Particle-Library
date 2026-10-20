import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../notes/notes.dart';
import '../../notes/note_evidence.dart';
import '../common/async_view.dart';
import '../common/export_file.dart';
import '../common/resize_handle.dart';
import '../common/snack_bars.dart';
import '../common/ui.dart';
import '../../app/navigation.dart';
import 'evidence_view.dart';
import 'note_editor.dart';
import 'notes_entity.dart';
import 'notes_format.dart';
import 'tag_tools.dart';
import 'note_evidence_resolver.dart';

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
      evidenceResolver: PdgEvidenceResolver(scope.database),
      currentEdition: scope.database.currentEdition,
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
    this.evidenceResolver,
    this.currentEdition = '',
  });

  final NotesStore? store;
  final Object? storeError;
  final AppStrings strings;
  final ValueNotifier<int> changes;
  final double wideBreakpoint;
  final ValueNotifier<int>? newNoteRequests;
  final NoteEvidenceResolver? evidenceResolver;
  final String currentEdition;

  @override
  State<NotesWorkspace> createState() => _NotesWorkspaceState();
}

class _NotesWorkspaceState extends State<NotesWorkspace> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<NoteRecord> _notes = const <NoteRecord>[];
  List<NoteCollection> _collections = const <NoteCollection>[];
  List<NoteCollectionSummary> _collectionSummaries =
      const <NoteCollectionSummary>[];
  String? _collectionFilter;
  bool _unfiledScope = false;
  bool _showEvidence = false;
  List<NoteEvidenceRow> _evidenceRows = const <NoteEvidenceRow>[];
  bool _evidenceLoading = false;
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
      final summaries = await store.collectionSummaries();
      final collections = [for (final summary in summaries) summary.collection];
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
          ? (_unfiledScope
                ? await store.unfiled(limit: _pageSize)
                : _collectionFilter == null
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
      if (_unfiledScope) {
        notes = notes
            .where((note) => note.collections.isEmpty)
            .toList(growable: false);
      }
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
        _collectionSummaries = summaries;
        _tagCounts = tagCounts;
        _loading = false;
        _error = null;
        if (selectedGone) {
          _selected = null;
          _editorSession++;
        }
      });
      if (_showEvidence) unawaited(_reloadEvidence());
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _reloadEvidence() async {
    final store = widget.store;
    if (store == null) return;
    if (!mounted) return;
    setState(() => _evidenceLoading = true);
    try {
      final notes = _searchController.text.trim().isEmpty && _tagFilters.isEmpty
          ? (_unfiledScope
                ? await store.unfiled(limit: 200)
                : _collectionFilter == null
                ? await store.recent(limit: 200)
                : await store.notesInCollection(_collectionFilter!, limit: 200))
          : _notes;
      final rows = await buildNoteEvidence(
        notes,
        resolver: widget.evidenceResolver,
        currentEdition: widget.currentEdition,
      );
      if (!mounted) return;
      setState(() {
        _evidenceRows = rows;
        _evidenceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _evidenceRows = const <NoteEvidenceRow>[];
        _evidenceLoading = false;
      });
    }
  }

  void _selectAllScope() {
    setState(() {
      _collectionFilter = null;
      _unfiledScope = false;
      _pageSize = 50;
      _showEvidence = false;
    });
    _reload(showLoading: true);
  }

  void _selectUnfiledScope() {
    setState(() {
      _collectionFilter = null;
      _unfiledScope = true;
      _pageSize = 50;
      _showEvidence = false;
    });
    _reload(showLoading: true);
  }

  void _selectCollectionScope(NoteCollection collection) {
    setState(() {
      _collectionFilter = collection.id;
      _unfiledScope = false;
      _pageSize = 50;
      _showEvidence = false;
    });
    _reload(showLoading: true);
  }

  void _setEvidenceMode(bool show) {
    setState(() => _showEvidence = show);
    if (show) unawaited(_reloadEvidence());
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
        await store.addNoteToCollection(note.id, collection.id);
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
                      onChanged: (checked) => setDialogState(() {
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
      final before = {for (final collection in note.collections) collection.id};
      for (final id in result.difference(before)) {
        await store.addNoteToCollection(note.id, id);
      }
      for (final id in before.difference(result)) {
        await store.removeNoteFromCollection(note.id, id);
      }
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
        bytes: utf8.encode(
          notesExportJson(notes, collections: await store.collections()),
        ),
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
      final collections = await store.collections();
      if (!mounted) return;
      await copyText(
        context,
        notesExportJson(notes, collections: collections),
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
        final showRail = constraints.maxWidth >= 1280;
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
                  ? (showRail
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _collectionRail(context),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _viewBar(context),
                                    Expanded(
                                      child: _wideContent(
                                        context,
                                        constraints,
                                        hasRail: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _viewBar(context),
                              Expanded(
                                child: _showEvidence
                                    ? _evidencePane(context)
                                    : _wideContent(
                                        context,
                                        constraints,
                                        hasRail: false,
                                      ),
                              ),
                            ],
                          ))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _viewBar(context),
                        Expanded(
                          child: _showEvidence
                              ? _evidencePane(context)
                              : _listPane(context, wide: false),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _wideContent(
    BuildContext context,
    BoxConstraints constraints, {
    required bool hasRail,
  }) {
    if (_showEvidence) return _evidencePane(context);
    final maxListWidth = (constraints.maxWidth - (hasRail ? 208 : 0) - 360)
        .clamp(300.0, 520.0);
    final width = _listWidth.clamp(260.0, maxListWidth).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollapsibleSidebar(
          expanded: _listVisible,
          width: width,
          tooltip: '拖动调整笔记列表宽度；拉到最窄可隐藏，双击恢复默认',
          railIcon: Icons.sticky_note_2_outlined,
          railTooltip: widget.strings.sidebarShow,
          onExpand: () => setState(() => _listVisible = true),
          onDrag: (delta) {
            final next = (width + delta).clamp(260.0, maxListWidth).toDouble();
            if (delta < 0 && next <= 262) {
              setState(() => _listVisible = false);
              return;
            }
            setState(() => _listWidth = next);
          },
          onReset: () => setState(() => _listWidth = 370),
          child: _listPane(context, wide: true),
        ),
        Expanded(child: _editorPane(context)),
      ],
    );
  }

  String get _scopeLabel {
    if (_unfiledScope) return widget.strings.notesUnfiled;
    final id = _collectionFilter;
    if (id == null) return widget.strings.notesAllCollections;
    for (final summary in _collectionSummaries) {
      if (summary.id == id) return summary.name;
    }
    return widget.strings.notesAllCollections;
  }

  Widget _viewBar(BuildContext context) {
    final strings = widget.strings;
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width < 1280)
            OutlinedButton.icon(
              onPressed: () => _showScopePicker(context),
              icon: const Icon(Icons.folder_outlined, size: 17),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  _scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            Text(
              _scopeLabel,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          const Spacer(),
          ChoiceChip(
            label: Text(strings.notesNotesView),
            selected: !_showEvidence,
            onSelected: (_) => _setEvidenceMode(false),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(strings.notesEvidence),
            selected: _showEvidence,
            onSelected: (_) => _setEvidenceMode(true),
          ),
        ],
      ),
    );
  }

  Future<void> _showScopePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(widget.strings.notesAllCollections),
              selected: !_unfiledScope && _collectionFilter == null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _selectAllScope();
              },
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text(widget.strings.notesUnfiled),
              selected: _unfiledScope,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _selectUnfiledScope();
              },
            ),
            const Divider(height: 1),
            for (final summary in _collectionSummaries)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(summary.name),
                trailing: Text('${summary.activeNoteCount}'),
                selected: _collectionFilter == summary.id,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _selectCollectionScope(summary.collection);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(widget.strings.notesNewCollection),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _createCollection();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune, size: 19),
              title: Text(widget.strings.notesManageCollections),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _manageCollections();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectionRail(BuildContext context) {
    final strings = widget.strings;
    final palette = context.palette;
    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        border: Border(right: BorderSide(color: palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strings.notesCollections,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.notesNewCollection,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _createCollection(),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                ),
                IconButton(
                  tooltip: strings.notesManageCollections,
                  visualDensity: VisualDensity.compact,
                  onPressed: _manageCollections,
                  icon: const Icon(Icons.tune, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Insets.l),
              children: [
                _railTile(
                  context,
                  icon: Icons.sticky_note_2_outlined,
                  label: strings.notesAllCollections,
                  selected: !_unfiledScope && _collectionFilter == null,
                  onTap: _selectAllScope,
                ),
                _railTile(
                  context,
                  icon: Icons.inbox_outlined,
                  label: strings.notesUnfiled,
                  selected: _unfiledScope,
                  onTap: _selectUnfiledScope,
                ),
                const Divider(height: 1),
                for (final summary in _collectionSummaries)
                  _railTile(
                    context,
                    icon: Icons.folder_outlined,
                    label: summary.name,
                    trailing: '${summary.activeNoteCount}',
                    selected: _collectionFilter == summary.id,
                    onTap: () => _selectCollectionScope(summary.collection),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? trailing,
  }) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: selected ? palette.primary.withValues(alpha: 0.09) : null,
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? palette.primary : palette.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? palette.primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: palette.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _evidencePane(BuildContext context) {
    if (_evidenceLoading) {
      return const Center(child: LoadingPanel(compact: true));
    }
    return NotesEvidenceView(
      rows: _evidenceRows,
      strings: widget.strings,
      onOpenRow: _openEvidenceRow,
      onOpenNote: _openNoteById,
      onExport: _evidenceRows.isEmpty ? null : _exportEvidenceCsv,
    );
  }

  Future<void> _openNoteById(String id) async {
    final store = widget.store;
    if (store == null) return;
    final note = await store.noteById(id);
    if (note == null || !mounted) return;
    final wide = MediaQuery.sizeOf(context).width >= widget.wideBreakpoint;
    _setEvidenceMode(false);
    _select(note, wide: wide);
  }

  Future<void> _openEvidenceRow(NoteEvidenceRow row) async {
    switch (row.type) {
      case NoteEvidenceType.measurement:
        final target = row.sourceTargetId;
        if (target.startsWith('measurement:')) {
          final key = target.substring('measurement:'.length);
          final split = key.lastIndexOf(':');
          if (split > 0) {
            final pdgid = key.substring(0, split);
            final measurementId = int.tryParse(key.substring(split + 1));
            if (measurementId != null) {
              await AppNav.openMeasurement(
                context,
                pdgid: pdgid,
                measurementId: measurementId,
              );
              return;
            }
          }
        }
        if (row.noteIds.isNotEmpty) await _openNoteById(row.noteIds.first);
      case NoteEvidenceType.pdgSummary:
        final target = row.sourceTargetId;
        if (target.startsWith('pdgid:')) {
          await AppNav.openPdgid(context, target.substring(6));
        }
      case NoteEvidenceType.reference:
        if (row.noteIds.isNotEmpty) await _openNoteById(row.noteIds.first);
    }
  }

  Future<void> _exportEvidenceCsv() async {
    final strings = widget.strings;
    if (_evidenceRows.isEmpty) return;
    final buffer = StringBuffer()
      ..writeln(
        'row_type,title,captured_value,captured_edition,current_value,current_edition,status,note_count',
      );
    for (final row in _evidenceRows) {
      buffer.writeln(
        [
          _csv(row.type.name),
          _csv(row.title),
          _csv(row.capturedValue == '—' ? '' : row.capturedValue),
          _csv(row.captured?.edition ?? ''),
          _csv(row.currentValue == '—' ? '' : row.currentValue),
          _csv(row.current?.edition ?? ''),
          _csv(row.status.name),
          '${row.noteCount}',
        ].join(','),
      );
    }
    try {
      final exported = await saveOrShareBytes(
        suggestedName:
            'ParticleLibrary-evidence-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        bytes: utf8.encode(buffer.toString()),
        type: const XTypeGroup(label: 'CSV', extensions: ['csv']),
        mimeType: 'text/csv',
      );
      if (!exported || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.notesExportCsvDone)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.notesExportFileFailed}: $error')),
      );
    }
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _manageCollections() async {
    final store = widget.store;
    if (store == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.notesManageCollections),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: _collectionSummaries.isEmpty
                ? Text(widget.strings.notesNoCollections)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final summary in _collectionSummaries)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.folder_outlined, size: 19),
                          title: Text(summary.name),
                          subtitle: Text(
                            '${summary.activeNoteCount} ${widget.strings.notesCollectionNoteCount}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: widget.strings.notesRenameCollection,
                                onPressed: () async {
                                  await _renameCollection(summary.collection);
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  if (mounted) await _manageCollections();
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                tooltip: widget.strings.notesDeleteCollection,
                                onPressed: () async {
                                  await _deleteCollection(summary.collection);
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  if (mounted) await _manageCollections();
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                            ],
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

  Future<void> _renameCollection(NoteCollection collection) async {
    final store = widget.store;
    if (store == null) return;
    final controller = TextEditingController(text: collection.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.notesRenameCollection),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(widget.strings.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await store.renameCollection(collection.id, name);
      await _reload(showLoading: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.strings.notesCollectionFailed}: $error'),
        ),
      );
    }
  }

  Future<void> _deleteCollection(NoteCollection collection) async {
    final store = widget.store;
    if (store == null) return;
    final summary = _collectionSummaries.where((s) => s.id == collection.id);
    final count = summary.isEmpty ? 0 : summary.first.activeNoteCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.notesDeleteCollection),
        content: Text(
          '${widget.strings.notesDeleteCollectionBody}\n'
          '${collection.name} · $count ${widget.strings.notesCollectionNoteCount}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.deleteCollection(collection.id);
      if (_collectionFilter == collection.id) _collectionFilter = null;
      await _reload(showLoading: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.strings.notesCollectionFailed}: $error'),
        ),
      );
    }
  }

  Widget _listPane(BuildContext context, {required bool wide}) {
    final strings = widget.strings;
    final searching = _searchController.text.trim().isNotEmpty;
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
                      fontFamily: 'Menlo',
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
