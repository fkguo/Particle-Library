import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../user/user_store.dart';
import '../../notes/notes_models.dart';
import '../common/resize_handle.dart';
import '../common/snack_bars.dart';
import '../notes/note_editor.dart';
import '../notes/note_tag_field.dart';
import '../notes/notes_format.dart';

const MethodChannel _clipboardChannel = MethodChannel('pdg.clipboard');

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
  PdfTextSearcher? _searcher;
  UserStore? _userStore;
  int? _currentPage;
  int? _restoredPage;
  final GlobalKey _pdfOverlayKey = GlobalKey();
  NotesStore? _notes;
  List<ReviewAnnotation> _annotations = const <ReviewAnnotation>[];
  bool _showAnnotations = true;
  bool _sidebarInitialized = false;
  bool _hadReadingState = false;
  bool _saving = false;
  bool _addingHighlight = false;
  bool _highlightMode = false;
  bool _annotationSelectionMode = false;
  bool _zenMode = false;
  bool _pdfDarkMode = false;
  bool _regionMode = false;
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _outlineLoading = false;
  int _sidebarTab = 0;
  double _sidebarWidth = 320;
  List<PdfOutlineNode> _outline = const <PdfOutlineNode>[];
  final Set<String> _selectedAnnotationIds = <String>{};
  String? _selectedAnnotationId;
  final Map<String, int> _regionVersions = <String, int>{};
  final List<_AnnotationHistoryEntry> _undoStack = <_AnnotationHistoryEntry>[];
  final List<_AnnotationHistoryEntry> _redoStack = <_AnnotationHistoryEntry>[];
  bool _applyingHistory = false;
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
    _persistReadingState();
    _searcher?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _autoHighlightTimer?.cancel();
    _pdfRetryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    _userStore = scope.store;
    final state = scope.store.reviewState(_fileName);
    if (state != null) {
      _hadReadingState = true;
      final width = state['sidebarWidth'];
      if (width is num) _sidebarWidth = width.toDouble().clamp(220, 560);
      final tab = state['sidebarTab'];
      if (tab is num) _sidebarTab = tab.toInt().clamp(0, 1);
      final page = state['page'];
      if (page is num) _restoredPage = page.toInt();
      _showAnnotations = state['showAnnotations'] != false;
      _pdfDarkMode = state['dark'] == true;
      _zenMode = state['zen'] == true;
    }
    _ready = _loadAnnotations(scope.notes);
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
          if (_selectedAnnotationId != null &&
              !visible.contains(_selectedAnnotationId)) {
            _selectedAnnotationId = null;
          }
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

  Future<void> _highlightButtonPressed() async {
    if (!_highlightMode &&
        _controller.isReady &&
        _controller.textSelectionDelegate.hasSelectedText) {
      await _highlightSelection();
      return;
    }
    _toggleHighlightMode();
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
      Object? failure;
      for (final item in selected) {
        try {
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
        } catch (error) {
          failure = error;
          break;
        }
      }
      if (!mounted) return;
      if (additions.isNotEmpty) {
        setState(() => _annotations = [...additions, ..._annotations]);
        _notifyNotesChanged();
        _offerAddToCollection(additions);
        final noteIds = [
          for (final annotation in additions)
            if (annotation.noteId != null) annotation.noteId!,
        ];
        if (noteIds.isNotEmpty) {
          _pushHistory(
            () async {
              for (final noteId in noteIds) {
                await _deleteAnnotationForHistory(noteId);
              }
            },
            () async {
              for (final noteId in noteIds) {
                await _restoreAnnotationForHistory(noteId);
              }
            },
          );
        }
      }
      if (failure != null && additions.length < selected.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppScope.of(context).strings.reviewHighlightsPartiallySaved(
                additions.length,
                selected.length,
              ),
            ),
          ),
        );
      }
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
      var start = -1;
      var end = -1;
      final text = pageText.fullText;
      if (quote.isNotEmpty) {
        double distanceAt(int index) {
          if (index < 0 || index >= pageText.charRects.length) {
            return double.infinity;
          }
          final rect = normalizePdfSelectionRect(
            pageText.charRects[index],
            page,
          );
          var best = double.infinity;
          for (final saved in annotation.rects) {
            final dx = rect.center.dx - saved.center.dx;
            final dy = rect.center.dy - saved.center.dy;
            final distance = dx * dx + dy * dy;
            if (distance < best) best = distance;
          }
          return best;
        }

        int? closest(List<int> candidates) {
          if (candidates.isEmpty) return null;
          var best = candidates.first;
          var bestDistance = distanceAt(best);
          for (final candidate in candidates.skip(1)) {
            final distance = distanceAt(candidate);
            if (distance < bestDistance) {
              bestDistance = distance;
              best = candidate;
            }
          }
          return best;
        }

        final exact = <int>[];
        for (
          var at = text.indexOf(quote);
          at >= 0;
          at = text.indexOf(quote, at + 1)
        ) {
          exact.add(at);
        }
        final exactStart = closest(exact);
        if (exactStart != null) {
          start = exactStart;
          end = (start + quote.length - 1).clamp(0, text.length - 1);
        } else {
          // Build a normalized string and an index map back to the original
          // text, so whitespace-collapsed matches keep the right offsets.
          final normalized = StringBuffer();
          final map = <int>[];
          var lastSpace = false;
          for (var i = 0; i < text.length; i++) {
            final ch = text[i];
            if (RegExp(r'\s').hasMatch(ch)) {
              if (!lastSpace) {
                normalized.write(' ');
                map.add(i);
                lastSpace = true;
              }
            } else {
              normalized.write(ch);
              map.add(i);
              lastSpace = false;
            }
          }
          final normalizedText = normalized.toString();
          final normalizedQuote = quote.replaceAll(RegExp(r'\s+'), ' ');
          final candidates = <int>[];
          for (
            var at = normalizedText.indexOf(normalizedQuote);
            at >= 0;
            at = normalizedText.indexOf(normalizedQuote, at + 1)
          ) {
            candidates.add(at);
          }
          final normalizedStart = closest([
            for (final at in candidates) map[at],
          ]);
          if (normalizedStart != null) {
            start = normalizedStart;
            final normalizedPosition = candidates.firstWhere(
              (at) => map[at] == normalizedStart,
              orElse: () => 0,
            );
            final lastNormalized =
                (normalizedPosition + normalizedQuote.length - 1).clamp(
                  0,
                  map.length - 1,
                );
            end = map[lastNormalized];
          }
        }
      }
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
        _pushHistory(
          () => _updateRangeForHistory(
            annotation.id,
            annotation.rects,
            annotation.text,
            annotation.imagePath,
            annotation.imageStale,
          ),
          () => _updateRangeForHistory(
            updated.id,
            updated.rects,
            updated.text,
            updated.imagePath,
            updated.imageStale,
          ),
        );
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

  void _selectAnnotation(ReviewAnnotation annotation) {
    setState(() => _selectedAnnotationId = annotation.id);
    if (_controller.isReady &&
        (_currentPage ?? _controller.pageNumber) != annotation.pageNumber) {
      unawaited(_controller.goToPage(pageNumber: annotation.pageNumber));
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

  Future<void> _removeAnnotationTag(
    ReviewAnnotation annotation,
    String tag,
  ) async {
    final notes = _notes;
    if (notes == null) return;
    final strings = AppScope.of(context).strings;
    try {
      await ReviewAnnotationNotes.updateComment(
        notes,
        annotation,
        annotation.note,
        tags: annotation.tags.where((item) => item != tag).toList(),
      );
      if (!mounted) return;
      final oldTags = annotation.tags;
      final newTags = annotation.tags
          .where((item) => item != tag)
          .toList(growable: false);
      await _loadAnnotations(notes);
      _notifyNotesChanged();
      _pushHistory(
        () => _updateDetailsForHistory(annotation.id, annotation.note, oldTags),
        () => _updateDetailsForHistory(annotation.id, annotation.note, newTags),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.notesSaveFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
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
    var knownTags = const <String>[];
    try {
      knownTags = (await notes.tagCounts(limit: 100)).keys.toList();
    } catch (_) {}
    if (!mounted) return;
    final comment = TextEditingController(text: annotation.note);
    final tags = TextEditingController(text: annotation.tags.join(', '));
    final result =
        await showModalBottomSheet<({String comment, List<String> tags})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheetContext) => Theme(
            data: _pdfDarkMode ? AppTheme.dark() : Theme.of(context),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
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
                          cacheWidth: 520,
                          fit: BoxFit.contain,
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
                    NoteTagField(
                      controller: tags,
                      knownTags: knownTags,
                      strings: strings,
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
                          onPressed: () {
                            Navigator.of(sheetContext).pop((
                              comment: comment.text.trim(),
                              tags: (parseNoteTags(tags.text)..sort()),
                            ));
                          },
                          child: Text(strings.commonSave),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    comment.dispose();
    tags.dispose();
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
      _notifyNotesChanged();
      final oldComment = annotation.note;
      final oldTags = annotation.tags;
      _pushHistory(
        () => _updateDetailsForHistory(annotation.id, oldComment, oldTags),
        () => _updateDetailsForHistory(
          annotation.id,
          result.comment,
          result.tags,
        ),
      );
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

  Future<void> _saveRegionImage(ReviewAnnotation annotation) async {
    final path = annotation.imagePath;
    if (path == null) return;
    final strings = AppScope.of(context).strings;
    try {
      final location = await getSaveLocation(
        suggestedName: path.split(RegExp(r'[\\/]')).last,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG', extensions: ['png']),
        ],
      );
      if (location == null) return;
      await File(path).copy(location.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.reviewImageSaved)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.reviewImageSaveFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
  }

  Future<void> _exportRegionMarkdown(ReviewAnnotation annotation) async {
    final source = annotation.imagePath;
    if (source == null || annotation.imageStale) return;
    final strings = AppScope.of(context).strings;
    try {
      final location = await getSaveLocation(
        suggestedName: 'annotation-${annotation.id}.md',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Markdown', extensions: ['md']),
        ],
      );
      if (location == null) return;
      final mdPath = location.path.toLowerCase().endsWith('.md')
          ? location.path
          : '${location.path}.md';
      final imagePath = mdPath.replaceFirst(RegExp(r'\.md$'), '.png');
      await File(source).copy(imagePath);
      final comment = annotation.note.trim();
      final body = StringBuffer(
        '![Region](${imagePath.split(RegExp(r'[\\/]')).last})\n',
      );
      if (comment.isNotEmpty) {
        body
          ..writeln()
          ..writeln(comment);
      }
      await File(mdPath).writeAsString(body.toString(), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.reviewImageSaved)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.reviewImageSaveFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
  }

  Future<void> _copyRegionImage(ReviewAnnotation annotation) async {
    final path = annotation.imagePath;
    if (path == null || annotation.imageStale) return;
    final strings = AppScope.of(context).strings;
    try {
      await _clipboardChannel.invokeMethod<bool>('copyImage', {'path': path});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.reviewImageCopied)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.reviewImageCopyFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
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
      if (_selectedAnnotationId == annotation.id) {
        _selectedAnnotationId = null;
      }
      final noteId = annotation.noteId;
      if (noteId != null) {
        _pushHistory(
          () => _restoreAnnotationForHistory(noteId),
          () => _deleteAnnotationForHistory(noteId),
        );
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

  bool _onPdfGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.secondaryTap) {
      return false;
    }
    if (!_controller.isReady ||
        !_controller.textSelectionDelegate.hasSelectedText) {
      return true; // Never fall through to the built-in Copy/Select All menu.
    }
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return false;
    final global = renderBox.localToGlobal(details.localPosition);
    unawaited(_showTextSelectionMenu(global));
    return true;
  }

  Future<void> _showTextSelectionMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final strings = AppScope.of(context).strings;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 17),
              const SizedBox(width: 8),
              Text(strings.commonCopy),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'highlight',
          child: Row(
            children: [
              const Icon(Icons.highlight_alt, size: 17),
              const SizedBox(width: 8),
              Text(strings.reviewHighlight),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'highlight') {
      await _highlightSelection();
      return;
    }
    try {
      final text = await _controller.textSelectionDelegate.getSelectedText();
      if (text.trim().isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.commonCopied)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.commonCopyFailed)));
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
      final imagePath = await _renderRegionImage(pageNumber, rect);
      final created = await ReviewAnnotationNotes.create(
        notes,
        fileName: _fileName,
        pageNumber: pageNumber,
        rects: <Rect>[rect],
        text: '',
        color: _highlightColor,
        reviewTitle: widget.title,
        imagePath: imagePath,
        imageStale: imagePath == null,
      );
      if (!mounted) return;
      setState(() {
        _annotations = [created, ..._annotations];
        _regionMode = false;
      });
      _notifyNotesChanged();
      _offerAddToCollection([created]);
      final noteId = created.noteId;
      if (noteId != null) {
        _pushHistory(
          () => _deleteAnnotationForHistory(noteId),
          () => _restoreAnnotationForHistory(noteId),
        );
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
      if (mounted) setState(() => _addingHighlight = false);
    }
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    if (_pdfDarkMode) return; // Dark mode paints annotations above the filter.
    for (final annotation in _annotations) {
      if (annotation.pageNumber != page.pageNumber) continue;
      final paint = Paint()
        ..color = _annotationColor(annotation.color).withValues(alpha: 0.38);
      for (final rect in mergeRectsForDisplay(annotation.rects)) {
        final target = Rect.fromLTWH(
          pageRect.left + rect.left * pageRect.width,
          pageRect.top + rect.top * pageRect.height,
          rect.width * pageRect.width,
          rect.height * pageRect.height,
        );
        canvas.drawRect(target, paint);
        if (annotation.id == _selectedAnnotationId &&
            annotation.text.trim().isEmpty) {
          canvas.drawRect(
            target,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = _annotationColor(annotation.color),
          );
        }
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
              selected: _selectedAnnotationId == annotation.id,
              onTap: () => _selectAnnotation(annotation),
              onDoubleTap: () => unawaited(_editAnnotation(annotation)),
              onLongPress: () => unawaited(_showAnnotationActions(annotation)),
              onContextMenu: (position) =>
                  unawaited(_showAnnotationContextMenu(annotation, position)),
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
                _selectAnnotation(annotation);
                unawaited(_beginAdjustRange(annotation));
                return true;
              },
              onDoubleTap: (_) {
                unawaited(_editAnnotation(annotation));
                return true;
              },
              onSecondaryTap: (details) {
                if (defaultTargetPlatform == TargetPlatform.macOS ||
                    defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.linux) {
                  unawaited(
                    _showAnnotationContextMenu(
                      annotation,
                      details.globalPosition,
                    ),
                  );
                } else {
                  unawaited(_showAnnotationActions(annotation));
                }
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
      imageStale: annotation.imageStale,
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

  Future<void> _refreshRegionImage(ReviewAnnotation annotation) async {
    final notes = _notes;
    if (notes == null) return;
    final rect = annotation.rects.first;
    final strings = AppScope.of(context).strings;
    final imagePath = await _renderRegionImage(annotation.pageNumber, rect);
    if (!mounted) return;
    if (imagePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.reviewRegionRetryFailed)));
      return;
    }
    try {
      final updated = await ReviewAnnotationNotes.updateRange(
        notes,
        annotation,
        rects: <Rect>[rect],
        text: '',
        imagePath: imagePath,
        imageStale: false,
      );
      if (!mounted || updated == null) return;
      setState(() {
        _annotations = [
          for (final item in _annotations)
            if (item.id == updated.id) updated else item,
        ];
      });
      _notifyNotesChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.reviewRegionRetrySucceeded)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.reviewRegionRetryFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
  }

  Future<void> _persistRegion(String id, Rect rect) async {
    final notes = _notes;
    if (notes == null) return;
    final index = _annotations.indexWhere((annotation) => annotation.id == id);
    if (index < 0) return;
    final annotation = _annotations[index];
    final version = (_regionVersions[id] ?? 0) + 1;
    _regionVersions[id] = version;
    try {
      final imagePath = await _renderRegionImage(annotation.pageNumber, rect);
      if (!mounted || _regionVersions[id] != version) return;
      final updated = await ReviewAnnotationNotes.updateRange(
        notes,
        annotation,
        rects: <Rect>[rect],
        text: '',
        imagePath: imagePath,
        imageStale: imagePath == null,
      );
      if (!mounted || _regionVersions[id] != version) return;
      if (updated == null) return;
      if (imagePath == null && annotation.imagePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppScope.of(context).strings.reviewRegionImageRefreshFailed,
            ),
          ),
        );
      }
      setState(() {
        _annotations = [
          for (final item in _annotations)
            if (item.id == updated.id) updated else item,
        ];
      });
      _notifyNotesChanged();
      _pushHistory(
        () => _updateRangeForHistory(
          id,
          annotation.rects,
          annotation.text,
          annotation.imagePath,
          annotation.imageStale,
        ),
        () => _updateRangeForHistory(
          id,
          updated.rects,
          updated.text,
          updated.imagePath,
          updated.imageStale,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _loadAnnotations(notes);
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

  void _pushHistory(
    Future<void> Function() undo,
    Future<void> Function() redo,
  ) {
    if (_applyingHistory) return;
    _undoStack.add(_AnnotationHistoryEntry(undo: undo, redo: redo));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
    setState(() {});
  }

  Future<void> _reloadAfterHistory() async {
    final notes = _notes;
    if (notes != null) await _loadAnnotations(notes);
    if (mounted) _notifyNotesChanged();
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    setState(() => _applyingHistory = true);
    try {
      await entry.undo();
      _redoStack.add(entry);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppScope.of(context).strings.commonUndo}: ${errorText(error, AppScope.of(context).strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingHistory = false);
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    setState(() => _applyingHistory = true);
    try {
      await entry.redo();
      _undoStack.add(entry);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppScope.of(context).strings.commonRedo}: ${errorText(error, AppScope.of(context).strings)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingHistory = false);
    }
  }

  Future<void> _restoreAnnotationForHistory(String? noteId) async {
    final notes = _notes;
    if (notes == null || noteId == null) return;
    await notes.restore(noteId);
    await _reloadAfterHistory();
  }

  Future<void> _deleteAnnotationForHistory(String? noteId) async {
    final notes = _notes;
    if (notes == null || noteId == null) return;
    await notes.delete(noteId);
    await _reloadAfterHistory();
  }

  Future<void> _updateDetailsForHistory(
    String annotationId,
    String comment,
    List<String> tags,
  ) async {
    final notes = _notes;
    if (notes == null) return;
    final current = _annotations.firstWhere(
      (annotation) => annotation.id == annotationId,
    );
    await ReviewAnnotationNotes.updateComment(
      notes,
      current,
      comment,
      tags: tags,
    );
    await _reloadAfterHistory();
  }

  Future<void> _updateRangeForHistory(
    String annotationId,
    List<Rect> rects,
    String text,
    String? imagePath,
    bool imageStale,
  ) async {
    final notes = _notes;
    if (notes == null) return;
    final current = _annotations.firstWhere(
      (annotation) => annotation.id == annotationId,
    );
    await ReviewAnnotationNotes.updateRange(
      notes,
      current,
      rects: rects,
      text: text,
      imagePath: imagePath,
      imageStale: imageStale,
    );
    await _reloadAfterHistory();
  }

  Future<void> _showAnnotationContextMenu(
    ReviewAnnotation annotation,
    Offset globalPosition,
  ) async {
    setState(() => _selectedAnnotationId = annotation.id);
    // pdfrx also owns a text-selection context menu. Clear its selection
    // before opening the annotation menu so the user does not get two menus.
    if (_controller.isReady) {
      await _controller.textSelectionDelegate.clearTextSelection();
    }
    if (!mounted) return;
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final strings = AppScope.of(context).strings;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 17),
              const SizedBox(width: 8),
              Text(strings.reviewAnnotationEdit),
            ],
          ),
        ),
        if (annotation.text.trim().isNotEmpty)
          PopupMenuItem(
            value: 'range',
            child: Row(
              children: [
                const Icon(Icons.open_with_outlined, size: 17),
                const SizedBox(width: 8),
                Text(strings.reviewAdjustRange),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'note',
          child: Row(
            children: [
              const Icon(Icons.note_alt_outlined, size: 17),
              const SizedBox(width: 8),
              Text(strings.reviewOpenNote),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'page',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 17),
              const SizedBox(width: 8),
              Text(strings.reviewGoToPage),
            ],
          ),
        ),
        if (annotation.imagePath != null && !annotation.imageStale) ...[
          PopupMenuItem(
            value: 'save',
            child: Row(
              children: [
                const Icon(Icons.save_alt_outlined, size: 17),
                const SizedBox(width: 8),
                Text(strings.reviewSaveImage),
              ],
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.macOS)
            PopupMenuItem(
              value: 'copy',
              child: Row(
                children: [
                  const Icon(Icons.copy_all_outlined, size: 17),
                  const SizedBox(width: 8),
                  Text(strings.reviewCopyImage),
                ],
              ),
            ),
        ],
        if (annotation.imageStale)
          PopupMenuItem(
            value: 'retry',
            child: Row(
              children: [
                const Icon(Icons.refresh, size: 17),
                const SizedBox(width: 8),
                Text(strings.reviewRegionRetryImage),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 17,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                strings.commonDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editAnnotation(annotation);
      case 'range':
        await _beginAdjustRange(annotation);
      case 'note':
        await _openAnnotationNote(annotation);
      case 'page':
        if (_controller.isReady) {
          await _controller.goToPage(pageNumber: annotation.pageNumber);
        }
      case 'save':
        await _saveRegionImage(annotation);
      case 'copy':
        await _copyRegionImage(annotation);
      case 'retry':
        await _refreshRegionImage(annotation);
      case 'delete':
        await _deleteAnnotation(annotation);
    }
  }

  Future<void> _showAnnotationActions(ReviewAnnotation annotation) async {
    final strings = AppScope.of(context).strings;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Theme(
        data: _pdfDarkMode ? AppTheme.dark() : Theme.of(context),
        child: SafeArea(
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
                      cacheWidth: 480,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (annotation.imageStale)
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.orange),
                  title: Text(strings.reviewRegionRetryImage),
                  subtitle: Text(strings.reviewRegionImageStale),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_refreshRegionImage(annotation));
                  },
                ),
              if (annotation.imagePath != null && !annotation.imageStale)
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: Text(strings.reviewSaveImage),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_saveRegionImage(annotation));
                  },
                ),
              if (defaultTargetPlatform == TargetPlatform.macOS &&
                  annotation.imagePath != null &&
                  !annotation.imageStale)
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: Text(strings.reviewCopyImage),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_copyRegionImage(annotation));
                  },
                ),
              if (annotation.imagePath != null && !annotation.imageStale)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(strings.reviewExportRegionMarkdown),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_exportRegionMarkdown(annotation));
                  },
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

  void _toggleSearch() {
    if (_searchOpen) {
      _closeSearch();
      return;
    }
    if (_searcher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppScope.of(context).strings.reviewPdfLoading)),
      );
      return;
    }
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searcher?.resetTextSearch();
    _searchController.clear();
    setState(() => _searchOpen = false);
  }

  Widget _searchBar(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final searcher = _searcher;
    if (searcher == null) return const SizedBox.shrink();
    return Material(
      color: context.palette.surface,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.palette.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: strings.reviewSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 17),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  if (value.trim().isEmpty) {
                    searcher.resetTextSearch();
                  } else {
                    searcher.startTextSearch(value, searchImmediately: true);
                  }
                },
              ),
            ),
            AnimatedBuilder(
              animation: searcher,
              builder: (context, _) {
                final count = searcher.matches.length;
                final current = searcher.currentIndex;
                final total = searcher.totalPageCount;
                final page = searcher.searchingPageNumber;
                final label =
                    searcher.isSearching && total != null && page != null
                    ? strings.reviewMatchProgress(count, page, total)
                    : count == 0
                    ? strings.reviewNoMatches
                    : '${current == null ? 0 : current + 1}/$count';
                return Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.palette.textSecondary),
                );
              },
            ),
            IconButton(
              tooltip: strings.reviewPreviousMatch,
              onPressed: () => unawaited(searcher.goToPrevMatch()),
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            ),
            IconButton(
              tooltip: strings.reviewNextMatch,
              onPressed: () => unawaited(searcher.goToNextMatch()),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            ),
            IconButton(
              tooltip: strings.commonClose,
              onPressed: _closeSearch,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPageDialog() async {
    if (!_controller.isReady) return;
    final strings = AppScope.of(context).strings;
    final controller = TextEditingController(
      text: '${_currentPage ?? _controller.pageNumber ?? 1}',
    );
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.reviewPageNumber),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(int.tryParse(controller.text)),
            child: Text(strings.commonGo),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || !mounted) return;
    if (page < 1 || page > _controller.pageCount) return;
    await _controller.goToPage(pageNumber: page);
  }

  void _fitPage(String mode) {
    if (!_controller.isReady) return;
    final page = _controller.pageNumber ?? _currentPage ?? 1;
    final matrix = mode == 'width'
        ? _controller.calcMatrixFitWidthForPage(pageNumber: page)
        : _controller.calcMatrixForFit(pageNumber: page);
    if (matrix != null) _controller.value = matrix;
  }

  bool _annotationSheetOnly(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < 700 || size.height < 500;
  }

  void _openAnnotationsSheet({int tab = 0}) {
    setState(() => _sidebarTab = tab);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Theme(
        data: _pdfDarkMode ? AppTheme.dark() : Theme.of(context),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: _ReviewAnnotationSidebar(
              annotations: _annotations,
              palette: _pdfDarkMode ? AppPalette.dark : context.palette,
              strings: AppScope.of(context).strings,
              onOpen: (annotation) {
                Navigator.of(context).pop();
                if (_controller.isReady) {
                  unawaited(
                    _controller.goToPage(pageNumber: annotation.pageNumber),
                  );
                }
              },
              onOpenNote: (annotation) {
                Navigator.of(sheetContext).pop();
                unawaited(_openAnnotationNote(annotation));
              },
              onEditNote: (annotation) {
                Navigator.of(sheetContext).pop();
                unawaited(_editAnnotation(annotation));
              },
              onDelete: (annotation) {
                Navigator.of(sheetContext).pop();
                unawaited(_deleteAnnotation(annotation));
              },
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
              onRemoveTag: (annotation, tag) {
                Navigator.of(sheetContext).pop();
                unawaited(_removeAnnotationTag(annotation, tag));
              },
              onContextMenu: (annotation, position) =>
                  unawaited(_showAnnotationContextMenu(annotation, position)),
              selectedId: _selectedAnnotationId,
              onSelect: _selectAnnotation,
              onAdjustRange: (annotation) =>
                  unawaited(_beginAdjustRange(annotation)),
              onShowActions: (annotation) =>
                  unawaited(_showAnnotationActions(annotation)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _pdfDarkMode ? AppPalette.dark : context.palette;
    final strings = AppScope.of(context).strings;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final sheetOnly = _annotationSheetOnly(context);
    return Theme(
      data: _pdfDarkMode ? AppTheme.dark() : Theme.of(context),
      child: Scaffold(
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
                    tooltip: strings.commonUndo,
                    onPressed: _undoStack.isEmpty
                        ? null
                        : () => unawaited(_undo()),
                    icon: const Icon(Icons.undo, size: 19),
                  ),
                  IconButton(
                    tooltip: strings.commonRedo,
                    onPressed: _redoStack.isEmpty
                        ? null
                        : () => unawaited(_redo()),
                    icon: const Icon(Icons.redo, size: 19),
                  ),
                  IconButton(
                    tooltip: strings.reviewSearch,
                    onPressed: _toggleSearch,
                    icon: const Icon(Icons.search, size: 19),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_openPageDialog()),
                    child: Text(
                      '${_currentPage ?? 1}/${_controller.isReady ? _controller.pageCount : '—'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: strings.reviewFitWidth,
                    icon: const Icon(Icons.fit_screen, size: 19),
                    onSelected: _fitPage,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'width',
                        child: Text(strings.reviewFitWidth),
                      ),
                      PopupMenuItem(
                        value: 'page',
                        child: Text(strings.reviewFitPage),
                      ),
                    ],
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
                    tooltip: strings.reviewFullScreen,
                    onPressed: () => setState(() => _zenMode = true),
                    icon: const Icon(Icons.fullscreen, size: 20),
                  ),
                  IconButton(
                    tooltip: strings.reviewOutlineTab,
                    onPressed: () {
                      if (sheetOnly) {
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
                      tooltip: strings.commonClose,
                      onPressed: () {
                        _autoHighlightTimer?.cancel();
                        setState(() => _editingRange = null);
                        unawaited(
                          _controller.textSelectionDelegate
                              .clearTextSelection(),
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
                        : () => unawaited(_highlightButtonPressed()),
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
                        if (sheetOnly) {
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
        body: Column(
          children: [
            if (_searchOpen) _searchBar(context),
            Expanded(
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (!_sidebarInitialized) {
                        _sidebarInitialized = true;
                        if (!_hadReadingState) {
                          // A phone in landscape is wide but short; opening the 320 px
                          // sidebar there leaves too little room for the page. Tablets and
                          // desktops still get the inline sidebar.
                          _showAnnotations =
                              constraints.maxWidth >= 700 &&
                              constraints.maxHeight >= 500;
                        }
                      }
                      final maxSidebar = (constraints.maxWidth - 260).clamp(
                        220.0,
                        560.0,
                      );
                      final sidebarWidth = _sidebarWidth.clamp(
                        220.0,
                        maxSidebar,
                      );
                      return SafeArea(
                        top: false,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: RepaintBoundary(
                                child: _pdfSurfaceWithOverlay(context),
                              ),
                            ),
                            if (_showAnnotations &&
                                !_zenMode &&
                                constraints.maxWidth >= 700 &&
                                constraints.maxHeight >= 500) ...[
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
                                onReset: () =>
                                    setState(() => _sidebarWidth = 320),
                                child: RepaintBoundary(
                                  child: _ReviewAnnotationSidebar(
                                    annotations: _annotations,
                                    palette: palette,
                                    strings: strings,
                                    onOpen: (annotation) {
                                      if (!_controller.isReady) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  strings.reviewPdfLoading,
                                                ),
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
                                    onToggleSelectionMode:
                                        _toggleAnnotationSelectionMode,
                                    onToggleSelection:
                                        _toggleAnnotationSelected,
                                    onAddSelected:
                                        _addSelectedAnnotationsToCollection,
                                    tabIndex: _sidebarTab,
                                    onTabChanged: (index) =>
                                        setState(() => _sidebarTab = index),
                                    outline: _outline,
                                    outlineLoading: _outlineLoading,
                                    onOpenOutline: _openOutline,
                                    onRemoveTag: (annotation, tag) => unawaited(
                                      _removeAnnotationTag(annotation, tag),
                                    ),
                                    onContextMenu: (annotation, position) =>
                                        unawaited(
                                          _showAnnotationContextMenu(
                                            annotation,
                                            position,
                                          ),
                                        ),
                                    selectedId: _selectedAnnotationId,
                                    onSelect: _selectAnnotation,
                                    onAdjustRange: (annotation) => unawaited(
                                      _beginAdjustRange(annotation),
                                    ),
                                    onShowActions: (annotation) => unawaited(
                                      _showAnnotationActions(annotation),
                                    ),
                                  ),
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
            ),
          ],
        ),
      ),
    );
  }

  void _persistReadingState() {
    final store = _userStore;
    if (store == null) return;
    unawaited(
      store.setReviewState(_fileName, <String, Object?>{
        'page': _currentPage ?? _controller.pageNumber ?? 1,
        'sidebarWidth': _sidebarWidth,
        'sidebarTab': _sidebarTab,
        'showAnnotations': _showAnnotations,
        'dark': _pdfDarkMode,
        'zen': _zenMode,
      }),
    );
  }

  Widget _pdfSurfaceWithOverlay(BuildContext context) {
    final surface = _pdfSurface(context);
    if (!_pdfDarkMode) return surface;
    return Stack(
      children: [
        Positioned.fill(child: surface),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: _pdfOverlayKey,
              painter: _PdfAnnotationScreenPainter(
                controller: _controller,
                annotations: _annotations,
                selectedId: _selectedAnnotationId,
                overlayKey: _pdfOverlayKey,
                colorOf: _annotationColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pdfSurface(BuildContext context) {
    Widget viewer = PdfViewer.file(
      widget.path,
      key: ValueKey<String>('pdf-${widget.path}-$_pdfEpoch'),
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: _pdfDarkMode
            ? Colors.white
            : context.palette.background,
        onViewerReady: (document, controller) {
          _pdfRetryTimer?.cancel();
          _pdfReady = true;
          _searcher ??= PdfTextSearcher(_controller);
          _currentPage = _controller.pageNumber;
          unawaited(_loadOutline(document));
          final targetPage = _restoredPage ?? widget.initialPage;
          if (targetPage > 1) {
            unawaited(controller.goToPage(pageNumber: targetPage));
          }
        },
        pagePaintCallbacks: [
          _paintAnnotations,
          (canvas, pageRect, page) =>
              _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page),
        ],
        pageOverlaysBuilder: _annotationOverlays,
        textSelectionParams: PdfTextSelectionParams(
          enabled: !_regionMode,
          showContextMenuAutomatically: false,
          buildSelectionHandle: _buildSelectionHandle,
          onTextSelectionChange: _onTextSelectionChanged,
          enableSelectionHandles:
              defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android ||
              _editingRange != null,
          onSelectionHandlePanStart: (_) => _autoHighlightTimer?.cancel(),
          onSelectionHandlePanEnd: (_) {
            if (_editingRange != null) unawaited(_saveAdjustedRange());
          },
        ),
        customizeContextMenuItems: _customizePdfContextMenu,
        onGeneralTap: _onPdfGeneralTap,
        onPageChanged: (page) {
          if (!mounted || page == null) return;
          setState(() => _currentPage = page);
        },
      ),
    );
    if (_pdfDarkMode) {
      // Luminance inversion: paper becomes AppPalette.dark.background, ink
      // becomes textPrimary, but chroma is kept so a yellow highlight stays
      // yellow instead of turning blue. Each channel is solved independently
      // for white->background and black->foreground.
      final paper = AppPalette.dark.surface;
      final ink = AppPalette.dark.textPrimary;
      final rows = <double>[];
      for (final (bg, fg) in [
        (paper.r, ink.r),
        (paper.g, ink.g),
        (paper.b, ink.b),
      ]) {
        final slope = (255 + fg * 255 - bg * 255) / 255;
        final offDiagonal = -slope / 3;
        final diagonal = 1 + offDiagonal;
        rows.addAll([diagonal, offDiagonal, offDiagonal, 0, fg * 255]);
      }
      viewer = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          ...rows.sublist(0, 5),
          ...rows.sublist(5, 10),
          ...rows.sublist(10, 15),
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

class _ReviewAnnotationSidebar extends StatefulWidget {
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
    required this.onRemoveTag,
    required this.onContextMenu,
    required this.selectedId,
    required this.onSelect,
    required this.onAdjustRange,
    required this.onShowActions,
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
  final void Function(ReviewAnnotation annotation, String tag) onRemoveTag;
  final void Function(ReviewAnnotation annotation, Offset position)
  onContextMenu;
  final String? selectedId;
  final ValueChanged<ReviewAnnotation> onSelect;
  final ValueChanged<ReviewAnnotation> onAdjustRange;
  final ValueChanged<ReviewAnnotation> onShowActions;

  @override
  State<_ReviewAnnotationSidebar> createState() =>
      _ReviewAnnotationSidebarState();
}

class _ReviewAnnotationSidebarState extends State<_ReviewAnnotationSidebar> {
  final TextEditingController _filterController = TextEditingController();
  String? _colorFilter;
  String? _tagFilter;

  List<ReviewAnnotation> get annotations => widget.annotations;
  AppPalette get palette => widget.palette;
  AppStrings get strings => widget.strings;
  ValueChanged<ReviewAnnotation> get onOpen => widget.onOpen;
  ValueChanged<ReviewAnnotation> get onOpenNote => widget.onOpenNote;
  ValueChanged<ReviewAnnotation> get onEditNote => widget.onEditNote;
  ValueChanged<ReviewAnnotation> get onDelete => widget.onDelete;
  bool get selectionMode => widget.selectionMode;
  Set<String> get selectedIds => widget.selectedIds;
  VoidCallback get onToggleSelectionMode => widget.onToggleSelectionMode;
  ValueChanged<String> get onToggleSelection => widget.onToggleSelection;
  VoidCallback get onAddSelected => widget.onAddSelected;
  int get tabIndex => widget.tabIndex;
  ValueChanged<int> get onTabChanged => widget.onTabChanged;
  List<PdfOutlineNode> get outline => widget.outline;
  bool get outlineLoading => widget.outlineLoading;
  ValueChanged<PdfOutlineNode> get onOpenOutline => widget.onOpenOutline;
  void Function(ReviewAnnotation, String) get onRemoveTag => widget.onRemoveTag;
  void Function(ReviewAnnotation, Offset) get onContextMenu =>
      widget.onContextMenu;
  String? get selectedId => widget.selectedId;
  ValueChanged<ReviewAnnotation> get onSelect => widget.onSelect;
  ValueChanged<ReviewAnnotation> get onAdjustRange => widget.onAdjustRange;
  ValueChanged<ReviewAnnotation> get onShowActions => widget.onShowActions;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Color _annotationColorForLabel(String color) => switch (color) {
    'green' => const Color(0xFF4CAF50),
    'pink' => const Color(0xFFE91E63),
    'blue' => const Color(0xFF2196F3),
    _ => const Color(0xFFFFC107),
  };

  List<ReviewAnnotation> _filteredAnnotations() {
    final query = _filterController.text.trim().toLowerCase();
    return annotations
        .where((annotation) {
          if (_colorFilter != null && annotation.color != _colorFilter) {
            return false;
          }
          if (_tagFilter != null && !annotation.tags.contains(_tagFilter)) {
            return false;
          }
          if (query.isNotEmpty &&
              !annotation.text.toLowerCase().contains(query) &&
              !annotation.note.toLowerCase().contains(query) &&
              !annotation.tags.any(
                (tag) => tag.toLowerCase().contains(query),
              )) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool get _hasFilter =>
      _filterController.text.trim().isNotEmpty ||
      _colorFilter != null ||
      _tagFilter != null;

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
    final ordered = [..._filteredAnnotations()]
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
                  _hasFilter
                      ? '${ordered.length}/${annotations.length}'
                      : '${annotations.length}',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: TextField(
              controller: _filterController,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.reviewFilterHint,
                prefixIcon: const Icon(Icons.filter_alt_outlined, size: 16),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 20,
                ),
                suffixIcon: _hasFilter
                    ? IconButton(
                        tooltip: strings.reviewFilterClear,
                        onPressed: () => setState(() {
                          _filterController.clear();
                          _colorFilter = null;
                          _tagFilter = null;
                        }),
                        icon: const Icon(Icons.close, size: 16),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: strings.reviewFilterColor,
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    onSelected: (value) => setState(
                      () => _colorFilter = value == 'all' ? null : value,
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'all',
                        child: Text(strings.reviewFilterAllColors),
                      ),
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
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _annotationColorForLabel(color),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(strings.reviewHighlightColorName(color)),
                            ],
                          ),
                        ),
                    ],
                    child: _FilterMenuLabel(
                      icon: Icons.palette_outlined,
                      label: _colorFilter == null
                          ? strings.reviewFilterColor
                          : strings.reviewHighlightColorName(_colorFilter!),
                      active: _colorFilter != null,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: strings.reviewFilterTag,
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    onSelected: (value) => setState(
                      () => _tagFilter = value == 'all' ? null : value,
                    ),
                    itemBuilder: (context) {
                      final tags = {
                        for (final annotation in annotations)
                          ...annotation.tags,
                      }.toList()..sort();
                      return [
                        PopupMenuItem(
                          value: 'all',
                          child: Text(strings.reviewFilterAllTags),
                        ),
                        for (final tag in tags)
                          PopupMenuItem(value: tag, child: Text(tag)),
                      ];
                    },
                    child: _FilterMenuLabel(
                      icon: Icons.sell_outlined,
                      label: _tagFilter ?? strings.reviewFilterTag,
                      active: _tagFilter != null,
                    ),
                  ),
                ),
                if (_hasFilter)
                  IconButton(
                    tooltip: strings.reviewFilterClear,
                    onPressed: () => setState(() {
                      _filterController.clear();
                      _colorFilter = null;
                      _tagFilter = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
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
                      return GestureDetector(
                        onSecondaryTapDown: (details) =>
                            onContextMenu(annotation, details.globalPosition),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          hoverColor: palette.accent.withValues(alpha: 0.08),
                          onTapDown: selectionMode
                              ? null
                              : (_) => onSelect(annotation),
                          onTap: selectionMode
                              ? () => onToggleSelection(annotation.id)
                              : () => onSelect(annotation),
                          onDoubleTap: selectionMode
                              ? null
                              : () => onEditNote(annotation),
                          onLongPress: selectionMode
                              ? null
                              : () => onShowActions(annotation),
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
                                      cacheWidth: 320,
                                      fit: BoxFit.contain,
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
                                if (annotation.imageStale) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    strings.reviewRegionImageStale,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.orange),
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
                                        fontStyle:
                                            annotation.note.trim().isEmpty
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
                                        InputChip(
                                          label: Text(tag),
                                          onDeleted: () =>
                                              onRemoveTag(annotation, tag),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
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
enum _RegionHandle {
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class _PdfRegionAdjustOverlay extends StatefulWidget {
  const _PdfRegionAdjustOverlay({
    required this.rect,
    required this.pageSize,
    required this.color,
    required this.onChanged,
    required this.onEnd,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onContextMenu,
    required this.selected,
  });

  final Rect rect;
  final Size pageSize;
  final Color color;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<Rect> onEnd;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final ValueChanged<Offset> onContextMenu;
  final bool selected;

  @override
  State<_PdfRegionAdjustOverlay> createState() =>
      _PdfRegionAdjustOverlayState();
}

class _PdfRegionAdjustOverlayState extends State<_PdfRegionAdjustOverlay> {
  static const double _minSize = 0.008;
  Rect? _start;
  Offset? _startLocal;
  Rect? _latest;
  _RegionHandle _handle = _RegionHandle.move;
  MouseCursor _cursor = SystemMouseCursors.move;

  _RegionHandle _hitTest(Offset point, Size size) {
    final edge = size.width < 32 || size.height < 32 ? 10.0 : 16.0;
    final nearLeft = point.dx <= edge;
    final nearRight = point.dx >= size.width - edge;
    final nearTop = point.dy <= edge;
    final nearBottom = point.dy >= size.height - edge;
    if (nearTop && nearLeft) return _RegionHandle.topLeft;
    if (nearTop && nearRight) return _RegionHandle.topRight;
    if (nearBottom && nearLeft) return _RegionHandle.bottomLeft;
    if (nearBottom && nearRight) return _RegionHandle.bottomRight;
    if (nearTop) return _RegionHandle.top;
    if (nearBottom) return _RegionHandle.bottom;
    if (nearLeft) return _RegionHandle.left;
    if (nearRight) return _RegionHandle.right;
    return _RegionHandle.move;
  }

  MouseCursor _cursorFor(_RegionHandle handle) => switch (handle) {
    _RegionHandle.topLeft ||
    _RegionHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    _RegionHandle.topRight ||
    _RegionHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    _RegionHandle.top ||
    _RegionHandle.bottom => SystemMouseCursors.resizeUpDown,
    _RegionHandle.left ||
    _RegionHandle.right => SystemMouseCursors.resizeLeftRight,
    _RegionHandle.move => SystemMouseCursors.move,
  };

  Rect _updatedRect(Offset delta) {
    final start = _start ?? widget.rect;
    final dx = delta.dx / widget.pageSize.width;
    final dy = delta.dy / widget.pageSize.height;
    if (_handle == _RegionHandle.move) {
      final left = (start.left + dx).clamp(0.0, 1.0 - start.width);
      final top = (start.top + dy).clamp(0.0, 1.0 - start.height);
      return Rect.fromLTWH(left, top, start.width, start.height);
    }
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;
    if (_handle == _RegionHandle.topLeft ||
        _handle == _RegionHandle.left ||
        _handle == _RegionHandle.bottomLeft) {
      left = (start.left + dx).clamp(0.0, start.right - _minSize);
    }
    if (_handle == _RegionHandle.topRight ||
        _handle == _RegionHandle.right ||
        _handle == _RegionHandle.bottomRight) {
      right = (start.right + dx).clamp(start.left + _minSize, 1.0);
    }
    if (_handle == _RegionHandle.topLeft ||
        _handle == _RegionHandle.top ||
        _handle == _RegionHandle.topRight) {
      top = (start.top + dy).clamp(0.0, start.bottom - _minSize);
    }
    if (_handle == _RegionHandle.bottomLeft ||
        _handle == _RegionHandle.bottom ||
        _handle == _RegionHandle.bottomRight) {
      bottom = (start.bottom + dy).clamp(start.top + _minSize, 1.0);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    final size = context.size ?? Size.zero;
    return MouseRegion(
      cursor: _cursor,
      onHover: (event) {
        final next = _cursorFor(_hitTest(event.localPosition, size));
        if (next != _cursor) setState(() => _cursor = next);
      },
      onExit: (_) {
        if (_cursor != SystemMouseCursors.move) {
          setState(() => _cursor = SystemMouseCursors.move);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => widget.onTap(),
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        onPanStart: (details) {
          final box = context.findRenderObject();
          if (box is! RenderBox) return;
          _start = widget.rect;
          _startLocal = details.localPosition;
          _latest = widget.rect;
          _handle = _hitTest(details.localPosition, box.size);
          _cursor = _cursorFor(_handle);
        },
        onPanUpdate: (details) {
          final origin = _startLocal;
          if (origin == null) return;
          final next = _updatedRect(details.localPosition - origin);
          _latest = next;
          widget.onChanged(next);
        },
        onPanEnd: (_) {
          final latest = _latest;
          _start = null;
          _startLocal = null;
          _latest = null;
          _handle = _RegionHandle.move;
          _cursor = SystemMouseCursors.move;
          if (latest != null) widget.onEnd(latest);
        },
        onPanCancel: () {
          _start = null;
          _startLocal = null;
          _latest = null;
          _handle = _RegionHandle.move;
          _cursor = SystemMouseCursors.move;
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
            if (widget.selected)
              for (final alignment in const [
                Alignment.topLeft,
                Alignment.topCenter,
                Alignment.topRight,
                Alignment.centerLeft,
                Alignment.centerRight,
                Alignment.bottomLeft,
                Alignment.bottomCenter,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: alignment,
                  child: IgnorePointer(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: widget.color,
                        border: Border.all(color: Colors.white, width: 1),
                        borderRadius: BorderRadius.circular(2),
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

/// Paints saved highlights above the dark-mode color filter so their colours
/// are not altered by the paper/ink luminance mapping.
class _PdfAnnotationScreenPainter extends CustomPainter {
  _PdfAnnotationScreenPainter({
    required this.controller,
    required this.annotations,
    required this.selectedId,
    required this.overlayKey,
    required this.colorOf,
  }) : super(repaint: controller);

  final PdfViewerController controller;
  final List<ReviewAnnotation> annotations;
  final String? selectedId;
  final GlobalKey overlayKey;
  final Color Function(String) colorOf;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isReady) return;
    final box = overlayKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final origin = box.localToGlobal(Offset.zero);
    for (final annotation in annotations) {
      final index = annotation.pageNumber - 1;
      if (index < 0 || index >= controller.layout.pageLayouts.length) {
        continue;
      }
      final page = controller.layout.pageLayouts[index];
      for (final rect in mergeRectsForDisplay(annotation.rects)) {
        final documentRect = Rect.fromLTWH(
          page.left + rect.left * page.width,
          page.top + rect.top * page.height,
          rect.width * page.width,
          rect.height * page.height,
        );
        final topLeft = controller.documentToGlobal(documentRect.topLeft);
        final bottomRight = controller.documentToGlobal(
          documentRect.bottomRight,
        );
        if (topLeft == null || bottomRight == null) continue;
        final local = Rect.fromPoints(
          topLeft - origin,
          bottomRight - origin,
        ).intersect(Offset.zero & size);
        if (local.isEmpty) continue;
        final color = colorOf(annotation.color);
        canvas.drawRect(local, Paint()..color = color.withValues(alpha: 0.34));
        if (annotation.id == selectedId && annotation.text.trim().isEmpty) {
          canvas.drawRect(
            local,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = color,
          );
        }
        if (annotation.text.trim().isEmpty) {
          canvas.drawRect(
            local,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = color,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PdfAnnotationScreenPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.controller != controller;
}

class _FilterMenuLabel extends StatelessWidget {
  const _FilterMenuLabel({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: active ? palette.primary : palette.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: active ? palette.primary : palette.textSecondary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? palette.primary : palette.textSecondary,
              ),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: active ? palette.primary : palette.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _AnnotationHistoryEntry {
  const _AnnotationHistoryEntry({required this.undo, required this.redo});

  final Future<void> Function() undo;
  final Future<void> Function() redo;
}
