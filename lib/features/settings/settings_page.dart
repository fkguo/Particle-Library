import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/error_text.dart';
import '../../app/app_strings.dart';
import '../../app/build_info.dart';
import '../../app/full_backup.dart';
import '../../app/settings_controller.dart';
import '../../app/update_checker.dart';
import '../../app/app_theme.dart';
import 'shortcut_settings_section.dart';
import 'zotero_cache_section.dart';
import '../reference/zotero_setup_dialog.dart';
import '../../data/zotero_bridge.dart';
import '../../data/zotero_inspire_api.dart';
import '../../data/pdg_database.dart';
import '../../domain/labels.dart';
import '../common/export_file.dart';
import '../common/page.dart';
import '../common/raw_fields.dart';
import '../common/ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<SnapshotStats> _statsFuture;
  Future<List<TableStat>>? _tablesFuture;
  bool _backingUpNotes = false;
  bool _showTables = false;
  bool _showCodes = false;
  bool _initialized = false;
  bool _checkingUpdate = false;
  String? _updateStatus;
  bool _fullBackupBusy = false;
  ZoteroInspireStatus? _zoteroInspireStatus;
  bool? _zoteroRunning;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _statsFuture = AppScope.of(context).database.snapshotStats();
    if (ZoteroBridge.isSupportedPlatform &&
        AppScope.of(context).settings.zoteroEnabled) {
      unawaited(_probeZoteroInspire());
    }
  }

  Future<void> _probeZoteroInspire() async {
    final running = await const ZoteroBridge().isAvailable();
    final status = await const ZoteroInspireApi().probe();
    if (!mounted) return;
    setState(() {
      _zoteroRunning = running;
      _zoteroInspireStatus = status;
    });
  }

  Future<void> _openAppStore() async {
    final url = UpdateChecker.appStoreUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    final strings = AppScope.of(context).strings;
    if (UpdateChecker.isAppStoreManaged) {
      setState(() => _updateStatus = strings.settingsUpdateAppStore);
      return;
    }
    setState(() {
      _checkingUpdate = true;
      _updateStatus = strings.settingsCheckingUpdates;
    });
    try {
      final update = await UpdateChecker.check();
      if (!mounted) return;
      if (update == null) {
        setState(() => _updateStatus = strings.settingsUpdateCurrent);
      } else {
        setState(() => _updateStatus = null);
        await showUpdateAvailableDialog(context, strings, update);
      }
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      debugPrint('Update check failed: ${errorText(error, strings)}');
      setState(() => _updateStatus = strings.settingsUpdateUnavailable);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Update check failed: ${errorText(error, strings)}');
      setState(() => _updateStatus = strings.settingsUpdateUnavailable);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _exportFullBackup() async {
    if (_fullBackupBusy) return;
    final scope = AppScope.of(context);
    final strings = scope.strings;
    setState(() => _fullBackupBusy = true);
    try {
      final name =
          'ParticleLibrary-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip';
      final mobile = Platform.isAndroid || Platform.isIOS;
      final path = mobile
          ? await temporaryExportPath(name)
          : (await getSaveLocation(
              suggestedName: name,
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: 'Particle Library backup',
                  extensions: ['zip'],
                ),
              ],
            ))?.path;
      if (path == null) return;
      final result = await FullBackup.export(
        user: scope.store,
        notes: scope.notes,
        destinationPath: path,
      );
      if (mobile) await shareFile(File(path), mimeType: 'application/zip');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsFullBackupDone}: ${strings.settingsFullBackupSummary(result.notes, result.pdfs, result.regions)}'
            '${result.missingRegions == 0 ? '' : '\n${strings.settingsFullBackupMissingRegions(result.missingRegions)}'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsFullBackupFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullBackupBusy = false);
    }
  }

  Future<void> _importFullBackup() async {
    if (_fullBackupBusy) return;
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Particle Library backup',
          extensions: ['zip', 'json'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.settingsFullBackupImport),
        content: Text(strings.settingsFullBackupConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _fullBackupBusy = true);
    try {
      final result = await FullBackup.import(
        user: scope.store,
        notes: scope.notes,
        sourcePath: file.path,
      );
      scope.settings.reloadFromStore();
      scope.notesChanges.value++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsFullBackupImported}: ${strings.settingsFullBackupSummary(result.notes, result.pdfs, result.regions)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsFullBackupFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullBackupBusy = false);
    }
  }

  Future<void> _backupNotes() async {
    final notes = AppScope.of(context).notes;
    if (notes == null || _backingUpNotes) return;
    final strings = AppScope.of(context).strings;
    setState(() => _backingUpNotes = true);
    try {
      final dbPath = notes.storagePath;
      final parent = Directory(dbPath).parent;
      final backups = Directory('${parent.path}/backups');
      if (!await backups.exists()) await backups.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final destination = File('${backups.path}/notes-$stamp.db');
      await notes.backupTo(destination.path);
      final existing =
          backups
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.db'))
              .toList()
            ..sort(
              (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
            );
      for (final old in existing.skip(5)) {
        try {
          await old.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsNotesBackupDone}: ${destination.path}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.settingsNotesBackupFailed}: ${errorText(error, strings)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _backingUpNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final settings = scope.settings;
    final info = scope.database.info;
    final palette = context.palette;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: Insets.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.l,
                Insets.l,
                Insets.s,
              ),
              child: Text(
                strings.settingsTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (scope.store.recoveryWarning != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  0,
                  Insets.l,
                  Insets.s,
                ),
                child: MetaChip(
                  strings.localizedRecoveryWarning(
                    scope.store.recoveryWarning!,
                  ),
                  tone: BadgeTone.warning,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.settingsAppearance,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingRow(
                      label: strings.settingsTheme,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'system',
                            label: Text(strings.settingsThemeSystem),
                          ),
                          ButtonSegment(
                            value: 'light',
                            label: Text(strings.settingsThemeLight),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            label: Text(strings.settingsThemeDark),
                          ),
                        ],
                        selected: {settings.settings.theme},
                        onSelectionChanged: (value) =>
                            settings.setTheme(value.first),
                      ),
                    ),
                    _SettingRow(
                      label: strings.settingsLanguage,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'system',
                            label: Text(strings.settingsLanguageSystem),
                          ),
                          ButtonSegment(
                            value: 'zh',
                            label: Text(strings.settingsLanguageZh),
                          ),
                          ButtonSegment(
                            value: 'en',
                            label: Text(strings.settingsLanguageEn),
                          ),
                        ],
                        selected: {settings.settings.locale},
                        onSelectionChanged: (value) =>
                            settings.setLocale(value.first),
                      ),
                    ),
                    _TextSizeSetting(
                      settings: settings,
                      strings: strings,
                      palette: palette,
                    ),
                    const SizedBox(height: Insets.s),
                    _SettingRow(
                      label: strings.settingsDetailedMode,
                      child: Switch(
                        value: settings.detailedMode,
                        onChanged: (value) => settings.setDetailedMode(value),
                      ),
                    ),
                    Text(
                      strings.settingsDetailedModeHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.s),
                    _SettingRow(
                      label: strings.settingsSidebarMode,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'auto',
                            label: Text(strings.settingsSidebarAuto),
                          ),
                          ButtonSegment(
                            value: 'always',
                            label: Text(strings.settingsSidebarAlways),
                          ),
                          ButtonSegment(
                            value: 'off',
                            label: Text(strings.settingsSidebarOff),
                          ),
                        ],
                        selected: {settings.sidebarMode},
                        onSelectionChanged: (value) =>
                            settings.setSidebarMode(value.first),
                      ),
                    ),
                    Text(
                      strings.settingsSidebarHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.s),
                    _SettingRow(
                      label: strings.settingsNoteLinkMode,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'page',
                            label: Text(strings.settingsNoteLinkPage),
                          ),
                          ButtonSegment(
                            value: 'sidebar',
                            label: Text(strings.settingsNoteLinkSidebar),
                          ),
                        ],
                        selected: {settings.noteLinkMode},
                        onSelectionChanged: (value) =>
                            settings.setNoteLinkMode(value.first),
                      ),
                    ),
                    Text(
                      strings.settingsNoteLinkHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.m),
            if (defaultTargetPlatform == TargetPlatform.macOS)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: ShortcutSettingsSection(
                  settings: settings,
                  strings: strings,
                ),
              ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.settingsData,
                trailing: IconButton(
                  tooltip: strings.settingsCopyHash,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () => copyText(context, scope.snapshotHash),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataField(
                      label: strings.settingsSnapshotVersion,
                      value: 'PDG ${info.edition ?? ''}',
                    ),
                    DataField(
                      label: strings.settingsSchema,
                      value: info.schemaVersion ?? '',
                      monospace: true,
                    ),
                    DataField(
                      label: strings.settingsRelease,
                      value: info.releaseTimestamp ?? '',
                      monospace: false,
                    ),
                    DataField(
                      label: strings.settingsHash,
                      value: scope.snapshotHash,
                      monospace: true,
                    ),
                    DataField(
                      label: strings.settingsAppVersion,
                      value: appVersion,
                      monospace: true,
                    ),
                    DataField(
                      label: strings.commonSource,
                      value: info.producer ?? '',
                      monospace: false,
                    ),
                    DataField(
                      label: 'license',
                      value: info.license ?? '',
                      monospace: false,
                    ),
                    if (info.citation != null)
                      DataField(
                        label: 'citation',
                        value: plainCitation(info.citation),
                        monospace: false,
                      ),
                    const SizedBox(height: Insets.s),
                    RawFieldsPanel(fields: info.rawFields, title: 'pdginfo'),
                  ],
                ),
              ),
            ),
            if (ZoteroBridge.isSupportedPlatform) ...[
              const SizedBox(height: Insets.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.l),
                child: SectionCard(
                  title: strings.settingsZotero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.settingsZoteroEnabled),
                        subtitle: Text(
                          strings.settingsZoteroEnabledHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                        value: scope.settings.zoteroEnabled,
                        onChanged: (value) {
                          scope.settings.setZoteroEnabled(value);
                          if (value && _zoteroInspireStatus == null) {
                            unawaited(_probeZoteroInspire());
                          }
                        },
                      ),
                      if (scope.settings.zoteroEnabled &&
                          _zoteroInspireStatus != null) ...[
                        Builder(
                          builder: (context) {
                            final status = _zoteroInspireStatus!;
                            final text = status.canAdd
                                ? (status.version == null
                                      ? strings.settingsZoteroAddAvailable
                                      : strings
                                            .settingsZoteroAddAvailableVersion(
                                              status.version!,
                                            ))
                                : status.available
                                ? strings.settingsZoteroAddTooOld(
                                    status.version ?? '?',
                                  )
                                : _zoteroRunning == true
                                ? strings.settingsZoteroPluginMissing
                                : strings.settingsZoteroNotRunning;
                            return Text(
                              text,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: status.canAdd
                                        ? palette.textSecondary
                                        : palette.warning,
                                  ),
                            );
                          },
                        ),
                        if (!_zoteroInspireStatus!.canAdd)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => showZoteroInspireSetupDialog(
                                context,
                                strings: strings,
                                reason: zoteroSetupReasonFor(
                                  _zoteroInspireStatus!,
                                ),
                                currentVersion: _zoteroInspireStatus!.version,
                                zoteroRunning: _zoteroRunning == true,
                              ),
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 16,
                              ),
                              label: Text(strings.settingsZoteroInstallUpdate),
                            ),
                          ),
                      ],
                      if (scope.settings.zoteroEnabled)
                        const ZoteroCacheSection(embedded: true),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.settingsStorage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataField(
                      label: strings.settingsSnapshotFile,
                      value: _fileName(scope.services.snapshotPath),
                      monospace: true,
                    ),
                    DataField(
                      label: 'user store',
                      value: _fileName(scope.store.storagePath ?? '—'),
                      monospace: true,
                    ),
                    if (scope.notes != null) ...[
                      const SizedBox(height: Insets.s),
                      OutlinedButton.icon(
                        onPressed: _backingUpNotes ? null : _backupNotes,
                        icon: const Icon(Icons.archive_outlined, size: 17),
                        label: Text(strings.settingsNotesBackup),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.settingsNotesBackupHint,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Insets.s),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _fullBackupBusy ? null : _exportFullBackup,
                          icon: const Icon(
                            Icons.inventory_2_outlined,
                            size: 17,
                          ),
                          label: Text(strings.settingsFullBackupExport),
                        ),
                        OutlinedButton.icon(
                          onPressed: _fullBackupBusy ? null : _importFullBackup,
                          icon: const Icon(Icons.unarchive_outlined, size: 17),
                          label: Text(strings.settingsFullBackupImport),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.settingsFullBackupHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    DataField(
                      label: strings.settingsClearRecents,
                      value: '${scope.store.recents.length}',
                    ),
                    DataField(
                      label: strings.favoritesTitle,
                      value: '${scope.store.favorites.length}',
                    ),
                    const SizedBox(height: Insets.s),
                    Text(
                      strings.settingsStorageHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.s),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            content: Text(strings.settingsClearRecentsConfirm),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(strings.commonCancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(strings.commonConfirm),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await scope.store.clearRecents();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(strings.settingsClearRecentsDone),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                      label: Text(strings.settingsClearRecents),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.settingsTableStats,
                trailing: TextButton(
                  onPressed: () {
                    setState(() {
                      _showTables = !_showTables;
                      if (_showTables) {
                        _tablesFuture ??= AppScope.of(context).database
                            .tableStats();
                      }
                    });
                  },
                  child: Text(
                    _showTables
                        ? strings.commonShowLess
                        : strings.commonShowMore,
                  ),
                ),
                child: FutureBuilder<SnapshotStats>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    if (stats == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(Insets.m),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Insets.l,
                          runSpacing: Insets.s,
                          children: [
                            _Stat(
                              label: strings.entriesLabel,
                              value: stats.entries,
                            ),
                            _Stat(
                              label: strings.summariesLabel,
                              value: stats.currentSummaries,
                            ),
                            _Stat(
                              label: 'all pdgdata',
                              value: stats.allSummaries,
                            ),
                            _Stat(
                              label: strings.referencesLabel,
                              value: stats.references,
                            ),
                          ],
                        ),
                        if (_showTables) ...[
                          const SizedBox(height: Insets.m),
                          FutureBuilder<List<TableStat>>(
                            future: _tablesFuture,
                            builder: (context, snapshot) {
                              final tables = snapshot.data;
                              if (tables == null) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(Insets.s),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                children: [
                                  for (final table in tables)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              table.table,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontFamily: 'Menlo',
                                                  ),
                                            ),
                                          ),
                                          Text(
                                            '${table.rows}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.codeTableTitle,
                subtitle: strings.codeTableHint,
                trailing: TextButton(
                  onPressed: () => setState(() => _showCodes = !_showCodes),
                  child: Text(
                    _showCodes
                        ? strings.commonShowLess
                        : strings.commonShowMore,
                  ),
                ),
                child: _showCodes
                    ? Column(
                        children: [
                          for (final doc in scope.database.allDocs)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      '${doc.tableName}.${doc.columnName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontFamily: 'Menlo',
                                            fontSize: 11,
                                          ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      doc.value ?? 'NULL',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (doc.indicator.isNotEmpty)
                                          doc.indicator,
                                        doc.description,
                                      ].join(' — '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : Text(
                        '${scope.database.allDocs.length} ${strings.commonCount} · ${strings.codeTableHint}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
              ),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SectionCard(
                title: strings.settingsAbout,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.settingsAboutText),
                    const SizedBox(height: Insets.xs),
                    Text(
                      strings.settingsBuiltBy,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.s),
                    Text(
                      strings.settingsVersionValue(appVersion),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    if (buildLabel.isNotEmpty) ...[
                      const SizedBox(height: Insets.xs),
                      Text(
                        strings.settingsBuildValue(buildLabel),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Insets.xs),
                    OutlinedButton.icon(
                      onPressed: _checkingUpdate ? null : _checkUpdates,
                      icon: _checkingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt, size: 17),
                      label: Text(strings.settingsCheckUpdates),
                    ),
                    if (_updateStatus != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _updateStatus!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                    if (UpdateChecker.isAppStoreManaged &&
                        UpdateChecker.appStoreUrl != null) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _openAppStore,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(strings.settingsOpenAppStore),
                      ),
                    ],
                    const SizedBox(height: Insets.s),
                    Text(
                      strings.settingsCoverageText,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(
                      strings.settingsInspireDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: Insets.m),
                    Wrap(
                      spacing: Insets.s,
                      runSpacing: Insets.s,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _launch(
                            context,
                            'https://pdgapi.lbl.gov/doc/schema.html',
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(strings.settingsPdgApi),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _launch(
                            context,
                            'https://creativecommons.org/licenses/by/4.0/',
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(strings.settingsLicenseLink),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: strings.appName,
                            applicationVersion: appVersion,
                          ),
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 16,
                          ),
                          label: Text(strings.settingsLicenses),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _launch(
                            context,
                            'https://github.com/fkguo/Particle-Library',
                          ),
                          icon: const Icon(Icons.code, size: 16),
                          label: Text(strings.settingsSourceCode),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: Text(
                '${strings.commonSnapshot}: ${scope.snapshotHash}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final strings = AppScope.of(context).strings;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.commonError)));
      }
    }
  }
}

const List<double> _textScaleOptions = [0.8, 0.9, 1.0, 1.1, 1.2];

class _TextSizeSetting extends StatelessWidget {
  const _TextSizeSetting({
    required this.settings,
    required this.strings,
    required this.palette,
  });

  final SettingsController settings;
  final AppStrings strings;
  final AppPalette palette;

  String _label(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.settingsTextSize,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final scale in _textScaleOptions)
                ChoiceChip(
                  label: Text(_label(scale)),
                  selected: (settings.settings.textScale - scale).abs() < 0.001,
                  onSelected: (_) => settings.setTextScale(scale),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.settingsTextSizeHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

String _fileName(String path) {
  if (path == '—' || path.isEmpty) return '—';
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}
