import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../search/search_service.dart';
import '../common/description_text.dart';

/// Compact PDG lookup used from the notes editor. Selecting a hit inserts a
/// source line and adds a clickable note anchor; it never copies the whole PDG
/// record into the note.
class NotePdgRail extends StatefulWidget {
  const NotePdgRail({
    super.key,
    required this.search,
    required this.strings,
    required this.onOpen,
    this.compact = false,
    this.autofocus = false,
  });

  final SearchService search;
  final AppStrings strings;
  final ValueChanged<SearchHit> onOpen;
  final bool compact;
  final bool autofocus;

  @override
  State<NotePdgRail> createState() => _NotePdgRailState();
}

class _NotePdgRailState extends State<NotePdgRail> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<SearchHit> _hits = const <SearchHit>[];
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _generation++;
      setState(() {
        _hits = const <SearchHit>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), _run);
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _hits = const <SearchHit>[];
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.search.search(
        query,
        SearchScope.all,
        limit: 8,
      );
      if (!mounted || generation != _generation) return;
      final hits = <SearchHit>[];
      final seen = <String>{};
      for (final group in result.groups) {
        for (final hit in group.hits) {
          final key = hit.referenceId != null
              ? 'reference:${hit.referenceId}'
              : hit.pdgid ?? hit.title;
          if (seen.add(key)) hits.add(hit);
        }
      }
      setState(() {
        _hits = hits.take(8).toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = const <SearchHit>[];
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = widget.strings;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.travel_explore, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    strings.notesPdgLookup,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: _onChanged,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: strings.notesPdgLookupHint,
                prefixIcon: const Icon(Icons.search, size: 17),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              strings.notesPdgLookupHintDetail,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(
                '${strings.notesPdgLookupFailed}: $_error',
                style: TextStyle(color: palette.warning),
              ),
            ),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _controller.text.trim().isEmpty
                            ? strings.notesPdgLookupIdle
                            : strings.notesPdgLookupEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    itemCount: _hits.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final hit = _hits[index];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: DescriptionText(
                          hit.title,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          hit.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Tooltip(
                          message: strings.commonOpen,
                          child: const Icon(Icons.open_in_new, size: 16),
                        ),
                        onTap: () => widget.onOpen(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
