import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/immersive_page.dart';
import '../../app/app_theme.dart';
import '../../notes/notes.dart';
import '../common/description_text.dart';
import '../common/page.dart';
import '../common/snack_bars.dart';
import '../common/floating_panel.dart';
import '../common/ui.dart';
import 'note_tag_field.dart';
import 'notes_format.dart';
import 'tag_tools.dart';
import '../entry/entry_route_page.dart';
import '../reference/reference_page.dart';
import '../../search/search_service.dart';
import '../../app/navigation.dart';
import 'notes_entity.dart';
import 'note_link_sidebar.dart';
import 'note_link_target.dart';
import 'note_pdg_rail.dart';
import 'notes_markdown_preview.dart';

enum _SaveStage { draft, pending, saving, saved, failed }

/// Shared note editor.
///
/// The same widget is used inline on the wide Notes page and inside
/// [NoteEditorPage] for narrow layouts and entity composers. It autosaves
/// 500 ms after the last text change, never saves on Enter, and postpones a
/// save while a CJK IME composition is still open.
///
/// [note] and [initialAnchors] are initial values only. A parent that needs to
/// switch notes must change the widget key (the Notes page uses an editor
/// session counter), otherwise the in-progress buffer is preserved.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.store,
    required this.strings,
    this.note,
    this.initialAnchors = const <NoteAnchorInput>[],
    this.initialCollectionIds = const <String>[],
    this.changeSignal,
    this.onSaved,
    this.onDeleted,
    this.onCancel,
    this.onCopyCiteKeys,
    this.onCopyBibtex,
    this.draft = false,
    this.autofocusTitle = false,
    this.compact = false,
    this.debounce = const Duration(milliseconds: 500),
  });

  final NotesStore store;
  final AppStrings strings;
  final NoteRecord? note;
  final List<NoteAnchorInput> initialAnchors;
  final List<String> initialCollectionIds;
  final ValueNotifier<int>? changeSignal;
  final ValueChanged<NoteRecord>? onSaved;
  final VoidCallback? onDeleted;
  final VoidCallback? onCancel;
  final Future<void> Function(NoteRecord note)? onCopyCiteKeys;
  final Future<void> Function(NoteRecord note)? onCopyBibtex;
  final bool draft;
  final bool autofocusTitle;

  /// Narrow embedding (the reader's split pane): the PDG rail would take most
  /// of the width, so the lookup opens as a dialog instead.
  final bool compact;
  final Duration debounce;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> with WidgetsBindingObserver {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagController;
  late final FocusNode _titleFocus;
  late final FocusNode _bodyFocus;
  late final FocusNode _tagFocus;
  late final List<NoteAnchorInput> _draftAnchors;

  NoteRecord? _record;
  late List<String> _savedTags;
  late String _savedTitle;
  late String _savedBody;
  late String _lastSignature;
  late _SaveStage _stage;

  Object? _saveError;
  Timer? _autosaveTimer;
  Timer? _linkHoverTimer;
  Timer? _linkHoverHideTimer;
  OverlayEntry? _linkHoverOverlay;
  OverlayEntry? _lookupOverlay;
  int _linkHoverGeneration = 0;
  bool _saving = false;
  bool _disposed = false;
  bool _discarded = false;
  bool _previewOnly = false;
  bool _showPdgRail = true;
  String? _linkPreviewTarget;
  bool _suppressChange = false;
  List<NoteCollection> _collections = const <NoteCollection>[];
  List<String> _knownTags = const <String>[];
  late Set<String> _collectionIds;
  late Set<String> _savedCollectionIds;
  bool _collectionsDirty = false;
  final List<NoteAnchorInput> _quickAnchors = <NoteAnchorInput>[];
  final Set<String> _removedAnchorIds = <String>{};
  late String _savedAnchorSignature;

  @override
  void initState() {
    super.initState();
    _record = widget.note;
    _draftAnchors = List<NoteAnchorInput>.of(widget.initialAnchors);
    _savedTitle = _record?.title ?? '';
    _savedBody = _record?.bodyMarkdown ?? '';
    _savedTags = _record?.tagNames ?? const <String>[];
    _collectionIds = {
      for (final c in _record?.collections ?? const <NoteCollection>[]) c.id,
      ...widget.initialCollectionIds,
    };
    _savedCollectionIds = {
      for (final c in _record?.collections ?? const <NoteCollection>[]) c.id,
    };
    _savedAnchorSignature = _anchorSignature();
    _stage = _record == null ? _SaveStage.draft : _SaveStage.saved;
    _titleController = TextEditingController(text: _savedTitle);
    _bodyController = TextEditingController(text: _savedBody);
    _tagController = TextEditingController(text: _savedTags.join(', '));
    _titleFocus = FocusNode();
    _bodyFocus = FocusNode();
    _tagFocus = FocusNode();
    _lastSignature = _dirtySignature;
    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
    _tagController.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    widget.changeSignal?.addListener(_onExternalNotesChanged);
    unawaited(_loadCollections());
    // The passed record can be a snapshot taken before another surface
    // appended to the note; refresh from the store so a re-created editor does
    // not show (and later save) the stale body.
    if (_record != null) unawaited(_refreshNoteMetadata(_record!.id));
    if (widget.autofocusTitle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (const bool.fromEnvironment('PDG_REVIEW_TRACE')) {
      debugPrint(
        'NOTE editor dispose id=${_record?.id} changes=$_hasChanges '
        'discarded=$_discarded bodyLen=${_bodyController.text.length}',
      );
    }
    _disposed = true;
    widget.changeSignal?.removeListener(_onExternalNotesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _linkHoverTimer?.cancel();
    _linkHoverHideTimer?.cancel();
    _linkHoverOverlay?.remove();
    _linkHoverOverlay = null;
    _closeFloatingLookup();
    if (!_discarded && (_saving || _hasChanges)) {
      _flushOnDispose();
    }
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCollections() async {
    try {
      final collections = await widget.store.collections();
      final tags = await widget.store.tagCounts(limit: 100);
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _knownTags = tags.keys.toList(growable: false);
        _collectionIds.removeWhere(
          (id) => !collections.any((collection) => collection.id == id),
        );
      });
    } catch (_) {
      // The note itself remains editable; collection metadata is optional.
    }
  }

  Future<void> _editCollections() async {
    final selected = Set<String>.of(_collectionIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.strings.notesCollections),
          content: SizedBox(
            width: 360,
            child: _collections.isEmpty
                ? Text(widget.strings.notesCollectionEmpty)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final collection in _collections)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(collection.id),
                          title: Text(collection.name),
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
    setState(() {
      _collectionIds = result;
      _collectionsDirty = true;
      _lastSignature = _dirtySignature;
      _stage = _SaveStage.pending;
    });
    await _saveNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveNow());
    }
  }

  String _committedText(TextEditingController controller) {
    final value = controller.value;
    if (!value.composing.isValid) return value.text;
    return value.text.replaceRange(
      value.composing.start,
      value.composing.end,
      '',
    );
  }

  String _anchorKey(String kind, String key, String hash) =>
      '${kind.trim().toLowerCase()}\u0000${key.trim()}\u0000$hash';

  String _persistedAnchorKey(NoteAnchor anchor) =>
      _anchorKey(anchor.targetKind, anchor.targetKey, anchor.snapshotHash);

  List<NoteAnchorInput> _allAnchors() {
    final result = <NoteAnchorInput>[];
    final seen = <String>{};
    void add(NoteAnchorInput anchor) {
      final hash = anchor.snapshotHash ?? '';
      final key = _anchorKey(anchor.targetKind, anchor.targetKey, hash);
      if (_removedAnchorIds.contains(key)) return;
      if (seen.add(key)) result.add(anchor);
    }

    for (final anchor in _record?.anchors ?? const <NoteAnchor>[]) {
      if (_removedAnchorIds.contains(_persistedAnchorKey(anchor))) continue;
      add(
        NoteAnchorInput(
          targetKind: anchor.targetKind,
          targetKey: anchor.targetKey,
          snapshotHash: anchor.snapshotHash.isEmpty
              ? null
              : anchor.snapshotHash,
          targetLabel: anchor.targetLabel,
          status: anchor.status,
          context: anchor.context,
        ),
      );
    }
    for (final anchor in _draftAnchors) {
      add(anchor);
    }
    for (final anchor in _quickAnchors) {
      add(anchor);
    }
    return result;
  }

  String _anchorSignature() {
    final keys = [for (final anchor in _allAnchors()) anchor.targetId]..sort();
    return keys.join('|');
  }

  Future<void> _openPdgHit(SearchHit hit) async {
    if (hit.note != null) {
      await openNoteEditor(context, hit.note!);
      return;
    }
    if (hit.referenceId != null) {
      await AppNav.push<void>(
        context,
        ReferencePage(referenceId: hit.referenceId!),
      );
      return;
    }
    final pdgid = hit.pdgid;
    if (pdgid != null && pdgid.isNotEmpty) {
      await AppNav.openPdgid(context, pdgid);
    }
  }

  String get _signature =>
      '${_titleController.text}\u0000${_bodyController.text}\u0000'
      '${_tagController.text}';

  String get _dirtySignature {
    final collections = _collectionIds.toList()..sort();
    return '$_signature\u0000${_anchorSignature()}\u0000${collections.join(',')}';
  }

  bool get _isComposing =>
      _titleController.value.composing.isValid ||
      _bodyController.value.composing.isValid ||
      _tagController.value.composing.isValid;

  bool get _hasChanges {
    final title = _titleController.text;
    final body = _bodyController.text;
    final tags = parseNoteTags(_tagController.text);
    final existing = _record;
    if (existing == null) {
      return title.trim().isNotEmpty ||
          body.trim().isNotEmpty ||
          tags.isNotEmpty;
    }
    return title != _savedTitle ||
        body != _savedBody ||
        !_sameTags(tags, _savedTags) ||
        (_collectionsDirty &&
            !_sameStringSets(_collectionIds, _savedCollectionIds)) ||
        _anchorSignature() != _savedAnchorSignature;
  }

  void _onChanged() {
    if (_disposed || _suppressChange) return;
    final signature = _dirtySignature;
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    _autosaveTimer?.cancel();
    // The text fields repaint themselves; rebuilding the editor (toolbar,
    // status, anchors) on every keystroke made typing on a phone jitter.
    // Only the stage transition needs a rebuild.
    if (!_saving && mounted && _stage != _SaveStage.pending) {
      setState(() => _stage = _SaveStage.pending);
    }
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (_isComposing) {
      // Do not persist half-composed IME text; retry shortly and save once
      // the composition has been committed or cancelled.
      _autosaveTimer = Timer(const Duration(milliseconds: 250), _saveNow);
      return;
    }
    _autosaveTimer = Timer(widget.debounce, _saveNow);
  }

  Future<void> _saveNow({bool force = false}) async {
    if (_disposed) return;
    if (_isComposing) {
      _autosaveTimer = Timer(const Duration(milliseconds: 250), _saveNow);
      return;
    }
    if (_saving) {
      _autosaveTimer = Timer(widget.debounce, _saveNow);
      return;
    }
    if (!_hasChanges) {
      if (mounted &&
          (_stage == _SaveStage.pending || _stage == _SaveStage.failed)) {
        setState(() {
          _stage = _record == null ? _SaveStage.draft : _SaveStage.saved;
          _saveError = null;
        });
      }
      return;
    }
    await _persist(force: force);
  }

  Future<NoteRecord?>? _activePersist;

  Future<NoteRecord?> _persist({bool reportState = true, bool force = false}) {
    final active = _activePersist;
    if (active != null) return active;
    final future = _persistBody(reportState: reportState, force: force);
    _activePersist = future;
    future.whenComplete(() {
      if (identical(_activePersist, future)) _activePersist = null;
    });
    return future;
  }

  /// Another surface (PDG lookup, note links, the notes list) may add an
  /// anchor to the note open here. Refresh its metadata without touching the
  /// title/body the user is typing.
  void _onExternalNotesChanged() {
    final current = _record;
    if (const bool.fromEnvironment('PDG_REVIEW_TRACE')) {
      debugPrint('NOTE change signal id=${current?.id} saving=$_saving');
    }
    if (current == null || _saving) return;
    unawaited(_refreshNoteMetadata(current.id));
  }

  Future<void> _refreshNoteMetadata(String id) async {
    final fresh = await widget.store.noteById(id);
    if (!mounted || fresh == null) return;
    final current = _record;
    if (current == null || fresh.revision == current.revision) return;
    final savedBody = current.bodyMarkdown;
    final freshBody = fresh.bodyMarkdown;
    setState(() {
      _record = fresh;
      // Another surface appended a quote/source line (the PDG lookup): merge
      // the suffix into the text being edited instead of losing it on the next
      // autosave, which would write our older body back.
      if (freshBody != savedBody) {
        final suffix = freshBody.startsWith(savedBody)
            ? freshBody.substring(savedBody.length)
            : '\n\n$freshBody';
        final text = _bodyController.text;
        if (text == savedBody) {
          _bodyController.value = TextEditingValue(
            text: freshBody,
            selection: TextSelection.collapsed(offset: freshBody.length),
          );
          _savedBody = freshBody;
        } else {
          final merged = '$text$suffix';
          _bodyController.value = TextEditingValue(
            text: merged,
            selection: TextSelection.collapsed(offset: merged.length),
          );
        }
      }
      _savedAnchorSignature = _anchorSignature();
    });
  }

  Future<NoteRecord?> _persistBody({
    bool reportState = true,
    bool force = false,
  }) async {
    if (_saving) return _record;
    final title = _committedText(_titleController);
    final body = _committedText(_bodyController);
    final tags = parseNoteTags(_committedText(_tagController));
    final existing = _record;
    final changed = existing == null
        ? (title.trim().isNotEmpty ||
              body.trim().isNotEmpty ||
              tags.isNotEmpty ||
              _collectionIds.isNotEmpty ||
              _quickAnchors.isNotEmpty)
        : (title != _savedTitle ||
              body != _savedBody ||
              !_sameTags(tags, _savedTags) ||
              !_sameStringSets(_collectionIds, _savedCollectionIds) ||
              _anchorSignature() != _savedAnchorSignature);
    if (!changed) return existing;

    _saving = true;
    if (reportState && mounted) {
      setState(() {
        _stage = _SaveStage.saving;
        _saveError = null;
      });
    }
    final changeSignal = widget.changeSignal;
    try {
      final NoteRecord saved;
      if (existing == null) {
        saved = await widget.store.create(
          title: title,
          bodyMarkdown: body,
          anchors: _allAnchors(),
          tags: tags,
          collectionIds: _collectionIds.toList(),
        );
      } else {
        final anchorsChanged = _anchorSignature() != _savedAnchorSignature;
        // Another surface may have appended a quote/source line (PDG lookup)
        // while this editor was open and its change signal was not processed
        // yet. Merge that suffix instead of overwriting it on save.
        var bodyToSave = body;
        var anchorsToSave = anchorsChanged ? _allAnchors() : null;
        var expectedRevision = force ? null : _record?.revision;
        final latest = await widget.store.noteById(existing.id);
        if (const bool.fromEnvironment('PDG_REVIEW_TRACE')) {
          debugPrint(
            'NOTE save id=${existing.id} rev=${existing.revision} '
            'latestRev=${latest?.revision} bodyLen=${body.length} '
            'titleChanged=${latest != null && latest.title != existing.title}',
          );
        }
        final base = _record?.bodyMarkdown ?? '';
        if (latest != null &&
            _record != null &&
            latest.revision != _record!.revision &&
            // Only an append (the capture flow) is merged silently; a real
            // external edit keeps the conflict path below.
            latest.title == _record!.title &&
            latest.bodyMarkdown.startsWith(base)) {
          final latestBody = latest.bodyMarkdown;
          final suffix = latestBody.substring(base.length);
          if (suffix.isNotEmpty) {
            bodyToSave = '${bodyToSave.trimRight()}$suffix';
          }
          if (const bool.fromEnvironment('PDG_REVIEW_TRACE')) {
            debugPrint(
              'NOTE save merged id=${existing.id} suffixLen=${suffix.length} '
              'finalLen=${bodyToSave.length}',
            );
          }
          final merged = <String, NoteAnchorInput>{};
          for (final anchor in latest.anchors) {
            merged['${anchor.targetId}\u0000${anchor.snapshotHash}'] =
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
          for (final anchor in _allAnchors()) {
            merged['${anchor.targetId}\u0000${anchor.snapshotHash ?? ''}'] =
                anchor;
          }
          anchorsToSave = merged.values.toList(growable: false);
          expectedRevision = latest.revision;
        }
        await widget.store.update(
          existing.id,
          title: title,
          bodyMarkdown: bodyToSave,
          anchors: anchorsToSave,
          tags: tags,
          expectedRevision: expectedRevision,
        );
        if (_collectionsDirty) {
          final before = {
            for (final collection in existing.collections) collection.id,
          };
          for (final id in _collectionIds.difference(before)) {
            await widget.store.addNoteToCollection(existing.id, id);
          }
          for (final id in before.difference(_collectionIds)) {
            await widget.store.removeNoteFromCollection(existing.id, id);
          }
        }
        saved = (await widget.store.noteById(existing.id))!;
      }
      _saving = false;
      _record = saved;
      _savedTitle = saved.title;
      _savedBody = saved.bodyMarkdown;
      _savedTags = saved.tagNames;
      _collectionIds = {
        for (final collection in saved.collections) collection.id,
      };
      _savedCollectionIds = Set<String>.of(_collectionIds);
      _quickAnchors.clear();
      _savedAnchorSignature = _anchorSignature();
      _collectionsDirty = false;
      changeSignal?.value++;
      // Notify the owner even when this widget is being disposed: a draft
      // remount needs the durable row so it does not create a second note.
      widget.onSaved?.call(saved);
      if (_disposed || !mounted) return saved;
      final stillDirty = _hasChanges;
      setState(() {
        _stage = stillDirty ? _SaveStage.pending : _SaveStage.saved;
        _saveError = null;
      });
      if (stillDirty) _scheduleAutosave();
      return saved;
    } catch (error) {
      _saving = false;
      // A content update may have committed before a membership edge failed.
      // Reload the durable row so the next autosave does not reuse a stale
      // revision. A real conflict, however, must keep the stale revision so
      // the next save cannot silently overwrite the other writer's content;
      // the Reload/Keep-mine banner is the only resolution path.
      final conflict =
          error is NotesException && error.code == NotesErrorCode.conflict;
      if (!conflict && existing != null) {
        try {
          final latest = await widget.store.noteById(existing.id);
          if (latest != null && mounted) {
            _record = latest;
            _savedTitle = latest.title;
            _savedBody = latest.bodyMarkdown;
            _savedTags = latest.tagNames;
            _collectionIds = {
              for (final collection in latest.collections) collection.id,
            };
            _savedCollectionIds = Set<String>.of(_collectionIds);
            _collectionsDirty = false;
          }
        } catch (_) {
          // Keep the original error; the user can still retry or copy text.
        }
      }
      if (_disposed || !mounted) return null;
      setState(() {
        _stage = _SaveStage.failed;
        _saveError = error;
      });
      return null;
    }
  }

  /// Persists the last buffer when the editor is closed before the autosave
  /// timer fires. Failures are deliberately silent: the entity/list will show
  /// the last saved state instead of an editor that no longer exists.
  void _flushOnDispose() {
    final title = _committedText(_titleController);
    final body = _committedText(_bodyController);
    final tags = parseNoteTags(_committedText(_tagController));
    final anchors = _allAnchors();
    final collectionIds = _collectionIds.toList();
    final store = widget.store;
    final changeSignal = widget.changeSignal;
    final active = _activePersist;
    unawaited(() async {
      try {
        // A save may already be in flight. Wait for it so the final update uses
        // the new revision instead of racing it and losing the last edit.
        if (active != null) {
          await active;
        }
        final existing = _record;
        if (existing == null &&
            title.trim().isEmpty &&
            body.trim().isEmpty &&
            tags.isEmpty &&
            anchors.isEmpty &&
            collectionIds.isEmpty) {
          return;
        }
        if (existing != null &&
            title == existing.title &&
            body == existing.bodyMarkdown &&
            _sameTags(tags, existing.tagNames) &&
            _sameStringSets(
              collectionIds.toSet(),
              existing.collections.map((collection) => collection.id).toSet(),
            ) &&
            _anchorSignature() == _savedAnchorSignature) {
          return;
        }
        NoteRecord? saved;
        if (existing == null) {
          saved = await store.create(
            title: title,
            bodyMarkdown: body,
            anchors: anchors,
            tags: tags,
            collectionIds: collectionIds,
          );
        } else {
          await store.update(
            existing.id,
            title: title,
            bodyMarkdown: body,
            anchors: anchors,
            tags: tags,
            expectedRevision: existing.revision,
          );
          if (_collectionsDirty) {
            final before = {
              for (final collection in existing.collections) collection.id,
            };
            for (final id in collectionIds.toSet().difference(before)) {
              await store.addNoteToCollection(existing.id, id);
            }
            for (final id in before.difference(collectionIds.toSet())) {
              await store.removeNoteFromCollection(existing.id, id);
            }
          }
          saved = await store.noteById(existing.id);
        }
        if (saved != null) widget.onSaved?.call(saved);
        changeSignal?.value++;
      } catch (error) {
        // The editor is gone, so there is no place for a dialog. Keep the
        // failure observable in logs instead of claiming a save.
        debugPrint('Particle Library: note flush on close failed: $error');
      }
    }());
  }

  Future<void> _cancelDraft() async {
    if (!widget.draft) return;
    final title = _committedText(_titleController).trim();
    final body = _committedText(_bodyController).trim();
    final tags = parseNoteTags(_committedText(_tagController));
    final hasAnchors = _allAnchors().isNotEmpty;
    final hasContent =
        title.isNotEmpty ||
        body.isNotEmpty ||
        tags.isNotEmpty ||
        hasAnchors ||
        _record != null;
    if (hasContent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(widget.strings.notesDiscardDraft),
          content: Text(widget.strings.notesDiscardDraftBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(widget.strings.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(widget.strings.notesDiscardDraftAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _discarded = true;
    _autosaveTimer?.cancel();
    final active = _activePersist;
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
    final record = _record;
    if (record != null) {
      try {
        await widget.store.delete(record.id);
        widget.changeSignal?.value++;
      } catch (error) {
        debugPrint('Particle Library: discard draft failed: $error');
      }
    }
    widget.onCancel?.call();
  }

  Future<void> _linkAnotherNote() async {
    final strings = widget.strings;
    final notes = await widget.store.recent(limit: 50);
    if (!mounted) return;
    final candidates = notes.where((note) => note.id != _record?.id).toList();
    final search = TextEditingController();
    final selected = await showDialog<NoteRecord>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.notesLinkNote),
        content: SizedBox(
          width: 460,
          height: 420,
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              final query = search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? candidates
                  : candidates
                        .where(
                          (note) =>
                              note.title.toLowerCase().contains(query) ||
                              note.bodyPlain.toLowerCase().contains(query),
                        )
                        .toList(growable: false);
              return Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: strings.notesSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                    onChanged: (_) => setLocalState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final note in filtered)
                          ListTile(
                            dense: true,
                            title: Text(
                              noteDisplayTitle(note, strings),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              noteBodyPreview(note, maxLength: 100),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(dialogContext).pop(note),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.commonCancel),
          ),
        ],
      ),
    );
    search.dispose();
    if (selected == null || !mounted) return;
    final label = noteDisplayTitle(selected, strings);
    final snippet = '[${label.replaceAll(']', '\\]')}](note:${selected.uuid})';
    final value = _bodyController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text;
    final prefix = start > 0 && !text.substring(start - 1, start).contains('\n')
        ? ' '
        : '';
    final next = text.replaceRange(start, end, '$prefix$snippet ');
    _bodyController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + prefix.length + snippet.length + 1,
      ),
    );
    _quickAnchors.add(NoteAnchorInput.note(selected.uuid, targetLabel: label));
    _onChanged();
  }

  void _removePersistedAnchor(NoteAnchor anchor) {
    final key = _persistedAnchorKey(anchor);
    final input = NoteAnchorInput(
      targetKind: anchor.targetKind,
      targetKey: anchor.targetKey,
      snapshotHash: anchor.snapshotHash.isEmpty ? null : anchor.snapshotHash,
      targetLabel: anchor.targetLabel,
      status: anchor.status,
      context: anchor.context,
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removedAnchorIds.add(key));
    _onChanged();
    showUndoSnackBar(
      messenger,
      message: widget.strings.notesAnchorRemoved,
      undoLabel: widget.strings.notesUndo,
      onUndo: () {
        if (!mounted) return;
        setState(() {
          _removedAnchorIds.remove(key);
          _quickAnchors.add(input);
        });
        _onChanged();
      },
    );
  }

  void _removeDraftAnchor(NoteAnchorInput anchor) {
    final wasDraft = _draftAnchors.contains(anchor);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _quickAnchors.remove(anchor);
      _draftAnchors.remove(anchor);
    });
    _onChanged();
    showUndoSnackBar(
      messenger,
      message: widget.strings.notesAnchorRemoved,
      undoLabel: widget.strings.notesUndo,
      onUndo: () {
        if (!mounted) return;
        setState(() {
          if (_quickAnchors.contains(anchor) ||
              _draftAnchors.contains(anchor)) {
            return;
          }
          if (wasDraft) {
            _draftAnchors.add(anchor);
          } else {
            _quickAnchors.add(anchor);
          }
        });
        _onChanged();
      },
    );
  }

  Future<void> _showRelatedNotes() async {
    final record = _record;
    if (record == null) return;
    final strings = widget.strings;
    final found = <String, NoteRecord>{};
    for (final anchor in record.anchors) {
      final notes = await widget.store.notesForTarget(
        anchor.targetKind,
        anchor.targetKey,
        limit: 20,
      );
      for (final note in notes) {
        if (note.id != record.id) found[note.id] = note;
      }
    }
    // Incoming note links are not anchors; search Markdown links to this UUID.
    final mentions = await widget.store.notesMentioningTargets([
      NoteTarget.note(record.uuid),
    ], limit: 20);
    for (final note in mentions) {
      if (note.id != record.id) found[note.id] = note;
    }
    if (!mounted) return;
    final related = found.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.notesRelatedTitle),
        content: SizedBox(
          width: 480,
          child: related.isEmpty
              ? Text(strings.notesRelatedEmpty)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final note in related)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.sticky_note_2_outlined,
                            size: 18,
                          ),
                          title: Text(
                            noteDisplayTitle(note, strings),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            note.bodyPlain,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            openNoteEditor(context, note);
                          },
                        ),
                    ],
                  ),
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

  Future<void> _keepMine() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.notesKeepMineTitle),
        content: Text(widget.strings.notesKeepMineBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.notesKeepMine),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _persist(force: true);
  }

  Future<void> _reloadFromDisk() async {
    final existing = _record;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.notesReloadTitle),
        content: Text(widget.strings.notesReloadBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.strings.notesReload),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final latest = await widget.store.get(existing.id);
    if (!mounted) return;
    if (latest == null || latest.isDeleted) {
      widget.onDeleted?.call();
      return;
    }
    _autosaveTimer?.cancel();
    _suppressChange = true;
    try {
      _record = latest;
      _savedTitle = latest.title;
      _savedBody = latest.bodyMarkdown;
      _savedTags = latest.tagNames;
      _savedCollectionIds = {
        for (final collection in latest.collections) collection.id,
      };
      _collectionIds = Set<String>.of(_savedCollectionIds);
      _quickAnchors.clear();
      _titleController.text = latest.title;
      _bodyController.text = latest.bodyMarkdown;
      _tagController.text = latest.tagNames.join(', ');
      _lastSignature = _signature;
      _savedAnchorSignature = _anchorSignature();
    } finally {
      _suppressChange = false;
    }
    if (!mounted) return;
    setState(() {
      _stage = _SaveStage.saved;
      _saveError = null;
    });
  }

  void _scheduleLinkPreview(String target, Offset globalPosition) {
    _linkHoverTimer?.cancel();
    _linkHoverHideTimer?.cancel();
    final generation = ++_linkHoverGeneration;
    _linkHoverTimer = Timer(const Duration(milliseconds: 300), () {
      _showLinkHoverPreview(target, globalPosition, generation);
    });
  }

  Future<void> _showLinkHoverPreview(
    String target,
    Offset globalPosition,
    int generation,
  ) async {
    NoteLinkPreview? preview;
    try {
      preview = await loadNoteLinkPreview(context, target);
    } catch (_) {
      preview = null;
    }
    if (!mounted || generation != _linkHoverGeneration || preview == null) {
      return;
    }
    _removeLinkHoverOverlay();
    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.sizeOf(context);
    const width = 340.0;
    const estimatedHeight = 250.0;
    final maxLeft = screen.width > width + 16 ? screen.width - width - 8 : 8.0;
    final maxTop = screen.height > estimatedHeight + 16
        ? screen.height - estimatedHeight
        : 8.0;
    final left = (globalPosition.dx + 14).clamp(8.0, maxLeft);
    final top = (globalPosition.dy + 16).clamp(8.0, maxTop);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        width: width,
        child: IgnorePointer(child: _NoteLinkHoverCard(preview: preview!)),
      ),
    );
    _linkHoverOverlay = entry;
    overlay.insert(entry);
  }

  void _hideLinkHover({bool delayed = false}) {
    _linkHoverTimer?.cancel();
    _linkHoverHideTimer?.cancel();
    _linkHoverGeneration++;
    if (!delayed) {
      _removeLinkHoverOverlay();
      return;
    }
    _linkHoverHideTimer = Timer(
      const Duration(milliseconds: 180),
      _removeLinkHoverOverlay,
    );
  }

  void _removeLinkHoverOverlay() {
    _linkHoverHideTimer?.cancel();
    _linkHoverOverlay?.remove();
    _linkHoverOverlay = null;
  }

  Future<void> _openNoteLink(String target) async {
    _hideLinkHover();
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    if (scope.settings.noteLinkMode == 'sidebar' &&
        supportsNoteLinkPreview(target)) {
      if (MediaQuery.sizeOf(context).width >= 1360) {
        setState(() {
          _linkPreviewTarget = target;
          _showPdgRail = true;
        });
      } else {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: SizedBox(
              width: 420,
              height: 460,
              child: NoteLinkSidebar(
                target: target,
                onClose: () => Navigator.of(dialogContext).pop(),
                onOpenTarget: (target) async {
                  Navigator.of(dialogContext).pop();
                  await openNoteLinkTarget(context, target);
                },
              ),
            ),
          ),
        );
      }
      return;
    }
    final opened = await openNoteLinkTarget(context, target);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.strings.notesLinkMissing)));
    }
  }

  Future<void> _openPdgLookup() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    // Make sure a draft exists in the store before the lookup's capture
    // dialog lists notes, otherwise the user cannot append to this note.
    if (_hasChanges) await _persist();
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    if (size.width >= 900) {
      _toggleFloatingLookup(scope.services, size);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 520,
          height: 620,
          child: NotePdgRail(
            search: scope.search,
            strings: widget.strings,
            onOpen: (hit) {
              Navigator.of(context).pop();
              _openPdgHit(hit);
            },
          ),
        ),
      ),
    );
  }

  void _toggleFloatingLookup(AppServices scope, Size size) {
    if (_lookupOverlay != null) {
      if (_lookupOverlay!.mounted) {
        _closeFloatingLookup();
        return;
      }
      FloatingPanelHost.unregister(_lookupOverlay!);
      _lookupOverlay = null;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final width = math.min(520.0, size.width - 48);
    final height = math.min(620.0, size.height - 120);
    final rect = Rect.fromLTWH((size.width - width) / 2, 80, width, height);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FloatingLookupHost(
        search: scope.search,
        strings: widget.strings,
        initialRect: rect,
        maxSize: Size(size.width - 24, size.height - 60),
        onClose: _closeFloatingLookup,
      ),
    );
    _lookupOverlay = entry;
    FloatingPanelHost.register(entry, overlay);
    overlay.insert(entry);
  }

  void _closeFloatingLookup() {
    final entry = _lookupOverlay;
    if (entry != null) FloatingPanelHost.dismiss(entry);
    _lookupOverlay = null;
  }

  Future<void> _copyMarkdown() async {
    final saved = await _persist();
    if (!mounted) return;
    if (saved == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.strings.notesSaveFailed)));
      return;
    }
    await copyText(
      context,
      noteAsMarkdown(saved, untitled: widget.strings.notesUntitled),
      message: widget.strings.notesCopiedMarkdown,
    );
  }

  Future<void> _copyReference({required bool bibtex}) async {
    final saved = await _persist();
    if (!mounted) return;
    if (saved == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.strings.notesSaveFailed)));
      return;
    }
    final callback = bibtex ? widget.onCopyBibtex : widget.onCopyCiteKeys;
    if (callback != null) await callback(saved);
  }

  Future<void> _confirmDelete() async {
    final record = _record;
    if (record == null) return;
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = context.palette;
        return AlertDialog(
          title: Text(strings.notesDeleteConfirmTitle),
          content: Text(strings.notesDeleteConfirmBody),
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
        );
      },
    );
    if (confirmed != true || !mounted) return;
    _autosaveTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.delete(record.id);
      widget.changeSignal?.value++;
      showUndoSnackBar(
        messenger,
        message: strings.notesDeleted,
        undoLabel: strings.notesUndo,
        onUndo: () async {
          await widget.store.restore(record.id);
          widget.changeSignal?.value++;
        },
      );
      widget.onDeleted?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _SaveStage.failed;
        _saveError = error;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${strings.notesDeleteFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The window height is not the room the editor gets: the app bar, the
        // keyboard and the page chrome take their share. A landscape phone has
        // ~440 dp of window, so decide from the space actually available.
        final height = constraints.maxHeight;
        // The Scaffold has already consumed the keyboard inset (it resized
        // this box), so the available height is the only keyboard signal left.
        // 300 dp is below a landscape phone with the keyboard up and well
        // above the candidate-bar jitter, so it does not oscillate.
        return _buildEditor(
          context,
          tight: height < 480,
          veryTight: height < 300,
        );
      },
    );
  }

  Widget _titleField(BuildContext context, {required bool dense}) {
    final strings = widget.strings;
    return TextField(
      controller: _titleController,
      focusNode: _titleFocus,
      maxLines: 1,
      style: dense
          ? Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)
          : Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        hintText: strings.notesTitleHint,
        border: InputBorder.none,
        filled: false,
        isDense: dense,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  /// Secondary editor actions for the one-row landscape header.
  Widget _editorOverflow(BuildContext context) {
    final strings = widget.strings;
    final hasCite =
        widget.onCopyCiteKeys != null || widget.onCopyBibtex != null;
    return PopupMenuButton<String>(
      tooltip: strings.commonMoreOptions,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'pdg':
            unawaited(_openPdgLookup());
          case 'related':
            unawaited(_showRelatedNotes());
          case 'markdown':
            unawaited(_copyMarkdown());
          case 'citekeys':
            unawaited(_copyReference(bibtex: false));
          case 'bibtex':
            unawaited(_copyReference(bibtex: true));
          case 'delete':
            unawaited(_confirmDelete());
          case 'discard':
            unawaited(_cancelDraft());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'pdg', child: Text(strings.notesPdgLookup)),
        if (_record != null && _record!.anchors.isNotEmpty)
          PopupMenuItem(value: 'related', child: Text(strings.notesRelated)),
        if (_record != null && hasCite) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'markdown',
            child: Text(strings.notesCopyMarkdown),
          ),
          PopupMenuItem(
            value: 'citekeys',
            child: Text(strings.notesCopyCiteKeys),
          ),
          PopupMenuItem(value: 'bibtex', child: Text(strings.notesCopyBibtex)),
        ] else if (_record != null)
          PopupMenuItem(
            value: 'markdown',
            child: Text(strings.notesCopyMarkdown),
          ),
        if (_record != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text(strings.notesDelete)),
        ],
        if (widget.draft && widget.onCancel != null)
          PopupMenuItem(
            value: 'discard',
            child: Text(strings.notesDiscardDraft),
          ),
      ],
    );
  }

  Widget _buildEditor(
    BuildContext context, {
    required bool tight,
    required bool veryTight,
  }) {
    final palette = context.palette;
    final strings = widget.strings;
    final tags = parseNoteTags(_tagController.text);
    final anchors = _record?.anchors ?? const <NoteAnchor>[];
    final scope = AppScope.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.l,
        Insets.m,
        Insets.l,
        Insets.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final compactHeader = headerConstraints.maxWidth < 620;
              // Landscape: title and toolbar share one row so the body keeps
              // the vertical space a second row would cost.
              final singleRow = tight && !compactHeader;
              final status = _StatusIndicator(
                stage: _stage,
                error: _saveError,
                strings: strings,
                onRetry: _saveNow,
                onReload:
                    _saveError is NotesException &&
                        (_saveError as NotesException).code ==
                            NotesErrorCode.conflict
                    ? _reloadFromDisk
                    : null,
                onKeepMine:
                    _saveError is NotesException &&
                        (_saveError as NotesException).code ==
                            NotesErrorCode.conflict
                    ? _keepMine
                    : null,
              );
              final actions = <Widget>[
                if (scope != null)
                  Builder(
                    builder: (context) {
                      final railVisible =
                          !widget.compact &&
                          MediaQuery.sizeOf(context).width >= 1360 &&
                          _showPdgRail &&
                          _linkPreviewTarget == null;
                      return IconButton(
                        tooltip: strings.notesPdgLookup,
                        style: IconButton.styleFrom(
                          backgroundColor: railVisible
                              ? palette.primary.withValues(alpha: 0.12)
                              : null,
                          foregroundColor: railVisible ? palette.primary : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        onPressed: () {
                          if (!widget.compact &&
                              MediaQuery.sizeOf(context).width >= 1360) {
                            setState(() {
                              _linkPreviewTarget = null;
                              _showPdgRail = !_showPdgRail;
                            });
                          } else {
                            _openPdgLookup();
                          }
                        },
                        icon: Icon(
                          railVisible
                              ? Icons.travel_explore
                              : Icons.travel_explore_outlined,
                          size: 19,
                        ),
                      );
                    },
                  ),
                IconButton(
                  tooltip: strings.notesLinkNote,
                  onPressed: _linkAnotherNote,
                  icon: const Icon(Icons.add_link, size: 19),
                ),
                if (_record != null && _record!.anchors.isNotEmpty)
                  IconButton(
                    tooltip: strings.notesRelated,
                    onPressed: _showRelatedNotes,
                    icon: const Icon(Icons.hub_outlined, size: 19),
                  ),
                IconButton(
                  tooltip: _previewOnly
                      ? strings.notesWrite
                      : strings.notesPreview,
                  onPressed: () => setState(() => _previewOnly = !_previewOnly),
                  icon: Icon(
                    _previewOnly
                        ? Icons.edit_note_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: strings.notesCopyMarkdown,
                  onPressed: _record == null ? null : _copyMarkdown,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                ),
                if (_record != null &&
                    (widget.onCopyCiteKeys != null ||
                        widget.onCopyBibtex != null))
                  PopupMenuButton<String>(
                    tooltip: strings.notesCopyCiteKeys,
                    icon: const Icon(Icons.format_quote, size: 18),
                    onSelected: (value) =>
                        unawaited(_copyReference(bibtex: value == 'bibtex')),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'citekeys',
                        child: Text(strings.notesCopyCiteKeys),
                      ),
                      PopupMenuItem(
                        value: 'bibtex',
                        child: Text(strings.notesCopyBibtex),
                      ),
                    ],
                  ),
                if (_record != null)
                  IconButton(
                    tooltip: strings.notesDelete,
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                if (widget.draft && widget.onCancel != null)
                  IconButton(
                    tooltip: strings.notesDiscardDraft,
                    onPressed: _cancelDraft,
                    icon: const Icon(Icons.close, size: 19),
                  ),
              ];
              if (singleRow) {
                // The title keeps the same position whether the tools are
                // shown or hidden: moving it would rebuild the field and
                // close the keyboard.
                return Row(
                  children: [
                    Visibility(
                      visible: !veryTight,
                      maintainState: true,
                      child: status,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _titleField(context, dense: true)),
                    Visibility(
                      visible: !veryTight,
                      maintainState: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _previewOnly
                                ? strings.notesWrite
                                : strings.notesPreview,
                            onPressed: () =>
                                setState(() => _previewOnly = !_previewOnly),
                            icon: Icon(
                              _previewOnly
                                  ? Icons.edit_note_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
                            ),
                          ),
                          IconButton(
                            tooltip: strings.notesLinkNote,
                            onPressed: _linkAnotherNote,
                            icon: const Icon(Icons.add_link, size: 19),
                          ),
                          _editorOverflow(context),
                        ],
                      ),
                    ),
                  ],
                );
              }
              final header = compactHeader
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        status,
                        Wrap(
                          spacing: 0,
                          runSpacing: 0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [status, ...actions],
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Visibility(
                    visible: !veryTight,
                    maintainState: true,
                    child: header,
                  ),
                  _titleField(context, dense: false),
                ],
              );
            },
          ),
          Visibility(
            visible:
                !tight &&
                (anchors.isNotEmpty ||
                    _draftAnchors.isNotEmpty ||
                    _quickAnchors.isNotEmpty ||
                    tags.isNotEmpty),
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.only(top: Insets.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (anchors.isNotEmpty ||
                      _draftAnchors.isNotEmpty ||
                      _quickAnchors.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          strings.notesAnchorsLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _anchorSummary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final anchor in anchors)
                          _anchorChip(
                            context,
                            kind: anchor.targetKind,
                            label: anchorDisplayLabel(anchor),
                            targetId: anchor.targetId,
                            resolved: anchor.isResolved,
                            onTap: () => openNoteAnchor(context, anchor),
                            onRemove: () => _removePersistedAnchor(anchor),
                          ),
                        if (_record == null)
                          for (final input in _draftAnchors)
                            _anchorChip(
                              context,
                              kind: input.targetKind,
                              label: input.targetLabel.trim().isEmpty
                                  ? input.targetId
                                  : input.targetLabel,
                              targetId: input.targetId,
                              resolved: input.status.isResolved,
                              onRemove: () => _removeDraftAnchor(input),
                            ),
                        for (final input in _quickAnchors)
                          _anchorChip(
                            context,
                            kind: input.targetKind,
                            label: input.targetLabel.trim().isEmpty
                                ? input.targetId
                                : input.targetLabel,
                            targetId: input.targetId,
                            resolved: input.status.isResolved,
                            onRemove: () => _removeDraftAnchor(input),
                          ),
                      ],
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: Insets.s),
                    Text(
                      strings.notesTagsLabel,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tag in tags)
                          ActionChip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: () => showNotesForTag(
                              context,
                              store: widget.store,
                              strings: widget.strings,
                              tag: tag,
                              onOpen: (note) => openNoteEditor(context, note),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: tight ? 2 : Insets.s),
          Divider(height: 1, color: palette.divider),
          SizedBox(height: tight ? 2 : Insets.s),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Short landscape shows the editor alone: side-by-side
                      // preview there leaves neither pane usable. The preview
                      // toggle still switches the whole body to preview.
                      final wide = constraints.maxWidth >= 640 && !tight;
                      final editor = TextField(
                        controller: _bodyController,
                        focusNode: _bodyFocus,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(height: 1.6),
                        decoration: InputDecoration(
                          hintText: strings.notesBodyHint,
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      );
                      final preview = NotesMarkdownPreview(
                        markdown: _bodyController.text,
                        emptyHint: strings.notesBodyHint,
                        padding: EdgeInsets.zero,
                        onOpenLink: _openNoteLink,
                        onHoverLink: _scheduleLinkPreview,
                        onLeaveLink: () => _hideLinkHover(delayed: true),
                      );
                      if (_previewOnly) return preview;
                      if (!wide) return editor;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: editor),
                          VerticalDivider(width: 24, color: palette.divider),
                          Expanded(child: preview),
                        ],
                      );
                    },
                  ),
                ),
                if (scope != null &&
                    !widget.compact &&
                    MediaQuery.sizeOf(context).width >= 1360 &&
                    (_showPdgRail || _linkPreviewTarget != null))
                  SizedBox(
                    width: 300,
                    child: _linkPreviewTarget != null
                        ? NoteLinkSidebar(
                            target: _linkPreviewTarget!,
                            onClose: () =>
                                setState(() => _linkPreviewTarget = null),
                            onOpenTarget: (target) async {
                              setState(() => _linkPreviewTarget = null);
                              await openNoteLinkTarget(context, target);
                            },
                          )
                        : NotePdgRail(
                            search: scope.search,
                            strings: strings,
                            onOpen: _openPdgHit,
                          ),
                  ),
              ],
            ),
          ),
          SizedBox(height: tight ? 2 : Insets.s),
          Divider(height: 1, color: palette.divider),
          SizedBox(height: tight ? 2 : Insets.s),
          Visibility(
            visible: !tight,
            maintainState: true,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _editCollections,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(
                    _collectionIds.isEmpty
                        ? strings.notesCollections
                        : '${strings.notesCollections} (${_collectionIds.length})',
                  ),
                ),
                for (final collection in _collections.where(
                  (collection) => _collectionIds.contains(collection.id),
                ))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(collection.name),
                    onDeleted: () async {
                      setState(() {
                        _collectionIds.remove(collection.id);
                        _collectionsDirty = true;
                      });
                      await _saveNow();
                    },
                  ),
              ],
            ),
          ),
          // Hide the tag field only when it cannot own focus: while the body
          // is being typed in a short landscape window it would otherwise
          // leave the text area a few pixels tall. It stays mounted, and it is
          // never hidden while focused (that would drop the input connection).
          Visibility(
            visible: !veryTight || _tagFocus.hasFocus,
            maintainState: true,
            child: NoteTagField(
              controller: _tagController,
              knownTags: _knownTags,
              strings: widget.strings,
              onChanged: _onChanged,
              focusNode: _tagFocus,
            ),
          ),
        ],
      ),
    );
  }

  String _anchorSummary() {
    final counts = <String, int>{};
    var unresolved = 0;
    for (final anchor in _allAnchors()) {
      counts.update(anchor.targetKind, (value) => value + 1, ifAbsent: () => 1);
      if (!anchor.status.isResolved) unresolved++;
    }
    final parts = <String>[];
    for (final entry in counts.entries) {
      final label = switch (entry.key) {
        NoteTargetKinds.note => widget.strings.notesAnchorKindNote,
        NoteTargetKinds.measurement =>
          widget.strings.notesAnchorKindMeasurement,
        NoteTargetKinds.reference => widget.strings.notesAnchorKindReference,
        NoteTargetKinds.review => widget.strings.notesAnchorKindReview,
        _ => widget.strings.notesAnchorKindPdgid,
      };
      parts.add('$label ${entry.value}');
    }
    if (unresolved > 0) {
      parts.add('${widget.strings.notesAnchorUnresolved} $unresolved');
    }
    return parts.join(' · ');
  }

  Widget _anchorChip(
    BuildContext context, {
    required String kind,
    required String label,
    required String targetId,
    required bool resolved,
    VoidCallback? onTap,
    VoidCallback? onRemove,
  }) {
    final palette = context.palette;
    final strings = widget.strings;
    final (IconData icon, String kindLabel, Color kindColor) = switch (kind) {
      NoteTargetKinds.note => (
        Icons.sticky_note_2_outlined,
        strings.notesAnchorKindNote,
        palette.primary,
      ),
      NoteTargetKinds.measurement => (
        Icons.straighten_outlined,
        strings.notesAnchorKindMeasurement,
        palette.accent,
      ),
      NoteTargetKinds.reference => (
        Icons.menu_book_outlined,
        strings.notesAnchorKindReference,
        palette.accent,
      ),
      NoteTargetKinds.review => (
        Icons.picture_as_pdf_outlined,
        strings.notesAnchorKindReview,
        palette.warning,
      ),
      _ => (
        Icons.science_outlined,
        strings.notesAnchorKindPdgid,
        palette.textSecondary,
      ),
    };
    final chip = Chip(
      avatar: Icon(
        resolved ? icon : Icons.link_off,
        size: 14,
        color: resolved ? kindColor : palette.warning,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          kind == NoteTargetKinds.pdgid ? label : '$kindLabel · $label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      backgroundColor: resolved
          ? null
          : palette.warning.withValues(alpha: 0.10),
      side: resolved
          ? null
          : BorderSide(color: palette.warning.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onDeleted: onRemove,
      deleteIcon: onRemove == null ? null : const Icon(Icons.close, size: 14),
      deleteButtonTooltipMessage: strings.notesRemoveAnchor,
    );
    final wrapped = Tooltip(
      message: resolved
          ? '$kindLabel\n$targetId'
          : '${strings.notesAnchorUnresolved}\n$kindLabel · $targetId',
      child: chip,
    );
    if (onTap == null) return wrapped;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: wrapped,
    );
  }

  static bool _sameStringSets(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.of(a)..sort();
    final sortedB = List<String>.of(b)..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.stage,
    required this.error,
    required this.strings,
    required this.onRetry,
    this.onReload,
    this.onKeepMine,
  });

  final _SaveStage stage;
  final Object? error;
  final AppStrings strings;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onReload;
  final Future<void> Function()? onKeepMine;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (IconData icon, String label, Color color) = switch (stage) {
      _SaveStage.draft => (
        Icons.edit_note,
        strings.notesDraft,
        palette.textSecondary,
      ),
      _SaveStage.pending => (
        Icons.cloud_upload_outlined,
        strings.notesSavePending,
        palette.warning,
      ),
      _SaveStage.saving => (
        Icons.sync,
        strings.notesSaving,
        palette.textSecondary,
      ),
      _SaveStage.saved => (
        Icons.check_circle_outline,
        strings.notesSaved,
        palette.accent,
      ),
      _SaveStage.failed => (
        Icons.error_outline,
        strings.notesSaveFailed,
        palette.error,
      ),
    };
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: stage == _SaveStage.saving
              ? const Padding(
                  padding: EdgeInsets.all(1),
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
        if (stage == _SaveStage.failed) ...[
          if (onKeepMine != null)
            IconButton(
              tooltip: strings.notesKeepMine,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              onPressed: () => onKeepMine!(),
              icon: Icon(Icons.priority_high, size: 15, color: color),
            ),
          if (onReload != null)
            IconButton(
              tooltip: strings.notesReload,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              onPressed: () => onReload!(),
              icon: Icon(Icons.sync_problem, size: 15, color: color),
            ),
          IconButton(
            tooltip: strings.notesSaveRetry,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
            onPressed: () => onRetry(),
            icon: Icon(Icons.refresh, size: 15, color: color),
          ),
        ],
      ],
    );
    if (error == null) return row;
    return Tooltip(message: errorText(error!, strings), child: row);
  }
}

