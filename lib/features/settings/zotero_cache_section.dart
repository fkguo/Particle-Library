import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_theme.dart';
import '../../data/zotero_cache.dart';
import '../common/ui.dart';

class ZoteroCacheSection extends StatefulWidget {
  const ZoteroCacheSection({super.key, this.embedded = false});

  /// When embedded, the cache controls live inside the Zotero integration
  /// card instead of rendering their own [SectionCard].
  final bool embedded;

  @override
  State<ZoteroCacheSection> createState() => _ZoteroCacheSectionState();
}

class _ZoteroCacheSectionState extends State<ZoteroCacheSection> {
  ZoteroCacheIndex? _index;
  bool _loading = true;
  bool _building = false;
  int _fetched = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final index = await ZoteroCacheIndex.load();
    if (!mounted) return;
    setState(() {
      _index = index;
      _loading = false;
    });
  }

  Future<void> _build() async {
    if (_building) return;
    setState(() {
      _building = true;
      _error = null;
      _fetched = 0;
      _total = 0;
    });
    try {
      final index = await ZoteroCacheBuilder.build(
        onProgress: (fetched, total) {
          if (!mounted) return;
          setState(() {
            _fetched = fetched;
            _total = total;
          });
        },
      );
      await index.save();
      if (!mounted) return;
      setState(() {
        _index = index;
        _building = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppScope.of(context).strings.settingsZoteroCacheDone),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _error = errorText(error, AppScope.of(context).strings);
      });
    }
  }

  Future<void> _clear() async {
    final file = await ZoteroCacheIndex.defaultFile();
    if (await file.exists()) await file.delete();
    await ZoteroIndexAutoUpdater.clearAttempt();
    if (!mounted) return;
    setState(() => _index = null);
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.of(context).strings;
    final palette = context.palette;
    final content = _content(context);
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 28),
          Row(
            children: [
              Icon(
                Icons.storage_outlined,
                size: 18,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.settingsZoteroCache,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (_building)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          content,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, 0),
      child: SectionCard(
        title: strings.settingsZoteroCache,
        trailing: _building
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        child: content,
      ),
    );
  }

  Widget _content(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = context.palette;
    final stale = _index != null && _index!.isStale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_index == null)
          Text(
            strings.settingsZoteroCacheEmpty,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          )
        else
          Text(
            strings.settingsZoteroCacheStatus(
              _index!.indexedItems,
              _formatDate(_index!.builtAt),
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        if (stale) ...[
          const SizedBox(height: 4),
          Text(
            strings.settingsZoteroCacheStale,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.warning),
          ),
        ],
        if (_building) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _total > 0 ? (_fetched / _total).clamp(0.0, 1.0) : null,
            minHeight: 3,
          ),
          const SizedBox(height: 4),
          Text(
            strings.settingsZoteroCacheBuilding(_fetched, _total),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            '${strings.settingsZoteroCacheFailed}: $_error',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.error),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              onPressed: _building || _loading ? null : _build,
              icon: const Icon(Icons.sync, size: 16),
              label: Text(
                _index == null
                    ? strings.settingsZoteroCacheBuild
                    : strings.settingsZoteroCacheUpdate,
              ),
            ),
            if (_index != null)
              TextButton.icon(
                onPressed: _building ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(strings.settingsZoteroCacheClear),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(strings.settingsZoteroCacheAutoUpdate),
          subtitle: Text(
            strings.settingsZoteroCacheAutoUpdateHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          value: scope.settings.autoUpdateZoteroIndex,
          onChanged: (value) => scope.settings.setAutoUpdateZoteroIndex(value),
        ),
        const SizedBox(height: 6),
        Text(
          strings.settingsZoteroCacheHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
