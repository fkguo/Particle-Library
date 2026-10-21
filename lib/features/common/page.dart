import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/chrome_visibility.dart';
import '../../app/navigation.dart';
import '../../app/app_theme.dart';
import '../../notes/notes.dart';
import '../notes/note_capture.dart';

/// The single owl mark used by the app header, boot screen and empty states.
///
/// It loads the same PNG artwork that is compiled into the platform icon so
/// the Dock, header and placeholders cannot drift into different characters.
class BrandMark extends StatefulWidget {
  const BrandMark({super.key, this.size = 30, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> {
  static const int _frameCount = 6;
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant BrandMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    _frame = 0;
    if (!widget.animate) return;
    _timer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.animate
        ? 'assets/brand/quark-idle-$_frame.png'
        : 'assets/brand/app_icon.png';
    return Image.asset(
      asset,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Particle Library',
    );
  }
}

class PageScaffold extends StatefulWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.subtitle,
    this.maxWidth = 1120,
    this.bottom,
    this.floatingActionButton,
    this.noteAnchors = const <NoteAnchorInput>[],
    this.noteLabel,
    this.showSidebarToggle = false,
  });

  final Widget title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final double maxWidth;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final List<NoteAnchorInput> noteAnchors;
  final String? noteLabel;
  final bool showSidebarToggle;

  @override
  State<PageScaffold> createState() => _PageScaffoldState();
}

class _PageScaffoldState extends State<PageScaffold> {
  String? _selectedText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final body = widget.body;
    final actions = widget.actions;
    final maxWidth = widget.maxWidth;
    final bottom = widget.bottom;
    final floatingActionButton = widget.floatingActionButton;
    final canPop = Navigator.of(context).canPop();
    final nested = NavigationScope.maybeOf(context) != null;
    final chromeHidden = ChromeVisibilityScope.isHidden(context);
    final showBack = canPop && (!nested || chromeHidden);
    return SelectionArea(
      onSelectionChanged: (content) => _selectedText = content?.plainText ?? '',
      contextMenuBuilder: (context, state) => _buildContextMenu(context, state),
      child: Scaffold(
        backgroundColor: palette.background,
        // AppShell already resizes its body for the keyboard. Resizing a
        // nested Scaffold again subtracts the keyboard inset twice and can
        // collapse the editor body to zero height.
        resizeToAvoidBottomInset: !nested,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: showBack
              ? IconButton(
                  tooltip: AppScope.of(context).strings.commonBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : nested
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(size: 26),
                  ),
                ),
          titleSpacing: showBack ? 0 : (nested ? 16 : 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          actions: [
            if (widget.showSidebarToggle)
              IconButton(
                tooltip: AppScope.of(context).settings.sidebarMode == 'off'
                    ? AppScope.of(context).strings.sidebarShow
                    : AppScope.of(context).strings.sidebarHide,
                icon: Icon(
                  AppScope.of(context).settings.sidebarMode == 'off'
                      ? Icons.vertical_split_outlined
                      : Icons.vertical_split,
                  size: 19,
                ),
                onPressed: () {
                  final settings = AppScope.of(context).settings;
                  settings.setSidebarMode(
                    settings.sidebarMode == 'off' ? 'auto' : 'off',
                  );
                },
              ),
            if (showBack)
              IconButton(
                tooltip: AppScope.of(context).strings.navHome,
                icon: const Icon(Icons.home_outlined, size: 19),
                onPressed: () {
                  AppScope.of(context).homeRequests.value++;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ...actions,
          ],
          bottom: bottom,
        ),
        floatingActionButton: floatingActionButton,
        // Use the whole screen width, including the landscape notch/rounded
        // corner bands: page chrome already runs edge to edge and the user has
        // asked for no reserved side gutters. Vertical safe areas still clear
        // the status bar and the home indicator.
        body: SafeArea(
          left: false,
          right: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenu(BuildContext context, SelectableRegionState state) {
    final strings = AppScope.of(context).strings;
    final selected = _selectedText?.trim() ?? '';
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: strings.commonCopy,
        onPressed: () async {
          if (selected.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: selected));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(strings.commonCopied)));
        },
      ),
      ContextMenuButtonItem(
        label: strings.commonSelectAll,
        onPressed: () => state.selectAll(),
      ),
      if (selected.isNotEmpty && widget.noteAnchors.isNotEmpty)
        ContextMenuButtonItem(
          label: strings.notesAddSelection,
          onPressed: () => captureTextToNote(
            context,
            text: selected,
            anchors: widget.noteAnchors,
            label: widget.noteLabel ?? strings.notesTitle,
          ),
        ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }
}

class SnapshotFooter extends StatelessWidget {
  const SnapshotFooter({super.key, required this.hash});

  final String hash;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (!scope.settings.detailedMode) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.l),
      child: Text(
        '${scope.strings.commonSnapshot}: $hash',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: palette.textSecondary),
      ),
    );
  }
}

class ContentHeader extends StatelessWidget {
  const ContentHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.meta = const [],
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      Insets.l,
      Insets.xl,
      Insets.l,
      Insets.m,
    ),
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> meta;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: Insets.m),
                Wrap(spacing: 4, children: actions),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: palette.textSecondary),
              child: subtitle!,
            ),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: Insets.s),
            Wrap(spacing: 6, runSpacing: 6, children: meta),
          ],
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.trailing,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.l,
        Insets.l,
        Insets.l,
        Insets.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: palette.textSecondary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class DataField extends StatelessWidget {
  const DataField({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.icon,
    this.monospace = false,
    this.warning = false,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final IconData? icon;
  final bool monospace;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: palette.textSecondary),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                valueWidget ??
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: monospace ? 'Menlo' : null,
                    fontSize: monospace ? 12 : null,
                    color: warning ? palette.warning : palette.textPrimary,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class PropertySummaryCard extends StatelessWidget {
  const PropertySummaryCard({
    super.key,
    this.title,
    this.titleWidget,
    required this.value,
    required this.onTap,
    this.badge,
    this.subtitle,
    this.trailing,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final Widget value;
  final VoidCallback onTap;
  final Widget? badge;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(Insets.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                        titleWidget ??
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textSecondary),
                        ),
                  ),
                  ?badge,
                ],
              ),
              const SizedBox(height: Insets.s),
              value,
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                  child: subtitle!,
                ),
              ],
              if (trailing != null) ...[const SizedBox(height: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