/// Standalone editor route used by the narrow Notes page and by entity
/// backlinks/composers.
/// Content of the wide-screen floating lookup: a nested [Navigator] so a
/// result opens *inside* the panel and the note editor underneath keeps its
/// text and focus.
class _FloatingLookupHost extends StatefulWidget {
  const _FloatingLookupHost({
    required this.search,
    required this.strings,
    required this.initialRect,
    required this.maxSize,
    required this.onClose,
  });

  final SearchService search;
  final AppStrings strings;
  final Rect initialRect;
  final Size maxSize;
  final VoidCallback onClose;

  @override
  State<_FloatingLookupHost> createState() => _FloatingLookupHostState();
}

class _FloatingLookupHostState extends State<_FloatingLookupHost> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  int _depth = 0;

  void _push(SearchHit hit) {
    final page = _pageFor(hit);
    final navigator = _navigator.currentState;
    if (page == null || navigator == null) return;
    setState(() => _depth++);
    navigator.push(MaterialPageRoute<void>(builder: (_) => page)).whenComplete(
      () {
        if (mounted && _depth > 0) setState(() => _depth--);
      },
    );
  }

  Widget? _pageFor(SearchHit hit) {
    if (hit.note != null) return NoteEditorPage(note: hit.note);
    if (hit.referenceId != null) {
      return ReferencePage(referenceId: hit.referenceId!);
    }
    final pdgid = hit.pdgid;
    if (pdgid == null) return null;
    return EntryRoutePage(pdgid: pdgid);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      title: widget.strings.notesPdgLookup,
      initialRect: widget.initialRect,
      maxSize: widget.maxSize,
      onClose: widget.onClose,
      onBack: _depth > 0 ? () => _navigator.currentState?.maybePop() : null,
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => NotePdgRail(
            search: widget.search,
            strings: widget.strings,
            autofocus: true,
            onOpen: _push,
          ),
        ),
      ),
    );
  }
}

