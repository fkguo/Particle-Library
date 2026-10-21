import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../app/navigation.dart';
import '../../domain/reference_title.dart';
import '../../user/user_store.dart';
import '../common/description_text.dart';
import '../common/resize_handle.dart';
import '../common/snack_bars.dart';
import '../common/ui.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  FavoriteKind? _filter;
  bool _sidebarOpen = true;
  double _sidebarWidth = 230;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    return AnimatedBuilder(
      animation: scope.store,
      builder: (context, _) {
        final favorites = scope.store.favorites
            .where((favorite) => _filter == null || favorite.kind == _filter)
            .toList(growable: false);
        final all = scope.store.favorites;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final content = ListView(
              padding: const EdgeInsets.only(bottom: Insets.xxl),
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
                        child: Text(
                          strings.favoritesTitle,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                        ),
                      ),
                      MetaChip(
                        '${all.length} ${strings.favoritesCount}',
                        tone: BadgeTone.info,
                      ),
                    ],
                  ),
                ),
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          label: Text(
                            '${strings.favoritesAll} · ${all.length}',
                          ),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                        FilterChip(
                          label: Text(
                            '${strings.favoritesEntries} · ${all.where((favorite) => favorite.kind == FavoriteKind.entry).length}',
                          ),
                          selected: _filter == FavoriteKind.entry,
                          onSelected: (_) =>
                              setState(() => _filter = FavoriteKind.entry),
                        ),
                        FilterChip(
                          label: Text(
                            '${strings.favoritesReferences} · ${all.where((favorite) => favorite.kind == FavoriteKind.reference).length}',
                          ),
                          selected: _filter == FavoriteKind.reference,
                          onSelected: (_) =>
                              setState(() => _filter = FavoriteKind.reference),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Insets.s),
                if (favorites.isEmpty)
                  EmptyPanel(
                    message: _filter == null
                        ? strings.favoritesEmpty
                        : strings.favoritesEmptyFilter,
                    icon: Icons.star_border,
                  )
                else
                  for (final favorite in favorites)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.l,
                        0,
                        Insets.l,
                        Insets.s,
                      ),
                      child: _FavoriteTile(favorite: favorite),
                    ),
              ],
            );
            if (!wide) return content;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CollapsibleSidebar(
                  expanded: _sidebarOpen,
                  width: _sidebarWidth,
                  tooltip: strings.favoritesResizeTooltip,
                  railIcon: Icons.star_outline,
                  railTooltip: strings.sidebarShow,
                  onExpand: () => setState(() => _sidebarOpen = true),
                  onDrag: (delta) {
                    final next = (_sidebarWidth + delta).clamp(200.0, 300.0);
                    if (delta < 0 && next <= 202) {
                      setState(() => _sidebarOpen = false);
                      return;
                    }
                    setState(() => _sidebarWidth = next);
                  },
                  child: _FavoritesSidebar(
                    all: all,
                    filter: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                    onCollapse: () => setState(() => _sidebarOpen = false),
                  ),
                ),
                Expanded(child: content),
              ],
            );
          },
        );
      },
    );
  }
}

class _FavoritesSidebar extends StatelessWidget {
  const _FavoritesSidebar({
    required this.all,
    required this.filter,
    required this.onSelected,
    required this.onCollapse,
  });

  final List<Favorite> all;
  final FavoriteKind? filter;
  final ValueChanged<FavoriteKind?> onSelected;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final entries = all.where((f) => f.kind == FavoriteKind.entry).length;
    final references = all
        .where((f) => f.kind == FavoriteKind.reference)
        .length;
    final items = <(String, int, FavoriteKind?)>[
      (strings.favoritesAll, all.length, null),
      (strings.favoritesEntries, entries, FavoriteKind.entry),
      (strings.favoritesReferences, references, FavoriteKind.reference),
    ];
    return ColoredBox(
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.star_outline,
                  size: 18,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 7),
                Text(
                  strings.favoritesTitle,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                selected: filter == item.$3,
                selectedTileColor: palette.accent.withValues(alpha: 0.10),
                leading: Icon(
                  item.$3 == null
                      ? Icons.select_all
                      : item.$3 == FavoriteKind.entry
                      ? Icons.science_outlined
                      : Icons.menu_book_outlined,
                  size: 18,
                ),
                title: Text(item.$1),
                trailing: Text(
                  '${item.$2}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
                onTap: () => onSelected(item.$3),
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.favorite});

  final Favorite favorite;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final stale =
        favorite.snapshotHash.isNotEmpty &&
        favorite.snapshotHash != scope.snapshotHash;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider),
      ),
      child: ListTile(
        title: DescriptionText(
          favorite.kind == FavoriteKind.reference
              ? cleanReferenceTitle(favorite.title)
              : favorite.title,
          maxLines: 2,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              favorite.subtitle,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            if (stale)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: MetaChip(
                  strings.favoritesNeedsReselect,
                  tone: BadgeTone.warning,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: strings.favoritesRemove,
              icon: const Icon(Icons.star, size: 19),
              onPressed: () async {
                await scope.store.removeFavorite(favorite.key);
                if (!context.mounted) return;
                showUndoSnackBar(
                  ScaffoldMessenger.of(context),
                  message: strings.favoritesRemoved,
                  undoLabel: strings.favoritesUndo,
                  onUndo: () => scope.store.toggleFavorite(favorite),
                );
              },
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () {
          if (favorite.kind == FavoriteKind.reference &&
              favorite.referenceId != null) {
            AppNav.openReference(context, favorite.referenceId!);
          } else if (favorite.pdgid != null) {
            AppNav.openPdgid(context, favorite.pdgid!);
          }
        },
      ),
    );
  }
}
