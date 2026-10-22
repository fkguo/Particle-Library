import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../core/errors.dart';
import '../../data/pdg_database.dart';
import '../../data/inspire_bibtex.dart';
import '../../data/zotero_bridge.dart';
import '../../data/zotero_cache.dart';
import '../../data/zotero_inspire_api.dart';
import '../../data/pdg_notes.dart';
import '../../data/reference_metadata.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../domain/reference_title.dart';
import '../common/async_view.dart';
import '../common/context_sidebar.dart';
import '../common/description_text.dart';
import '../common/math_text.dart';
import '../common/favorite_button.dart';
import '../common/page.dart';
import '../common/page_outline.dart';
import '../common/raw_fields.dart';
import '../common/snack_bars.dart';
import '../common/ui.dart';
import '../common/zotero_icon.dart';
import 'zotero_setup_dialog.dart';
import '../../notes/notes.dart';
import '../notes/notes_anchor.dart';
import '../notes/notes_entity.dart';
import '../series/measurement_card.dart';

class ReferencePage extends StatefulWidget {
  const ReferencePage({super.key, required this.referenceId}) : patch = null;

  /// A work that appears only in a pdgLive summary. Its bibliographic data
  /// comes from the notes patch; the page reuses the normal reference layout.
  const ReferencePage.patch({super.key, required this.patch})
    : referenceId = -1;

  final int referenceId;
  final PdgNoteReference? patch;