class NoteEditorPage extends StatelessWidget implements ImmersivePage {
  const NoteEditorPage({
    super.key,
    this.note,
    this.initialAnchors = const <NoteAnchorInput>[],
    this.initialCollectionIds = const <String>[],
  });

  final NoteRecord? note;
  final List<NoteAnchorInput> initialAnchors;
  final List<String> initialCollectionIds;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final store = scope.notes;
    if (store == null) {
      return PageScaffold(
        title: Text(strings.notesTitle),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Insets.l),
            child: Text(strings.notesUnavailable),
          ),
        ),
      );
    }
    final editor = NoteEditor(
      key: ValueKey<String>(note?.id ?? 'new-note'),
      store: store,
      strings: strings,
      note: note,
      initialAnchors: initialAnchors,
      initialCollectionIds: initialCollectionIds,
      changeSignal: scope.notesChanges,
      autofocusTitle: note == null,
      draft: note == null,
      onDeleted: () => Navigator.of(context).maybePop(),
      onCancel: () => Navigator.of(context).maybePop(),
    );
    return PageScaffold(
      maxWidth: 980,
      title: Text(note == null ? strings.notesNew : strings.notesEdit),
      body: editor,
    );
  }
}

class _NoteLinkHoverCard extends StatelessWidget {
  const _NoteLinkHoverCard({required this.preview});

  final NoteLinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    return Material(
      elevation: 8,
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 250),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              preview.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            if (preview.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Flexible(
                child: DescriptionText(
                  preview.description,
                  maxLines: 5,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              strings.notesLinkPreview,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: palette.accent),
            ),
          ],
        ),
      ),
    );
  }
}
