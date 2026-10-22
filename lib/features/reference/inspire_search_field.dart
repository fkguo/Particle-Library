import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';

/// INSPIRE query field with the same history behaviour as zotero-inspire:
///
/// - typing a prefix shows the rest of the newest matching history entry as
///   inline grey text; Tab or ArrowRight accepts it;
/// - ArrowDown or the history button opens a menu with the stored queries and
///   a "clear history" entry; Escape closes it;
/// - choosing an entry fills the field and runs the search.
class InspireSearchField extends StatefulWidget {
  const InspireSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.searchTooltip,
    required this.history,
    required this.onSearch,
    required this.onClearHistory,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String searchTooltip;
  final List<String> Function() history;
  final VoidCallback onSearch;
  final VoidCallback onClearHistory;

  @override
  State<InspireSearchField> createState() => _InspireSearchFieldState();
}

class _InspireSearchFieldState extends State<InspireSearchField> {
  final MenuController _menu = MenuController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.focusNode.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.focusNode.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String? get _hint {
    if (!widget.focusNode.hasFocus) return null;
    final text = widget.controller.text;
    if (text.isEmpty) return null;
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.baseOffset != text.length) return null;
    final lower = text.toLowerCase();
    for (final item in widget.history()) {
      if (item.length > text.length && item.toLowerCase().startsWith(lower)) {
        return item;
      }
    }
    return null;
  }

  void _acceptHint() {
    final hint = _hint;
    if (hint == null) return;
    widget.controller.value = TextEditingValue(
      text: hint,
      selection: TextSelection.collapsed(offset: hint.length),
    );
  }

  void _toggleMenu() {
    if (_menu.isOpen) {
      _menu.close();
    } else {
      _menu.open();
    }
  }

  void _select(String query) {
    _menu.close();
    widget.controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    widget.onSearch();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final theme = Theme.of(context);
    final hint = _hint;
    final suffix = hint?.substring(widget.controller.text.length);
    final textStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    // The field is borderless with a fixed horizontal padding, so the inline
    // hint can be positioned right after the typed text.
    const textPadding = 10.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.search, size: 20, color: palette.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              if (hint != null) ...{
                const SingleActivator(LogicalKeyboardKey.tab): _acceptHint,
                const SingleActivator(LogicalKeyboardKey.arrowRight):
                    _acceptHint,
              },
              // The history list only opens from its button (or ArrowDown is
              // deliberately not bound): typing shows the inline hint only.
              if (_menu.isOpen)
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _menu.close(),
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => widget.onSearch(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: textPadding,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    prefixIcon: null,
                    suffixIcon: IconButton(
                      tooltip: widget.searchTooltip,
                      onPressed: widget.onSearch,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                    ),
                  ),
                ),
                if (suffix != null)
                  Positioned(
                    left:
                        textPadding +
                        1 +
                        _textWidth(widget.controller.text, textStyle, context),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          suffix,
                          style: textStyle.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 6),
          menuChildren: [
            for (final query in widget.history())
              MenuItemButton(
                onPressed: () => _select(query),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (widget.history().isNotEmpty) const Divider(height: 1),
            MenuItemButton(
              onPressed: () {
                _menu.close();
                widget.onClearHistory();
              },
              child: Text(strings.inspireClearHistory),
            ),
          ],
          builder: (context, controller, child) => IconButton(
            tooltip: strings.inspireSearchHistory,
            onPressed: _toggleMenu,
            icon: const Icon(Icons.history, size: 20),
          ),
        ),
      ],
    );
  }

  double _textWidth(String text, TextStyle style, BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