  @override
  State<ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends State<ReferencePage> {
  late Future<
    ({
      Reference reference,
      List<ReferenceSeriesGroup> groups,
      List<Reference> sameDoi,
      List<Entry> citing,
    })
  >
  _future;

  bool _initialized = false;
  String? _enrichedTitle;
  String? _enrichedSource;
  String? _lookupError;
  bool _lookingUp = false;
  bool _bibtexLoading = false;
  String? _citeKey;
  bool _citeKeyLoading = false;
  bool _zoteroBusy = false;
  bool _zoteroProbed = false;
  ZoteroInspireStatus? _zoteroInspireStatus;
  List<NoteAnchorInput> _captureAnchors = const <NoteAnchorInput>[];
  String? _captureLabel;

  String _displayTitle(Reference reference) {
    if (reference.title.isNotEmpty) return plainReferenceTitle(reference.title);
    final enriched = _enrichedTitle;
    if (enriched != null && enriched.isNotEmpty) {
      return plainReferenceTitle(enriched);
    }
    return plainReferenceTitle(reference.displayTitle);
  }

  Future<void> _lookupTitle(Reference reference) async {
    if (_lookingUp) return;
    final scope = AppScope.of(context);
    final store = scope.store;
    final strings = scope.strings;
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    try {
      final result = await const ReferenceMetadataService().fetchTitleByDoi(
        reference.doi,
      );
      await store.cacheReferenceTitle(
        reference.doi,
        result.title,
        source: result.source,
      );
      if (!mounted) return;
      final noteContext = referenceNotesContext(
        reference,
        snapshotHash: scope.snapshotHash,
        displayTitle: result.title,
      );
      setState(() {
        _lookingUp = false;
        _enrichedTitle = result.title;
        _enrichedSource = result.source;
        _captureAnchors = noteContext.anchors;
        _captureLabel = noteContext.label;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _lookupError =
            '${strings.referenceLookupFailed}: ${errorText(error, strings)}';
      });
    }
  }

  Future<void> _loadCiteKey(Reference reference) async {
    if (!InspireBibtexService.canFetch(
      inspireId: reference.inspireId,
      doi: reference.doi,
    )) {
      return;
    }
    final key = await const InspireBibtexService().fetchCiteKey(
      inspireId: reference.inspireId,
      doi: reference.doi,
    );
    if (!mounted) return;
    setState(() {
      _citeKey = key;
      _citeKeyLoading = false;
    });
  }

  Future<void> _probeZoteroInspire() async {
    if (!ZoteroBridge.isSupportedPlatform) return;
    if (!AppScope.of(context).settings.zoteroEnabled) return;
    final status = await const ZoteroInspireApi().probe();
    if (!mounted) return;
    setState(() => _zoteroInspireStatus = status);
  }

  Future<void> _addToZoteroFromPlugin(
    Reference reference,
    AppStrings strings,
  ) async {
    final recid = reference.inspireId.trim();
    if (!RegExp(r'^\d+$').hasMatch(recid)) return;
    final result = await const ZoteroInspireApi().addItemWithPicker(recid);
    if (!mounted || result == null) return;
    showActionSnackBar(
      ScaffoldMessenger.of(context),
      message: result.existing
          ? strings.inspireAlreadyInZotero
          : strings.inspireAddedToZotero,
      actionLabel: strings.zoteroOpen,
      onAction: () => _launchZoteroItem(result.itemKey),
    );
  }

  Future<void> _launchZoteroItem(String key) => launchUrl(
    Uri.parse('zotero://select/library/items/$key'),
    mode: LaunchMode.externalApplication,
  );

  Future<void> _openZotero(Reference reference) async {
    if (_zoteroBusy) return;
    final strings = AppScope.of(context).strings;
    setState(() => _zoteroBusy = true);
    try {
      var status = _zoteroInspireStatus;
      if (status == null) {
        status = await const ZoteroInspireApi().probe();
        if (!mounted) return;
        _zoteroInspireStatus = status;
      }
      final hasRecid = RegExp(r'^\d+$').hasMatch(reference.inspireId.trim());
      final canAdd = status.canAdd && hasRecid;
      final bridge = const ZoteroBridge();
      final zoteroRunning = await bridge.isAvailable();
      Future<void> offerSetup() async {
        if (!hasRecid) {
          await _copyReferenceBibtexFallback(reference, strings);
          return;
        }
        final copy = await showZoteroInspireSetupDialog(
          context,
          strings: strings,
          reason: zoteroSetupReasonFor(status!),
          currentVersion: status.version,
          zoteroRunning: zoteroRunning,
          offerBibtex: true,
        );
        if (copy && mounted) {
          await _copyReferenceBibtexFallback(reference, strings);
        }
      }

      if (!zoteroRunning) {
        if (!mounted) return;
        if (canAdd) {
          await _addToZoteroFromPlugin(reference, strings);
          return;
        }
        await offerSetup();
        return;
      }
      final index = await ZoteroCacheIndex.load();
      final key =
          index?.findItemKey(recid: reference.inspireId, doi: reference.doi) ??
          await bridge.findItemKey(
            recid: reference.inspireId,
            doi: reference.doi,
          );
      if (!mounted) return;
      if (key != null && key.isNotEmpty) {
        await _launchZoteroItem(key);
        return;
      }
      if (canAdd) {
        await _addToZoteroFromPlugin(reference, strings);
        return;
      }
      await offerSetup();
    } on ZoteroInspireException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.inspireAddToZoteroFailed}: ${error.message}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.inspireZoteroFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _zoteroBusy = false);
    }
  }

  Future<void> _copyReferenceBibtexFallback(
    Reference reference,
    AppStrings strings,
  ) async {
    final bibtex = await const InspireBibtexService().fetchBibtex(
      inspireId: reference.inspireId,
      doi: reference.doi,
    );
    if (!mounted) return;
    await copyText(context, bibtex, message: strings.inspireZoteroCopied);
    if (!mounted) return;
    final hasRecid = RegExp(r'^\d+$').hasMatch(reference.inspireId.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasRecid
              ? strings.inspireZoteroAddUnavailable
              : strings.inspireZoteroNotFound,
        ),
      ),
    );
  }

  Future<void> _copyBibtex(Reference reference) async {
    if (_bibtexLoading) return;
    final strings = AppScope.of(context).strings;
    setState(() => _bibtexLoading = true);
    try {
      final text = await const InspireBibtexService().fetchBibtex(
        inspireId: reference.inspireId,
        doi: reference.doi,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _bibtexLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.referenceBibtexCopied)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bibtexLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.referenceBibtexFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = _load();
    if (AppScope.of(context).settings.zoteroEnabled && !_zoteroProbed) {
      _zoteroProbed = true;
      unawaited(_probeZoteroInspire());
    }
    _future.then((data) {
      if (!mounted) return;
      final scope = AppScope.of(context);
      final notes = referenceNotesContext(
        data.reference,
        snapshotHash: scope.snapshotHash,
        displayTitle: _displayTitle(data.reference),
      );
      setState(() {
        _captureAnchors = notes.anchors;
        _captureLabel = notes.label;
      });
    });
  }

  Future<
    ({
      Reference reference,
      List<ReferenceSeriesGroup> groups,
      List<Reference> sameDoi,
      List<Entry> citing,
    })
  >
  _load() async {
    final scope = AppScope.of(context);
    final repository = scope.repository;
    final database = scope.database;
    final store = scope.store;
    final patch = widget.patch;
    if (patch != null) {
      final reference = Reference({
        'id': -1,
        'document_id': patch.documentId,
        'publication_name': patch.publication ?? '',
        'publication_year': patch.year,
        'doi': patch.doi ?? '',
        'inspire_id': patch.inspireRecid?.toString() ?? '',
        'title': patch.title ?? '',
      });
      final patchKey = patch.citeKey ?? '';
      if (patchKey.isNotEmpty) {
        _citeKey = patchKey;
      } else if (InspireBibtexService.canFetch(
        inspireId: reference.inspireId,
        doi: reference.doi,
      )) {
        _citeKeyLoading = true;
        unawaited(_loadCiteKey(reference));
      }
      final citing = <Entry>[];
      for (final id in await PdgNotes.entriesForCitation(patch.documentId)) {
        final entry = await database.entryByPdgid(id);
        if (entry != null) citing.add(entry);
      }
      return (
        reference: reference,
        groups: const <ReferenceSeriesGroup>[],
        sameDoi: const <Reference>[],
        citing: citing,
      );
    }
    final reference = await database.referenceById(widget.referenceId);
    if (reference == null) {
      throw NotFoundException('当前快照未收录文献记录 ${widget.referenceId}。');
    }
    final groups = await repository.referenceSeriesGroups(widget.referenceId);
    final sameDoi = reference.doi.isEmpty
        ? <Reference>[]
        : await database.referencesByDoi(reference.doi);
    // Prefer the cite key captured in the pdgLive-notes patch (offline), and
    // only ask INSPIRE for references the patch does not cover.
    final patchCiteKey = await PdgNotes.citeKeyFor(reference.documentId);
    if (patchCiteKey != null) {
      _citeKey = patchCiteKey;
    } else if (InspireBibtexService.canFetch(
      inspireId: reference.inspireId,
      doi: reference.doi,
    )) {
      _citeKeyLoading = true;
      unawaited(_loadCiteKey(reference));
    }
    if (reference.title.isEmpty) {
      final cached = store.cachedReferenceTitle(reference.doi);
      _enrichedTitle = cached?.title;
      _enrichedSource = cached?.source;
    }
    return (
      reference: reference,
      groups: groups,
      sameDoi: sameDoi,
      citing: const <Entry>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    return PageScaffold(
      showSidebarToggle: true,
      maxWidth: 1480,
      noteAnchors: _captureAnchors,
      noteLabel: _captureLabel,

      title: FutureBuilder(
        future: _future,
        builder: (context, snapshot) => DescriptionText(
          snapshot.data == null
              ? '${widget.referenceId}'
              : _displayTitle(snapshot.data!.reference),
          maxLines: 1,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      subtitle: scope.strings.referenceTitle,
      actions: [
        FutureBuilder<
          ({
            Reference reference,
            List<ReferenceSeriesGroup> groups,
            List<Reference> sameDoi,
            List<Entry> citing,
          })
        >(
          future: _future,
          builder: (context, snapshot) {
            final reference = snapshot.data?.reference;
            if (reference == null) return const SizedBox.shrink();
            final notes = referenceNotesContext(
              reference,
              snapshotHash: scope.snapshotHash,
              displayTitle: _displayTitle(reference),
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (scope.settings.zoteroEnabled &&
                    ZoteroBridge.isSupportedPlatform &&
                    (reference.inspireId.isNotEmpty ||
                        reference.doi.isNotEmpty))
                  IconButton(
                    tooltip: _zoteroInspireStatus?.canAdd == true
                        ? strings.inspireZoteroFindOrAdd
                        : strings.zoteroOpen,
                    onPressed: _zoteroBusy
                        ? null
                        : () => _openZotero(reference),
                    icon: _zoteroBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const ZoteroIcon(size: 20),
                  ),
                EntityNotesButton(
                  targets: notes.targets,
                  anchors: notes.anchors,
                ),
              ],
            );
          },
        ),
      ],
      body: AsyncView(
        future: _future,
        onRetry: () => setState(() => _future = _load()),
        builder: (context, data) => _ReferenceBody(
          reference: data.reference,
          groups: data.groups,
          sameDoi: data.sameDoi,
          citing: data.citing,
          isPatch: widget.patch != null,
          displayTitle: _displayTitle(data.reference),
          enrichedTitle: _enrichedTitle,
          enrichedSource: _enrichedSource,
          lookingUp: _lookingUp,
          lookupError: _lookupError,
          onLookup: () => _lookupTitle(data.reference),
          bibtexLoading: _bibtexLoading,
          onCopyBibtex: () => _copyBibtex(data.reference),
          citeKey: _citeKey,
          citeKeyLoading: _citeKeyLoading,
        ),
      ),
    );
  }
}

class _ReferenceBody extends StatelessWidget {
  const _ReferenceBody({
    required this.reference,
    required this.groups,
    required this.sameDoi,
    required this.citing,
    required this.isPatch,
    required this.displayTitle,
    required this.enrichedTitle,
    required this.enrichedSource,
    required this.lookingUp,
    required this.lookupError,
    required this.onLookup,
    required this.bibtexLoading,
    required this.onCopyBibtex,
    required this.citeKey,
    required this.citeKeyLoading,
  });

  final Reference reference;
  final List<ReferenceSeriesGroup> groups;
  final List<Reference> sameDoi;
  final List<Entry> citing;
  final bool isPatch;
  final String displayTitle;
  final String? enrichedTitle;
  final String? enrichedSource;
  final bool lookingUp;
  final String? lookupError;
  final VoidCallback onLookup;
  final bool bibtexLoading;
  final VoidCallback onCopyBibtex;
  final String? citeKey;
  final bool citeKeyLoading;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final detailed = scope.settings.detailedMode;
    final palette = context.palette;
    final doiUri = _doiUri(reference.doi);
    final inspireUri = ReferenceMetadataService.inspireUri(
      inspireId: reference.inspireId,
      doi: reference.doi,
      title: reference.title,
    );
    final inspireDirect = ReferenceMetadataService.hasInspireId(
      reference.inspireId,
    );
    final inspireViaDoi =
        !inspireDirect && ReferenceMetadataService.isValidDoi(reference.doi);
    final inspireViaTitle =
        !inspireDirect && !inspireViaDoi && inspireUri != null;
    final notes = referenceNotesContext(
      reference,
      snapshotHash: scope.snapshotHash,
      displayTitle: displayTitle,
    );
    final overviewKey = GlobalKey();
    final documentsKey = GlobalKey();
    final notesKey = GlobalKey();
    final measurementsKey = GlobalKey();
    final citingKey = GlobalKey();
    final outlineItems = <PageOutlineItem>[
      PageOutlineItem(
        label: strings.pageOverview,
        target: overviewKey,
        icon: Icons.info_outline,
      ),
      PageOutlineItem(
        label: strings.referenceDocuments,
        target: documentsKey,
        icon: Icons.description_outlined,
      ),
      if (!isPatch)
        PageOutlineItem(
          label: strings.notesTitle,
          target: notesKey,
          icon: Icons.sticky_note_2_outlined,
        ),
      if (isPatch)
        PageOutlineItem(
          label: strings.referenceCitedByEntries,
          target: citingKey,
          icon: Icons.link,
        )
      else
        PageOutlineItem(
          label: strings.referenceReverseMeasurements,
          target: measurementsKey,
          icon: Icons.straighten,
        ),
    ];
    final content = PageOutlineScaffold(
      label: strings.pageOutline,
      items: outlineItems,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ContentHeader(
              key: overviewKey,
              title: DescriptionText(
                displayTitle,
                maxLines: 3,
                selectable: true,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                [
                  reference.documentId,
                  if (reference.publicationYear != null)
                    '${reference.publicationYear}',
                  if (reference.publicationName.isNotEmpty)
                    reference.publicationName,
                ].join(' · '),
              ),
              meta: [
                if (isPatch)
                  MetaChip(strings.referencePdgLiveNote, tone: BadgeTone.info)
                else
                  MetaChip('pdgreference #${reference.id}'),
                if (reference.publicationYear != null)
                  MetaChip('${reference.publicationYear}'),
                if (reference.doi.isNotEmpty)
                  MetaChip('DOI', tone: BadgeTone.info),
                if (reference.inspireId.isNotEmpty)
                  MetaChip('INSPIRE', tone: BadgeTone.accent),
              ],
              actions: [
                if (!isPatch)
                  FavoriteButton(
                    favorite: referenceFavorite(
                      reference: reference,
                      snapshotHash: scope.snapshotHash,
                    ),
                  ),
                CopyIconButton(
                  text: _citation(reference, displayTitle),
                  tooltip: strings.referenceCopyCitation,
                ),
              ],
            ),
            if (reference.title.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: Container(
                  padding: const EdgeInsets.all(Insets.m),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 17,
                            color: palette.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              enrichedTitle == null
                                  ? strings.referenceLookupHint
                                  : strings.referenceEnrichedNote,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Insets.s),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_doiUri(reference.doi) != null)
                            OutlinedButton.icon(
                              onPressed: lookingUp ? null : onLookup,
                              icon: lookingUp
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.travel_explore, size: 17),
                              label: Text(
                                lookingUp
                                    ? strings.referenceLookupRunning
                                    : enrichedTitle == null
                                    ? strings.referenceLookupTitle
                                    : strings.referenceRefreshTitle,
                              ),
                            )
                          else
                            Text(
                              strings.referenceLookupNoDoi,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          if (enrichedTitle != null)
                            MetaChip(
                              enrichedSource ?? 'Crossref',
                              tone: BadgeTone.info,
                              icon: Icons.cloud_done_outlined,
                            ),
                        ],
                      ),
                      if (lookupError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          lookupError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Padding(
              key: documentsKey,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.referenceDocuments,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataField(
                      label: strings.referenceTitle,
                      value: plainReferenceTitle(reference.title),
                      warning: reference.title.isEmpty,
                      valueWidget: reference.title.isEmpty
                          ? null
                          : DescriptionText(
                              plainReferenceTitle(reference.title),
                              selectable: true,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                    ),
                    if (enrichedTitle != null)
                      DataField(
                        label: strings.referenceEnrichedTitle,
                        value: enrichedTitle!,
                      ),
                    DataField(
                      label: strings.referenceDocumentId,
                      value: reference.documentId,
                    ),
                    DataField(
                      label: strings.referencePublication,
                      value: reference.publicationName,
                      warning: reference.publicationName.isEmpty,
                    ),
                    DataField(
                      label: strings.referenceYear,
                      value: reference.publicationYear?.toString() ?? '',
                      warning: reference.publicationYear == null,
                    ),
                    DataField(
                      label: strings.referenceDoi,
                      value: reference.doi,
                      warning: reference.doi.isEmpty,
                    ),
                    DataField(
                      label: strings.referenceInspire,
                      value: reference.inspireId,
                      warning: reference.inspireId.isEmpty,
                    ),
                    DataField(
                      label: strings.referenceInspireCiteKey,
                      value: citeKeyLoading
                          ? '…'
                          : (citeKey == null || citeKey!.isEmpty
                                ? '—'
                                : citeKey!),
                      warning: citeKey == null || citeKey!.isEmpty,
                      monospace: citeKey != null && citeKey!.isNotEmpty,
                    ),
                    if (detailed)
                      DataField(
                        label: strings.metadataId,
                        value: '${reference.id}',
                        monospace: true,
                      ),
                    const SizedBox(height: Insets.s),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (doiUri != null)
                          Tooltip(
                            message: strings.referenceOpenDoi,
                            child: OutlinedButton.icon(
                              onPressed: () => _launch(context, doiUri),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: Text(strings.referenceDoi),
                            ),
                          ),
                        if (inspireUri != null)
                          Tooltip(
                            message: inspireDirect
                                ? strings.referenceOpenInspire
                                : inspireViaDoi
                                ? strings.referenceSearchInspireDoi
                                : strings.referenceSearchInspireTitle,
                            child: OutlinedButton.icon(
                              onPressed: () => _launch(context, inspireUri),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('INSPIRE'),
                            ),
                          ),
                        Tooltip(
                          message:
                              InspireBibtexService.canFetch(
                                inspireId: reference.inspireId,
                                doi: reference.doi,
                              )
                              ? strings.referenceCopyBibtex
                              : strings.referenceBibtexNoId,
                          child: OutlinedButton.icon(
                            onPressed:
                                InspireBibtexService.canFetch(
                                      inspireId: reference.inspireId,
                                      doi: reference.doi,
                                    ) &&
                                    !bibtexLoading
                                ? onCopyBibtex
                                : null,
                            icon: bibtexLoading
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.copy_all, size: 16),
                            label: Text(
                              bibtexLoading
                                  ? strings.referenceCopyBibtexRunning
                                  : strings.referenceCopyBibtex,
                            ),
                          ),
                        ),
                        if (doiUri == null)
                          Text(
                            strings.referenceNoDoi,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        if (inspireViaDoi)
                          Text(
                            strings.referenceInspireViaDoi,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        if (inspireViaTitle)
                          Text(
                            strings.referenceInspireViaTitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        if (inspireUri == null)
                          Text(
                            strings.referenceNoInspire,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                      ],
                    ),
                    if (sameDoi.length > 1) ...[
                      const SizedBox(height: Insets.s),
                      Text(
                        '${strings.referenceDuplicateDoi} (${sameDoi.length})',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.m),
            if (isPatch) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.s,
                  Insets.l,
                  0,
                ),
                child: Text(
                  strings.referencePdgLiveExplanation,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
              const SizedBox(height: Insets.m),
              SectionHeading(strings.referenceCitedByEntries, key: citingKey),
              if (citing.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                  child: EmptyPanel(
                    message: strings.referencePdgLiveNoEntries,
                    icon: Icons.link_off,
                  ),
                )
              else
                for (final entry in citing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      0,
                      Insets.l,
                      Insets.s,
                    ),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.science_outlined,
                          size: 20,
                          color: palette.textSecondary,
                        ),
                        title: ParticleSymbol(entry.description, fontSize: 16),
                        subtitle: Text('PDG ${entry.pdgid}'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => AppNav.openPdgid(context, entry.pdgid),
                      ),
                    ),
                  ),
            ] else ...[
              EntityNotesSection(
                key: notesKey,
                targets: notes.targets,
                anchors: notes.anchors,
              ),
              const SizedBox(height: Insets.m),
              SectionHeading(
                strings.referenceReverseMeasurements,
                key: measurementsKey,
                subtitle: strings.referenceGroupsHint,
              ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                  child: EmptyPanel(
                    message: strings.referenceNoReverse,
                    icon: Icons.link_off,
                  ),
                )
              else
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.l,
                      0,
                      Insets.l,
                      Insets.s,
                    ),
                    child: _ReferenceGroupCard(
                      referenceId: reference.id,
                      group: group,
                    ),
                  ),
            ],
            const SizedBox(height: Insets.m),
            if (!isPatch)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: RawFieldsPanel(
                  fields: reference.rawFields,
                  title: strings.referenceRaw,
                ),
              ),
            const SizedBox(height: Insets.m),
            SnapshotFooter(hash: scope.snapshotHash),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showContextSidebar(context, constraints.maxWidth)) return content;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            ResizableContextSidebar(
              viewportWidth: constraints.maxWidth,
              child: ReferenceContextSidebar(
                reference: reference,
                groups: groups,
                displayTitle: displayTitle,
              ),
            ),
          ],
        );
      },
    );
  }

  static Uri? _doiUri(String doi) {
    if (doi.isEmpty) return null;
    if (doi.contains('://') || doi.contains(' ')) return null;
    if (!RegExp(r'^10\.[0-9]{4,9}/\S+$').hasMatch(doi)) return null;
    return Uri.parse('https://doi.org/$doi');
  }

  static Future<void> _launch(BuildContext context, Uri uri) async {
    final strings = AppScope.of(context).strings;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.commonError)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.commonError)));
      }
    }
  }

  static String _citation(Reference reference, String displayTitle) => [
    displayTitle,
    reference.publicationName,
    if (reference.publicationYear != null) '${reference.publicationYear}',
    'PDG document_id: ${reference.documentId}',
    if (reference.doi.isNotEmpty) 'DOI: ${reference.doi}',
    if (reference.inspireId.isNotEmpty) 'INSPIRE: ${reference.inspireId}',
    if (reference.id >= 0) 'pdgreference #${reference.id}',
  ].where((line) => line.isNotEmpty).join('\n');
}

