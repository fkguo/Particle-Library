import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/immersive_page.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../data/review_annotation_notes.dart';
import '../../data/review_annotations.dart';
import '../../notes/notes_store.dart';
import '../../notes/notes_models.dart';
import '../common/resize_handle.dart';
import '../common/snack_bars.dart';
import '../notes/note_editor.dart';

class ReviewViewerPage extends StatefulWidget implements ImmersivePage {
  const ReviewViewerPage({
    super.key,
    required this.title,
    required this.path,
    required this.officialUrl,
    this.initialPage = 1,
  });

  final String title;
  final String path;
  final String officialUrl;
  final int initialPage;

  @override
  State<ReviewViewerPage> createState() => _ReviewViewerPageState();
}

class _ReviewViewerPageState extends State<ReviewViewerPage> {
  final PdfViewerController _controller = PdfViewerController();
  NotesStore? _notes;
  List<ReviewAnnotation> _annotations = const <ReviewAnnotation>[];
  bool _showAnnotations = true;
  bool _sidebarInitialized = false;
  bool _saving = false;
  bool _addingHighlight = false;
  bool _highlightMode = false;
  bool _annotationSelectionMode = false;
  bool _zenMode = false;
  bool _pdfDarkMode = false;
  bool _regionMode = false;
  bool _outlineLoading = false;
  int _sidebarTab = 0;
  double _sidebarWidth = 320;
  List<PdfOutlineNode> _outline = const <PdfOutlineNode>[];
  final Set<String> _selectedAnnotationIds = <String>{};
  String? _lastCollectionId;
  Timer? _autoHighlightTimer;
  String _highlightColor = 'yellow';
  bool _started = false;
  ReviewAnnotation? _editingRange;
  bool _pdfReady = false;
  int _pdfEpoch = 0;
  Timer? _pdfRetryTimer;
  late final Future<void> _ready;

  String get _fileName {
    final segments = Uri.file(widget.path).pathSegments;
    for (final segment in segments.reversed) {
      if (segment.trim().isNotEmpty) return segment;
    }
    return '';
  }

