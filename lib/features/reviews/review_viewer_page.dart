import 'dart:async';

import 'package:flutter/material.dart';
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

  Future<void> _editNote(ReviewAnnotation annotation) async {
    await _ready;
    if (!mounted) return;
    final controller = TextEditingController(text: annotation.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppScope.of(context).strings.reviewAnnotationNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: AppScope.of(context).strings.reviewAnnotationNoteHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppScope.of(context).strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(AppScope.of(context).strings.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    final index = _annotations.indexWhere((item) => item.id == annotation.id);
    if (index < 0) return;
    final previous = _annotations[index];
    final notes = _notes;
    if (notes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.notesUnavailable)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ReviewAnnotationNotes.updateComment(notes, previous, note);
      if (!mounted) return;
      setState(() {
        _annotations = [..._annotations];
        _annotations[index] = ReviewAnnotation(
          id: previous.id,
          fileName: previous.fileName,
          pageNumber: previous.pageNumber,
          rects: previous.rects,
          text: previous.text,
          note: note,
          color: previous.color,
          createdAt: previous.createdAt,
          noteId: previous.noteId,
        );
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
    return widgets;
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
                    ? strings.reviewAnnotationEmpty
                    : annotation.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                strings.reviewAnnotationPage(annotation.pageNumber),
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
                unawaited(_editNote(annotation));
              },
            ),
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

  void _openAnnotationsSheet() {
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
            onEditNote: _editNote,
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
      appBar: AppBar(
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
              onSelected: (color) => setState(() => _highlightColor = color),
              itemBuilder: (context) => [
                for (final color in const ['yellow', 'green', 'pink', 'blue'])
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
                for (final color in const ['yellow', 'green', 'pink', 'blue'])
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (!_sidebarInitialized) {
            _sidebarInitialized = true;
            // A phone in landscape is wide but short; opening the 320 px
            // sidebar there leaves too little room for the page. Tablets and
            // desktops still get the inline sidebar.
            _showAnnotations =
                constraints.maxWidth >= 700 && constraints.maxHeight >= 500;
          }
          final sidebarWidth = constraints.maxWidth >= 720
              ? 320.0
              : (constraints.maxWidth * 0.45).clamp(160.0, 320.0);
          return SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PdfViewer.file(
                    widget.path,
                    key: ValueKey<String>('pdf-${widget.path}-$_pdfEpoch'),
                    controller: _controller,
                    params: PdfViewerParams(
                      onViewerReady: (document, controller) {
                        _pdfRetryTimer?.cancel();
                        _pdfReady = true;
                        if (widget.initialPage > 1) {
                          unawaited(
                            controller.goToPage(pageNumber: widget.initialPage),
                          );
                        }
                      },
                      pagePaintCallbacks: [_paintAnnotations],
                      pageOverlaysBuilder: _annotationOverlays,
                      textSelectionParams: PdfTextSelectionParams(
                        enabled: true,
                        buildSelectionHandle: _buildSelectionHandle,
                        onTextSelectionChange: _onTextSelectionChanged,
                        enableSelectionHandles: true,
                        onSelectionHandlePanStart: (_) =>
                            _autoHighlightTimer?.cancel(),
                      ),
                      customizeContextMenuItems: _customizePdfContextMenu,
                    ),
                  ),
                ),
                if (_showAnnotations) ...[
                  VerticalDivider(width: 1, color: palette.divider),
                  SizedBox(
                    width: sidebarWidth,
                    child: _ReviewAnnotationSidebar(
                      annotations: _annotations,
                      palette: palette,
                      strings: strings,
                      onOpen: (annotation) {
                        if (!_controller.isReady) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.reviewPdfLoading)),
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
                      onEditNote: _editNote,
                      onDelete: _deleteAnnotation,
                      selectionMode: _annotationSelectionMode,
                      selectedIds: _selectedAnnotationIds,
                      onToggleSelectionMode: _toggleAnnotationSelectionMode,
                      onToggleSelection: _toggleAnnotationSelected,
                      onAddSelected: _addSelectedAnnotationsToCollection,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
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
          if (selectionMode)
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
            child: ordered.isEmpty
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
                            : () => onOpen(annotation),
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
                                  Text(
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
                                  const Spacer(),
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
                                annotation.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (annotation.note.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  annotation.note,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: palette.textSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
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