class _ReferenceGroupCard extends StatefulWidget {
  const _ReferenceGroupCard({required this.referenceId, required this.group});

  final int referenceId;
  final ReferenceSeriesGroup group;

  @override
  State<_ReferenceGroupCard> createState() => _ReferenceGroupCardState();
}

class _ReferenceGroupCardState extends State<_ReferenceGroupCard> {
  bool _expanded = false;
  bool _loading = false;
  List<MeasurementBundle>? _items;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => AppNav.openPdgid(context, widget.group.pdgid),
            child: Padding(
              padding: const EdgeInsets.all(Insets.m),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DescriptionText(
                          widget.group.description,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.group.pdgid} · ${dataTypeInfo(widget.group.dataType).label(strings.lang)} · ${widget.group.count} ${strings.referenceGroupCount}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () async {
                            if (_expanded) {
                              setState(() => _expanded = false);
                              return;
                            }
                            setState(() {
                              _expanded = true;
                              _loading = true;
                            });
                            try {
                              final items = await AppScope.of(context)
                                  .repository
                                  .measurementsForReferenceSeries(
                                    widget.referenceId,
                                    widget.group.entryId,
                                  );
                              if (mounted) {
                                setState(() {
                                  _items = items;
                                  _loading = false;
                                });
                              }
                            } catch (_) {
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                    child: Text(
                      _expanded
                          ? strings.commonShowLess
                          : strings.referenceShowMeasurements,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.m,
                0,
                Insets.m,
                Insets.m,
              ),
              child: _loading
                  ? const Center(child: LoadingPanel(compact: true))
                  : Column(
                      children: [
                        for (final item
                            in _items ?? const <MeasurementBundle>[])
                          Padding(
                            padding: const EdgeInsets.only(bottom: Insets.s),
                            child: MeasurementCard(bundle: item),
                          ),
                        if ((_items?.length ?? 0) >= 50)
                          Text(
                            '${strings.searchShowingFirst} (50)',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// Crossref sometimes returns MathML/HTML instead of a plain title.
///
/// Keep the original string in raw fields, but show a readable title in the
/// header and documents panel. PDG `$...$` math is left for [DescriptionText].
String plainReferenceTitle(String source) => cleanReferenceTitle(source);