  @override
  void dispose() {
    _autoHighlightTimer?.cancel();
    _pdfRetryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _ready = _loadAnnotations(AppScope.of(context).notes);
    // Some Android devices paint the first PDF frame before the viewer has
    // laid out its page. Recreate once if readiness is still false shortly
    // after the first open; reopening used to be the only workaround.
    _pdfRetryTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && !_pdfReady) setState(() => _pdfEpoch++);
    });
  }

  Future<void> _loadAnnotations(NotesStore? notes) async {
    setState(() => _notes = notes);
    try {
      if (notes != null) {
        await ReviewAnnotationNotes.ensureMigrated(notes);
        final annotations = await ReviewAnnotationNotes.load(
          notes,
          _fileName,
          reviewTitle: widget.title,
        );
        if (!mounted) return;
        setState(() {
          _annotations = annotations;
          final visible = {for (final annotation in annotations) annotation.id};
          _selectedAnnotationIds.removeWhere((id) => !visible.contains(id));
        });
        return;
      }
      final store = await ReviewAnnotationStore.open();
      final annotations = await store.load();
      if (!mounted) return;
      setState(() {
        _annotations = [
          for (final annotation in annotations)
            if (annotation.fileName == _fileName) annotation,
        ];
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppScope.of(context).strings.notesUnavailable}: ${errorText(error, AppScope.of(context).strings)}',
          ),
        ),
      );
    }
  }

  void _notifyNotesChanged() {
    if (!mounted) return;
    AppScope.of(context).notesChanges.value++;
  }

  void _offerAddToCollection(List<ReviewAnnotation> additions) {
    if (!mounted || additions.isEmpty) return;
    final strings = AppScope.of(context).strings;
    showActionSnackBar(
      ScaffoldMessenger.of(context),
      message: strings.reviewHighlightAdded,
      actionLabel: strings.notesAddToCollection,
      onAction: () => unawaited(_addAnnotationsToCollection(additions)),
    );
  }

  Future<bool> _addAnnotationsToCollection(
    List<ReviewAnnotation> additions,
  ) async {
    final store = _notes;
    if (store == null || !mounted) return false;
    final strings = AppScope.of(context).strings;
    final collections = await store.collections();
    if (!mounted) return false;
    if (collections.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.notesNoCollections)));
      return false;
    }
    final selected = <String>{
      if (_lastCollectionId != null &&
          collections.any((collection) => collection.id == _lastCollectionId))
        _lastCollectionId!,
    };
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.notesAddToCollection),
          content: SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final NoteCollection collection in collections)
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.commonCancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(Set.of(selected)),
              child: Text(strings.commonSave),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return false;
    try {
      for (final annotation in additions) {
        final noteId = annotation.noteId;
        if (noteId == null) continue;
        for (final collectionId in result) {
          await store.addNoteToCollection(noteId, collectionId);
        }
      }
      if (!mounted) return false;
      _notifyNotesChanged();
      final previous = _lastCollectionId;
      _lastCollectionId = result.firstWhere(
        (id) => id != previous,
        orElse: () => result.first,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.reviewHighlightAddedToCollection)),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.notesCollectionFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.officialUrl);
    if (uri == null || uri.scheme != 'https') return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).strings.reviewsOpenFailed),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewsOpenFailed)),
      );
    }
  }

  void _onTextSelectionChanged(PdfTextSelection selection) {
    _autoHighlightTimer?.cancel();
    if (_editingRange != null ||
        !_highlightMode ||
        !selection.hasSelectedText) {
      return;
    }
    _autoHighlightTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_highlightMode) return;
      unawaited(_highlightSelection());
    });
  }

  void _toggleHighlightMode() {
    setState(() => _highlightMode = !_highlightMode);
    if (!_highlightMode) _autoHighlightTimer?.cancel();
  }

  Future<void> _highlightSelection() async {
    await _ready;
    if (!mounted) return;
    if (!_controller.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewPdfLoading)),
      );
      return;
    }
    if (_addingHighlight) return;
    final delegate = _controller.textSelectionDelegate;
    if (!delegate.hasSelectedText) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewSelectText)),
      );
      return;
    }
    setState(() => _addingHighlight = true);
    try {
      final ranges = await delegate.getSelectedTextRanges();
      final rectsByPage = <int, List<Rect>>{};
      final textByPage = <int, String>{};
      for (final range in ranges) {
        final pageNumber = range.pageNumber;
        if (pageNumber < 1 || pageNumber > _controller.pageCount) continue;
        final page = _controller.pages[pageNumber - 1];
        if (page.width <= 0 || page.height <= 0) continue;
        for (final fragment in range.enumerateFragmentBoundingRects()) {
          // toRect applies page rotation and the PDF y-up -> Flutter y-down
          // conversion. Normalize the result so paint only needs pageRect.
          final rect = normalizePdfSelectionRect(fragment.bounds, page);
          if (rect.width <= 0 || rect.height <= 0) continue;
          rectsByPage.putIfAbsent(pageNumber, () => <Rect>[]).add(rect);
        }
        final pageText = range.text.trim();
        if (pageText.isNotEmpty) {
          textByPage[pageNumber] = [
            if (textByPage[pageNumber]?.isNotEmpty ?? false)
              textByPage[pageNumber]!,
            pageText,
          ].join(' ');
        }
      }
      if (!mounted || rectsByPage.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppScope.of(context).strings.reviewSelectText),
            ),
          );
        }
        return;
      }
      final notes = _notes;
      if (notes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).strings.notesUnavailable),
          ),
        );
        return;
      }
      final selected = <({int page, List<Rect> rects, String text})>[
        for (final entry in rectsByPage.entries)
          (
            page: entry.key,
            rects: List<Rect>.unmodifiable(entry.value),
            text: textByPage[entry.key] ?? '',
          ),
      ];
      // Clear before awaiting the write: the pdfrx delegate is detached when
      // the viewer is disposed.
      await delegate.clearTextSelection();
      final additions = <ReviewAnnotation>[];
      for (final item in selected) {
        additions.add(
          await ReviewAnnotationNotes.create(
            notes,
            fileName: _fileName,
            pageNumber: item.page,
            rects: item.rects,
            text: item.text,
            color: _highlightColor,
            reviewTitle: widget.title,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _annotations = [...additions, ..._annotations]);
      _notifyNotesChanged();
      _offerAddToCollection(additions);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).strings.reviewSelectText),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _addingHighlight = false);
    }
  }

  Future<void> _beginAdjustRange(ReviewAnnotation annotation) async {
    await _ready;
    if (!mounted) return;
    if (!_controller.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewPdfLoading)),
      );
      return;
    }
    try {
      final page = _controller.pages[annotation.pageNumber - 1];
      final pageText = await page.loadStructuredText();
      final quote = annotation.text.trim();
      var start = quote.isEmpty ? -1 : pageText.fullText.indexOf(quote);
      if (start < 0 && quote.isNotEmpty) {
        start = pageText.fullText
            .replaceAll(RegExp(r'\s+'), ' ')
            .indexOf(quote.replaceAll(RegExp(r'\s+'), ' '));
      }
      var end = start < 0
          ? -1
          : (start + quote.length - 1).clamp(0, pageText.fullText.length - 1);
      if (start < 0 || pageText.charRects.isEmpty) {
        // Stored quotes can differ from extracted PDF text after line-break
        // normalization. Use the stored rectangles' first/last characters.
        int nearest(Offset point) {
          var best = 0;
          var bestDistance = double.infinity;
          for (var i = 0; i < pageText.charRects.length; i++) {
            final rect = normalizePdfSelectionRect(pageText.charRects[i], page);
            final dx = rect.center.dx - point.dx;
            final dy = rect.center.dy - point.dy;
            final distance = dx * dx + dy * dy;
            if (distance < bestDistance) {
              bestDistance = distance;
              best = i;
            }
          }
          return best;
        }

        final first = annotation.rects.first.center;
        final last = annotation.rects.last.center;
        final a = nearest(first);
        final b = nearest(last);
        start = a < b ? a : b;
        end = a < b ? b : a;
      }
      if (start < 0 || end < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).strings.reviewSelectText),
          ),
        );
        return;
      }
      await _controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(pageText, start),
          PdfTextSelectionPoint(pageText, end),
        ),
      );
      if (!mounted) return;
      setState(() {
        _editingRange = annotation;
        _highlightMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppScope.of(context).strings.reviewAdjustRangeHint),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewSelectText)),
      );
    }
  }

  Future<void> _saveAdjustedRange() async {
    final annotation = _editingRange;
    final notes = _notes;
    if (annotation == null || notes == null) return;
    if (!_controller.isReady) return;
    final delegate = _controller.textSelectionDelegate;
    if (!delegate.hasSelectedText) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewSelectText)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ranges = await delegate.getSelectedTextRanges();
      final rects = <Rect>[];
      final textParts = <String>[];
      for (final range in ranges) {
        if (range.pageNumber != annotation.pageNumber) continue;
        final page = _controller.pages[range.pageNumber - 1];
        for (final fragment in range.enumerateFragmentBoundingRects()) {
          final rect = normalizePdfSelectionRect(fragment.bounds, page);
          if (rect.width > 0 && rect.height > 0) rects.add(rect);
        }
        final text = range.text.trim();
        if (text.isNotEmpty) textParts.add(text);
      }
      if (rects.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).strings.reviewSelectText),
          ),
        );
        return;
      }
      final updated = await ReviewAnnotationNotes.updateRange(
        notes,
        annotation,
        rects: rects,
        text: textParts.join(' '),
      );
      await delegate.clearTextSelection();
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _annotations = [
            for (final item in _annotations)
              if (item.id == updated.id) updated else item,
          ];
          _editingRange = null;
        });
        _notifyNotesChanged();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppScope.of(context).strings.notesSaveFailed}: ${errorText(error, AppScope.of(context).strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAnnotationNote(ReviewAnnotation annotation) async {
    await _ready;
    if (!mounted) return;
    final noteId = annotation.noteId;
    final notes = _notes;
    if (noteId == null || notes == null) return;
    final note = await notes.noteById(noteId);
    if (!mounted || note == null) return;
    await AppNav.push<void>(context, NoteEditorPage(note: note));
    if (mounted) await _loadAnnotations(notes);
  }

  Future<void> _editAnnotation(ReviewAnnotation annotation) async {
    await _ready;
    if (!mounted) return;
    final notes = _notes;
    if (notes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.notesUnavailable)),
      );
      return;
    }
    final strings = AppScope.of(context).strings;
    final comment = TextEditingController(text: annotation.note);
    final tagInput = TextEditingController();
    final tags = <String>{...annotation.tags};
    final result =
        await showModalBottomSheet<({String comment, List<String> tags})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              void addTag(String raw) {
                final tag = raw.trim();
                if (tag.isEmpty) return;
                setSheetState(() => tags.add(tag));
                tagInput.clear();
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.reviewAnnotationEdit,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: strings.commonClose,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (annotation.imagePath != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(annotation.imagePath!),
                            height: 130,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else
                        SelectableText(
                          annotation.text.trim().isEmpty
                              ? strings.reviewAnnotationRegion
                              : annotation.text,
                          maxLines: 3,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.palette.textSecondary),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: comment,
                        autofocus: true,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: strings.reviewAnnotationNote,
                          hintText: strings.reviewAnnotationNoteHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        strings.reviewTags,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in tags.toList()..sort())
                            InputChip(
                              label: Text(tag),
                              onDeleted: () =>
                                  setSheetState(() => tags.remove(tag)),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (tags.isEmpty)
                            Text(
                              strings.reviewTagHint,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.palette.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: tagInput,
                              decoration: InputDecoration(
                                hintText: strings.reviewTagHint,
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              onSubmitted: addTag,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: strings.reviewAddTag,
                            onPressed: () => addTag(tagInput.text),
                            icon: const Icon(Icons.add, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: Text(strings.commonCancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => Navigator.of(sheetContext).pop((
                              comment: comment.text.trim(),
                              tags: (tags.toList()..sort()),
                            )),
                            child: Text(strings.commonSave),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    comment.dispose();
    tagInput.dispose();
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ReviewAnnotationNotes.updateComment(
        notes,
        annotation,
        result.comment,
        tags: result.tags,
      );
      if (!mounted) return;
      await _loadAnnotations(notes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${strings.notesSaveFailed}: ${errorText(error, strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAnnotation(ReviewAnnotation annotation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(AppScope.of(context).strings.reviewDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppScope.of(context).strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppScope.of(context).strings.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _ready;
    if (!mounted) return;
    final notes = _notes;
    if (notes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.notesUnavailable)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ReviewAnnotationNotes.delete(notes, annotation);
      if (!mounted) return;
      setState(() {
        _annotations = [
          for (final item in _annotations)
            if (item.id != annotation.id) item,
        ];
      });
      _notifyNotesChanged();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppScope.of(context).strings.notesSaveFailed}: ${errorText(error, AppScope.of(context).strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _customizePdfContextMenu(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    if (params.textSelectionDelegate.hasSelectedText) {
      items.insert(
        0,
        ContextMenuButtonItem(
          label: AppScope.of(context).strings.reviewHighlight,
          onPressed: () {
            params.dismissContextMenu();
            unawaited(_highlightSelection());
          },
        ),
      );
    }
  }

  Color _annotationColor(String name) => switch (name) {
    'green' => const Color(0xFF4CAF50),
    'pink' => const Color(0xFFE91E63),
    'blue' => const Color(0xFF2196F3),
    _ => const Color(0xFFFFC107),
  };

  Future<void> _loadOutline(PdfDocument document) async {
    if (!mounted) return;
    setState(() => _outlineLoading = true);
    try {
      final outline = await document.loadOutline();
      if (!mounted) return;
      setState(() {
        _outline = outline;
        _outlineLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outline = const <PdfOutlineNode>[];
        _outlineLoading = false;
      });
    }
  }

  void _openOutline(PdfOutlineNode node) {
    if (!_controller.isReady || node.dest == null) return;
    unawaited(_controller.goToDest(node.dest));
  }

  Future<String?> _renderRegionImage(int pageNumber, Rect rect) async {
    try {
      if (!_controller.isReady ||
          pageNumber < 1 ||
          pageNumber > _controller.pages.length) {
        return null;
      }
      final page = await _controller.pages[pageNumber - 1].ensureLoaded();
      const scale = 2.0;
      final fullWidth = (page.width * scale).round().clamp(1, 6000);
      final fullHeight = (page.height * scale).round().clamp(1, 6000);
      final left = (rect.left * fullWidth).round().clamp(0, fullWidth - 1);
      final top = (rect.top * fullHeight).round().clamp(0, fullHeight - 1);
      final right = (rect.right * fullWidth).round().clamp(left + 1, fullWidth);
      final bottom = (rect.bottom * fullHeight).round().clamp(
        top + 1,
        fullHeight,
      );
      final rendered = await page.render(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
        fullWidth: fullWidth.toDouble(),
        fullHeight: fullHeight.toDouble(),
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) return null;
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(rendered.pixels);
        final descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: rendered.width,
          height: rendered.height,
          rowBytes: rendered.width * 4,
          pixelFormat: ui.PixelFormat.bgra8888,
        );
        final codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        frame.image.dispose();
        codec.dispose();
        buffer.dispose();
        if (png == null) return null;
        final support = await getApplicationSupportDirectory();
        final directory = Directory(
          '${support.path}/ParticleDesk/review_regions',
        );
        await directory.create(recursive: true);
        final file = File(
          '${directory.path}/region-${DateTime.now().microsecondsSinceEpoch}-$pageNumber.png',
        );
        await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
        return file.path;
      } finally {
        rendered.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _createRegionAnnotation(int pageNumber, Rect rect) async {
    if (rect.width < 0.004 || rect.height < 0.004) return;
    await _ready;
    if (!mounted) return;
    final notes = _notes;
    if (notes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.notesUnavailable)),
      );
      return;
    }
    if (_addingHighlight) return;
    setState(() => _addingHighlight = true);
    try {
      final created = await ReviewAnnotationNotes.create(
        notes,
        fileName: _fileName,
        pageNumber: pageNumber,
        rects: <Rect>[rect],
        text: '',
        color: _highlightColor,
        reviewTitle: widget.title,
        imagePath: await _renderRegionImage(pageNumber, rect),
      );
      if (!mounted) return;
      setState(() {
        _annotations = [created, ..._annotations];
        _regionMode = false;
      });
      _notifyNotesChanged();
      _offerAddToCollection([created]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppScope.of(context).strings.notesSaveFailed}: ${errorText(error, AppScope.of(context).strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _addingHighlight = false);
    }
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final annotation in _annotations) {
      if (annotation.pageNumber != page.pageNumber) continue;
      final paint = Paint()
        ..color = _annotationColor(annotation.color).withValues(alpha: 0.38);
      for (final rect in annotation.rects) {
        canvas.drawRect(
          Rect.fromLTWH(
            pageRect.left + rect.left * pageRect.width,
            pageRect.top + rect.top * pageRect.height,
            rect.width * pageRect.width,
            rect.height * pageRect.height,
          ),
          paint,
        );
      }
    }
  }

  Widget _highlightGlyph(IconData icon) {
    final color = Theme.of(context).iconTheme.color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 19, color: color),
          Positioned(
            right: -1,
            bottom: 0,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _annotationColor(_highlightColor),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHandle(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    return CustomPaint(
      size: const Size(30, 30),
      painter: _SelectionHandlePainter(color, state),
    );
  }

  List<Widget> _annotationOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final widgets = <Widget>[];
    for (final annotation in _annotations) {
      if (annotation.pageNumber != page.pageNumber) continue;
      if (annotation.text.trim().isEmpty) {
        final rect = annotation.rects.first;
        widgets.add(
          Positioned(
            left: rect.left * pageRect.width,
            top: rect.top * pageRect.height,
            width: rect.width * pageRect.width,
            height: rect.height * pageRect.height,
            child: _PdfRegionAdjustOverlay(
              rect: rect,
              pageSize: pageRect.size,
              color: _annotationColor(annotation.color),
              onChanged: (next) => _updateRegionAnnotation(annotation.id, next),
              onEnd: (next) => unawaited(_persistRegion(annotation.id, next)),
              onTap: () => unawaited(_showAnnotationActions(annotation)),
            ),
          ),
        );
        continue;
      }
      for (final rect in annotation.rects) {
        final left = rect.left * pageRect.width - 5;
        final top = rect.top * pageRect.height - 5;
        final width = rect.width * pageRect.width + 10;
        final height = rect.height * pageRect.height + 10;
        widgets.add(
          Positioned(
            left: left,
            top: top,
            width: width < 28 ? 28 : width,
            height: height < 28 ? 28 : height,
            child: PdfOverlayInteractionRegion(
              onTap: (_) {
                // Zotero-style direct selection: tapping a highlight selects
                // its text and exposes the two range handles immediately.
                unawaited(_beginAdjustRange(annotation));
                return true;
              },
              onSecondaryTap: (_) {
                unawaited(_showAnnotationActions(annotation));
                return true;
              },
              onLongPress: (_) {
                unawaited(_showAnnotationActions(annotation));
                return true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        );
      }
    }
    if (_regionMode) {
      widgets.add(
        Positioned.fill(
          child: _PdfRegionSelector(
            pageNumber: page.pageNumber,
            color: _annotationColor(_highlightColor),
            onSelected: (rect) =>
                unawaited(_createRegionAnnotation(page.pageNumber, rect)),
          ),
        ),
      );
    }
    return widgets;
  }

  ReviewAnnotation _withRect(ReviewAnnotation annotation, Rect rect) {
    return ReviewAnnotation(
      id: annotation.id,
      fileName: annotation.fileName,
      pageNumber: annotation.pageNumber,
      rects: <Rect>[rect],
      text: annotation.text,
      note: annotation.note,
      color: annotation.color,
      createdAt: annotation.createdAt,
      noteId: annotation.noteId,
      imagePath: annotation.imagePath,
      tags: annotation.tags,
    );
  }

  void _updateRegionAnnotation(String id, Rect rect) {
    setState(() {
      _annotations = [
        for (final annotation in _annotations)
          annotation.id == id ? _withRect(annotation, rect) : annotation,
      ];
    });
  }

  Future<void> _persistRegion(String id, Rect rect) async {
    final notes = _notes;
    if (notes == null) return;
    final index = _annotations.indexWhere((annotation) => annotation.id == id);
    if (index < 0) return;
    final annotation = _annotations[index];
    try {
      final updated = await ReviewAnnotationNotes.updateRange(
        notes,
        annotation,
        rects: <Rect>[rect],
        text: '',
      );
      if (!mounted || updated == null) return;
      setState(() {
        _annotations = [
          for (final item in _annotations)
            if (item.id == updated.id) updated else item,
        ];
      });
      _notifyNotesChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppScope.of(context).strings.notesSaveFailed}: ${errorText(error, AppScope.of(context).strings)}',
          ),
        ),
      );
    }
  }

  Future<void> _showAnnotationActions(ReviewAnnotation annotation) async {
    final strings = AppScope.of(context).strings;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                annotation.text.trim().isEmpty
                    ? strings.reviewAnnotationRegion
                    : annotation.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                strings.reviewAnnotationPage(annotation.pageNumber),
              ),
            ),
            if (annotation.imagePath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(annotation.imagePath!),
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: Text(strings.reviewOpenNote),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_openAnnotationNote(annotation));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(strings.reviewAnnotationEdit),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_editAnnotation(annotation));
              },
            ),
            if (annotation.text.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_with_outlined),
                title: Text(strings.reviewAdjustRange),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_beginAdjustRange(annotation));
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(strings.commonDelete),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_deleteAnnotation(annotation));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAnnotationSelectionMode() {
    setState(() {
      _annotationSelectionMode = !_annotationSelectionMode;
      _selectedAnnotationIds.clear();
    });
  }

  void _toggleAnnotationSelected(String id) {
    setState(() {
      if (!_selectedAnnotationIds.remove(id)) {
        _selectedAnnotationIds.add(id);
      }
    });
  }

  Future<void> _addSelectedAnnotationsToCollection() async {
    final selected = [
      for (final annotation in _annotations)
        if (_selectedAnnotationIds.contains(annotation.id)) annotation,
    ];
    if (selected.isEmpty) return;
    final added = await _addAnnotationsToCollection(selected);
    if (added && mounted) {
      setState(() {
        _annotationSelectionMode = false;
        _selectedAnnotationIds.clear();
      });
    }
  }

  void _openAnnotationsSheet({int tab = 0}) {
    setState(() => _sidebarTab = tab);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: _ReviewAnnotationSidebar(
            annotations: _annotations,
            palette: context.palette,
            strings: AppScope.of(context).strings,
            onOpen: (annotation) {
              Navigator.of(context).pop();
              if (_controller.isReady) {
                unawaited(
                  _controller.goToPage(pageNumber: annotation.pageNumber),
                );
              }
            },
            onOpenNote: _openAnnotationNote,
            onEditNote: _editAnnotation,
            onDelete: _deleteAnnotation,
            selectionMode: _annotationSelectionMode,
            selectedIds: _selectedAnnotationIds,
            onToggleSelectionMode: () {
              _toggleAnnotationSelectionMode();
              setSheetState(() {});
            },
            onToggleSelection: (id) {
              _toggleAnnotationSelected(id);
              setSheetState(() {});
            },
            onAddSelected: () async {
              await _addSelectedAnnotationsToCollection();
              if (context.mounted) setSheetState(() {});
            },
            tabIndex: _sidebarTab,
            onTabChanged: (index) {
              setState(() => _sidebarTab = index);
              setSheetState(() {});
            },
            outline: _outline,
            outlineLoading: _outlineLoading,
            onOpenOutline: _openOutline,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = AppScope.of(context).strings;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: _zenMode
          ? null
          : AppBar(
              toolbarHeight: narrow ? 48 : null,
              titleSpacing: narrow ? 0 : null,
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.3),
              ),
              actions: [
                IconButton(
                  tooltip: _pdfDarkMode
                      ? strings.reviewPdfLightMode
                      : strings.reviewPdfDarkMode,
                  onPressed: () => setState(() => _pdfDarkMode = !_pdfDarkMode),
                  icon: Icon(
                    _pdfDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 19,
                  ),
                ),
                IconButton(
                  tooltip: strings.reviewFullScreen,
                  onPressed: () => setState(() => _zenMode = true),
                  icon: const Icon(Icons.fullscreen, size: 20),
                ),
                IconButton(
                  tooltip: strings.reviewOutlineTab,
                  onPressed: () {
                    if (narrow) {
                      _openAnnotationsSheet(tab: 1);
                    } else {
                      setState(() {
                        _showAnnotations = true;
                        _sidebarTab = 1;
                      });
                    }
                  },
                  icon: const Icon(Icons.list_alt, size: 19),
                ),
                IconButton(
                  tooltip: _regionMode
                      ? strings.commonCancel
                      : strings.reviewRegionSelect,
                  onPressed: () {
                    setState(() {
                      _regionMode = !_regionMode;
                      if (_regionMode) _highlightMode = false;
                    });
                  },
                  icon: Icon(
                    _regionMode ? Icons.close : Icons.crop_free,
                    size: 19,
                    color: _regionMode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                if (_editingRange != null) ...[
                  IconButton(
                    tooltip: strings.reviewSaveRange,
                    onPressed: _saving ? null : _saveAdjustedRange,
                    icon: const Icon(Icons.check),
                  ),
                  IconButton(
                    tooltip: strings.commonCancel,
                    onPressed: () {
                      _autoHighlightTimer?.cancel();
                      setState(() => _editingRange = null);
                      unawaited(
                        _controller.textSelectionDelegate.clearTextSelection(),
                      );
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
                IconButton(
                  tooltip: _highlightMode
                      ? strings.reviewHighlightModeOn
                      : strings.reviewHighlight,
                  onPressed: _saving || _addingHighlight
                      ? null
                      : _toggleHighlightMode,
                  icon: _highlightGlyph(
                    _highlightMode ? Icons.border_color : Icons.highlight_alt,
                  ),
                ),
                if (!narrow) ...[
                  PopupMenuButton<String>(
                    tooltip: strings.reviewHighlightColor,
                    icon: _highlightGlyph(Icons.palette_outlined),
                    onSelected: (color) =>
                        setState(() => _highlightColor = color),
                    itemBuilder: (context) => [
                      for (final color in const [
                        'yellow',
                        'green',
                        'pink',
                        'blue',
                      ])
                        PopupMenuItem(
                          value: color,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _annotationColor(color),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(strings.reviewHighlightColorName(color)),
                              if (color == _highlightColor) ...[
                                const Spacer(),
                                const Icon(Icons.check, size: 16),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: strings.reviewAnnotationSidebar,
                    onPressed: () {
                      final size = MediaQuery.sizeOf(context);
                      if (size.width < 700 || size.height < 500) {
                        _openAnnotationsSheet();
                      } else {
                        setState(() => _showAnnotations = !_showAnnotations);
                      }
                    },
                    icon: Badge.count(
                      count: _annotations.length,
                      isLabelVisible: _annotations.isNotEmpty,
                      child: Icon(
                        _showAnnotations
                            ? Icons.view_sidebar
                            : Icons.view_sidebar_outlined,
                        size: 19,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.reviewOpenOfficial,
                    icon: const Icon(Icons.open_in_new, size: 19),
                    onPressed: _openExternally,
                  ),
                ] else
                  PopupMenuButton<String>(
                    tooltip: strings.commonMoreOptions,
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (value) {
                      if (value.startsWith('color:')) {
                        setState(() => _highlightColor = value.substring(6));
                      } else if (value == 'sidebar') {
                        _openAnnotationsSheet();
                      } else if (value == 'official') {
                        _openExternally();
                      }
                    },
                    itemBuilder: (context) => [
                      for (final color in const [
                        'yellow',
                        'green',
                        'pink',
                        'blue',
                      ])
                        PopupMenuItem(
                          value: 'color:$color',
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _annotationColor(color),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(strings.reviewHighlightColorName(color)),
                              if (color == _highlightColor) ...[
                                const Spacer(),
                                const Icon(Icons.check, size: 16),
                              ],
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'sidebar',
                        child: Text(strings.reviewAnnotationSidebar),
                      ),
                      PopupMenuItem(
                        value: 'official',
                        child: Text(strings.reviewOpenOfficial),
                      ),
                    ],
                  ),
              ],
            ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (!_sidebarInitialized) {
                _sidebarInitialized = true;
                // A phone in landscape is wide but short; opening the 320 px
                // sidebar there leaves too little room for the page. Tablets and
                // desktops still get the inline sidebar.
                _showAnnotations =
                    constraints.maxWidth >= 700 && constraints.maxHeight >= 500;
              }
              final maxSidebar = (constraints.maxWidth - 260).clamp(
                220.0,
                560.0,
              );
              final sidebarWidth = _sidebarWidth.clamp(220.0, maxSidebar);
              return SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _pdfSurface(context)),
                    if (_showAnnotations && !_zenMode) ...[
                      CollapsibleSidePanel(
                        width: sidebarWidth,
                        handleOnLeft: true,
                        tooltip: strings.reviewAnnotationSidebar,
                        onDrag: (delta) => setState(() {
                          _sidebarWidth = (_sidebarWidth - delta).clamp(
                            220.0,
                            maxSidebar,
                          );
                        }),
                        onReset: () => setState(() => _sidebarWidth = 320),
                        child: _ReviewAnnotationSidebar(
                          annotations: _annotations,
                          palette: palette,
                          strings: strings,
                          onOpen: (annotation) {
                            if (!_controller.isReady) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings.reviewPdfLoading),
                                ),
                              );
                              return;
                            }
                            unawaited(
                              _controller.goToPage(
                                pageNumber: annotation.pageNumber,
                              ),
                            );
                          },
                          onOpenNote: _openAnnotationNote,
                          onEditNote: _editAnnotation,
                          onDelete: _deleteAnnotation,
                          selectionMode: _annotationSelectionMode,
                          selectedIds: _selectedAnnotationIds,
                          onToggleSelectionMode: _toggleAnnotationSelectionMode,
                          onToggleSelection: _toggleAnnotationSelected,
                          onAddSelected: _addSelectedAnnotationsToCollection,
                          tabIndex: _sidebarTab,
                          onTabChanged: (index) =>
                              setState(() => _sidebarTab = index),
                          outline: _outline,
                          outlineLoading: _outlineLoading,
                          onOpenOutline: _openOutline,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (_zenMode)
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: palette.surface.withValues(alpha: 0.94),
                elevation: 3,
                borderRadius: BorderRadius.circular(22),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: strings.commonBack,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 19),
                    ),
                    IconButton(
                      tooltip: _pdfDarkMode
                          ? strings.reviewPdfLightMode
                          : strings.reviewPdfDarkMode,
                      onPressed: () =>
                          setState(() => _pdfDarkMode = !_pdfDarkMode),
                      icon: Icon(
                        _pdfDarkMode
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        size: 19,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.reviewExitFullScreen,
                      onPressed: () => setState(() => _zenMode = false),
                      icon: const Icon(Icons.fullscreen_exit, size: 20),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pdfSurface(BuildContext context) {
    Widget viewer = PdfViewer.file(
      widget.path,
      key: ValueKey<String>('pdf-${widget.path}-$_pdfEpoch'),
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: _pdfDarkMode
            ? AppPalette.dark.background
            : context.palette.background,
        onViewerReady: (document, controller) {
          _pdfRetryTimer?.cancel();
          _pdfReady = true;
          unawaited(_loadOutline(document));
          if (widget.initialPage > 1) {
            unawaited(controller.goToPage(pageNumber: widget.initialPage));
          }
        },
        pagePaintCallbacks: [_paintAnnotations],
        pageOverlaysBuilder: _annotationOverlays,
        textSelectionParams: PdfTextSelectionParams(
          enabled: !_regionMode,
          buildSelectionHandle: _buildSelectionHandle,
          onTextSelectionChange: _onTextSelectionChanged,
          enableSelectionHandles:
              defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android,
          onSelectionHandlePanStart: (_) => _autoHighlightTimer?.cancel(),
        ),
        customizeContextMenuItems: _customizePdfContextMenu,
      ),
    );
    if (_pdfDarkMode) {
      // Map white PDF paper onto AppPalette.dark.background and black ink onto
      // a light foreground. A slightly steeper slope than a plain inversion
      // keeps antialiased, thin text readable on the dark paper.
      final dark = AppPalette.dark;
      const slope = 1.12;
      double offset(Color channel) => slope * 255 + channel.r * 255;
      viewer = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          -slope,
          0,
          0,
          0,
          offset(dark.background),
          0,
          -slope,
          0,
          0,
          offset(dark.background),
          0,
          0,
          -slope,
          0,
          offset(dark.background),
          0,
          0,
          0,
          1,
          0,
        ]),
        child: viewer,
      );
    }
    // The app-level SelectionArea must not own drag gestures inside the PDF;
    // pdfrx implements its own text selection.
    return SelectionContainer.disabled(child: viewer);
  }
}

class _ReviewAnnotationSidebar extends StatelessWidget {
  const _ReviewAnnotationSidebar({
    required this.annotations,
    required this.palette,
    required this.strings,
    required this.onOpen,
    required this.onOpenNote,
    required this.onEditNote,
    required this.onDelete,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelectionMode,
    required this.onToggleSelection,
    required this.onAddSelected,
    required this.tabIndex,
    required this.onTabChanged,
    required this.outline,
    required this.outlineLoading,
    required this.onOpenOutline,
  });

  final List<ReviewAnnotation> annotations;
  final AppPalette palette;
  final AppStrings strings;
  final ValueChanged<ReviewAnnotation> onOpen;
  final ValueChanged<ReviewAnnotation> onOpenNote;
  final ValueChanged<ReviewAnnotation> onEditNote;
  final ValueChanged<ReviewAnnotation> onDelete;
  final bool selectionMode;
  final Set<String> selectedIds;
  final VoidCallback onToggleSelectionMode;
  final ValueChanged<String> onToggleSelection;
  final VoidCallback onAddSelected;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final List<PdfOutlineNode> outline;
  final bool outlineLoading;
  final ValueChanged<PdfOutlineNode> onOpenOutline;

  Widget _outlineList(BuildContext context) {
    if (outlineLoading) {
      return Center(
        child: Text(
          strings.reviewOutlineLoading,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      );
    }
    if (outline.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            strings.reviewOutlineEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ),
      );
    }
    final rows = <({PdfOutlineNode node, int depth})>[];
    void walk(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        rows.add((node: node, depth: depth));
        walk(node.children, depth + 1);
      }
    }

    walk(outline, 0);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final enabled = row.node.dest != null;
        return InkWell(
          onTap: enabled ? () => onOpenOutline(row.node) : null,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8.0 + row.depth * 14, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: enabled ? palette.textSecondary : palette.divider,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.node.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? palette.textPrimary
                          : palette.textSecondary,
                    ),
                  ),
                ),
                if (row.node.dest != null)
                  Text(
                    '${row.node.dest!.pageNumber}',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...annotations]
      ..sort((a, b) {
        final page = a.pageNumber.compareTo(b.pageNumber);
        return page != 0 ? page : a.createdAt.compareTo(b.createdAt);
      });
    return ColoredBox(
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.highlight_alt, size: 17),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    strings.reviewAnnotations,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${annotations.length}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
                IconButton(
                  tooltip: selectionMode
                      ? strings.reviewClearHighlightSelection
                      : strings.reviewSelectHighlights,
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleSelectionMode,
                  icon: Icon(
                    selectionMode ? Icons.close : Icons.checklist,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => onTabChanged(0),
                    child: Text(
                      strings.reviewAnnotationsTab,
                      style: TextStyle(
                        fontWeight: tabIndex == 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: tabIndex == 0
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => onTabChanged(1),
                    child: Text(
                      strings.reviewOutlineTab,
                      style: TextStyle(
                        fontWeight: tabIndex == 1
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: tabIndex == 1
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selectionMode && tabIndex == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.reviewSelectedHighlights(selectedIds.length),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: selectedIds.isEmpty ? null : onAddSelected,
                    child: Text(strings.reviewAddSelectedHighlights),
                  ),
                ],
              ),
            ),
          Divider(height: 1, color: palette.divider),
          Expanded(
            child: tabIndex == 1
                ? _outlineList(context)
                : ordered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        strings.reviewAnnotationEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final annotation = ordered[index];
                      final selected = selectedIds.contains(annotation.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: palette.accent.withValues(alpha: 0.08),
                        onTap: selectionMode
                            ? () => onToggleSelection(annotation.id)
                            : () => onEditNote(annotation),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: palette.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (selectionMode) ...[
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) =>
                                          onToggleSelection(annotation.id),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: switch (annotation.color) {
                                        'green' => const Color(0xFF4CAF50),
                                        'pink' => const Color(0xFFE91E63),
                                        'blue' => const Color(0xFF2196F3),
                                        _ => const Color(0xFFFFC107),
                                      },
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: strings.reviewGoToPage,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () => onOpen(annotation),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          strings.reviewAnnotationPage(
                                            annotation.pageNumber,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: palette.textSecondary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (!selectionMode)
                                    IconButton(
                                      tooltip: strings.reviewAnnotationEdit,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => onEditNote(annotation),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  if (!selectionMode)
                                    PopupMenuButton<String>(
                                      tooltip: strings.moreActions,
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        size: 18,
                                      ),
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'open':
                                            onOpenNote(annotation);
                                          case 'edit':
                                            onEditNote(annotation);
                                          case 'delete':
                                            onDelete(annotation);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'open',
                                          child: Text(strings.reviewOpenNote),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text(
                                            strings.reviewAnnotationEdit,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(strings.commonDelete),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                annotation.text.trim().isEmpty
                                    ? strings.reviewAnnotationRegion
                                    : annotation.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (annotation.imagePath != null) ...[
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Image.file(
                                    File(annotation.imagePath!),
                                    height: 64,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const SizedBox(
                                      height: 22,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 3),
                              Text(
                                annotation.note.trim().isEmpty
                                    ? strings.reviewNoComment
                                    : annotation.note,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: palette.textSecondary,
                                      fontStyle: annotation.note.trim().isEmpty
                                          ? FontStyle.normal
                                          : FontStyle.italic,
                                    ),
                              ),
                              if (annotation.tags.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: [
                                    for (final tag in annotation.tags)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.surfaceAlt,
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                        ),
                                        child: Text(
                                          tag,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: palette.textSecondary,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectionHandlePainter extends CustomPainter {
  _SelectionHandlePainter(this.color, this.state);

  final Color color;
  final PdfViewerTextSelectionAnchorHandleState state;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = state == PdfViewerTextSelectionAnchorHandleState.normal
        ? 0.72
        : 1.0;
    if (state != PdfViewerTextSelectionAnchorHandleState.dragging) {
      canvas.drawCircle(
        center.translate(0, 2),
        8,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      );
    }
    canvas.drawCircle(
      center,
      7,
      Paint()..color = color.withValues(alpha: opacity),
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool hitTest(Offset position) => true;

  @override
  bool shouldRepaint(covariant _SelectionHandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.state != state;
}

/// Drag-to-select overlay used for image/formula/region annotations.
class _PdfRegionSelector extends StatefulWidget {
  const _PdfRegionSelector({
    required this.pageNumber,
    required this.color,
    required this.onSelected,
  });

  final int pageNumber;
  final Color color;
  final ValueChanged<Rect> onSelected;

  @override
  State<_PdfRegionSelector> createState() => _PdfRegionSelectorState();
}

class _PdfRegionSelectorState extends State<_PdfRegionSelector> {
  Offset? _start;
  Offset? _current;

  Offset _clamp(Offset point, Size size) =>
      Offset(point.dx.clamp(0.0, size.width), point.dy.clamp(0.0, size.height));

  Rect? _draft(Size size) {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return null;
    final rect = Rect.fromPoints(start, current);
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final draft = _draft(size);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              final point = _clamp(details.localPosition, size);
              setState(() {
                _start = point;
                _current = point;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _current = _clamp(details.localPosition, size);
              });
            },
            onPanEnd: (_) {
              final start = _start;
              final current = _current;
              setState(() {
                _start = null;
                _current = null;
              });
              if (start == null || current == null) return;
              final rect = Rect.fromPoints(start, current);
              if (rect.width < 4 || rect.height < 4) return;
              widget.onSelected(
                Rect.fromLTRB(
                  rect.left / size.width,
                  rect.top / size.height,
                  rect.right / size.width,
                  rect.bottom / size.height,
                ),
              );
            },
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Colors.transparent),
                ),
                if (draft != null)
                  Positioned.fromRect(
                    rect: draft,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.18),
                          border: Border.all(color: widget.color, width: 1.3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Direct manipulation for a region annotation: drag inside to move, or drag
/// the bottom-right handle to resize.
class _PdfRegionAdjustOverlay extends StatefulWidget {
  const _PdfRegionAdjustOverlay({
    required this.rect,
    required this.pageSize,
    required this.color,
    required this.onChanged,
    required this.onEnd,
    required this.onTap,
  });

  final Rect rect;
  final Size pageSize;
  final Color color;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<Rect> onEnd;
  final VoidCallback onTap;

  @override
  State<_PdfRegionAdjustOverlay> createState() =>
      _PdfRegionAdjustOverlayState();
}

class _PdfRegionAdjustOverlayState extends State<_PdfRegionAdjustOverlay> {
  Rect? _start;
  Offset? _startLocal;
  Rect? _latest;
  bool _resizing = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: (details) {
          _start = widget.rect;
          _startLocal = details.localPosition;
          _latest = widget.rect;
          final size = widget.pageSize;
          final local = details.localPosition;
          final width = widget.rect.width * size.width;
          final height = widget.rect.height * size.height;
          _resizing = local.dx >= width - 18 && local.dy >= height - 18;
        },
        onPanUpdate: (details) {
          final start = _start;
          final origin = _startLocal;
          if (start == null || origin == null) return;
          final delta = details.localPosition - origin;
          final dx = delta.dx / widget.pageSize.width;
          final dy = delta.dy / widget.pageSize.height;
          late final Rect next;
          if (_resizing) {
            final right = (start.right + dx).clamp(start.left + 0.01, 1.0);
            final bottom = (start.bottom + dy).clamp(start.top + 0.01, 1.0);
            next = Rect.fromLTRB(start.left, start.top, right, bottom);
          } else {
            final left = (start.left + dx).clamp(0.0, 1.0 - start.width);
            final top = (start.top + dy).clamp(0.0, 1.0 - start.height);
            next = Rect.fromLTWH(left, top, start.width, start.height);
          }
          _latest = next;
          widget.onChanged(next);
        },
        onPanEnd: (_) {
          final latest = _latest;
          _start = null;
          _startLocal = null;
          _latest = null;
          _resizing = false;
          if (latest != null) widget.onEnd(latest);
        },
        onPanCancel: () {
          _start = null;
          _startLocal = null;
          _latest = null;
          _resizing = false;
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    border: Border.all(color: widget.color, width: 1.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -6,
              bottom: -6,
              child: IgnorePointer(
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.color,
                    border: Border.all(color: Colors.white, width: 1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
