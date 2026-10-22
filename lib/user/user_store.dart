import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_paths.dart';

enum FavoriteKind { entry, reference }

class Favorite {
  const Favorite({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.snapshotHash,
    required this.createdAt,
    this.pdgid,
    this.referenceId,
  });

  final FavoriteKind kind;
  final String title;
  final String subtitle;
  final String snapshotHash;
  final DateTime createdAt;
  final String? pdgid;
  final int? referenceId;

  String get key =>
      kind == FavoriteKind.entry ? 'entry|$pdgid' : 'reference|$referenceId';

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'title': title,
    'subtitle': subtitle,
    'snapshot': snapshotHash,
    'createdAt': createdAt.toIso8601String(),
    if (pdgid != null) 'pdgid': pdgid,
    if (referenceId != null) 'referenceId': referenceId,
  };

  static Favorite? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    FavoriteKind? kind;
    for (final candidate in FavoriteKind.values) {
      if (candidate.name == map['kind']) kind = candidate;
    }
    if (kind == null) return null;
    return Favorite(
      kind: kind,
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      snapshotHash: map['snapshot']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      pdgid: map['pdgid']?.toString(),
      referenceId: map['referenceId'] is num
          ? (map['referenceId'] as num).toInt()
          : int.tryParse(map['referenceId']?.toString() ?? ''),
    );
  }
}

class RecentQuery {
  const RecentQuery({
    required this.query,
    required this.scope,
    required this.at,
  });

  final String query;
  final String scope;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'query': query,
    'scope': scope,
    'at': at.toIso8601String(),
  };

  static RecentQuery? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final query = map['query']?.toString() ?? '';
    if (query.isEmpty) return null;
    return RecentQuery(
      query: query,
      scope: map['scope']?.toString() ?? 'all',
      at:
          DateTime.tryParse(map['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CachedReferenceTitle {
  const CachedReferenceTitle({
    required this.title,
    required this.source,
    required this.fetchedAt,
  });

  final String title;
  final String source;
  final DateTime fetchedAt;
}

class AppSettings {
  const AppSettings({
    this.theme = 'system',
    this.locale = 'system',
    this.textScale = 1.0,
    this.detailedMode = true,
    this.sidebarMode = 'auto',
    this.noteLinkMode = 'page',
    this.lastUpdateCheck = '',
    this.autoUpdateZoteroIndex = true,
    this.zoteroEnabled = true,
    this.shortcuts = const <String, String>{},
  });

  final String theme;
  final String locale;
  final double textScale;
  final bool detailedMode;
  final String sidebarMode;

  /// How a link inside a note opens: `page` navigates to the PDG page,
  /// `sidebar` previews it beside the note.
  final String noteLinkMode;

  /// Local date (YYYY-MM-DD) of the last automatic update check.
  final String lastUpdateCheck;

  /// Rebuild the local Zotero item index at most once per day.
  final bool autoUpdateZoteroIndex;

  /// Whether the optional Zotero integration is enabled at all.
  final bool zoteroEnabled;

  /// Per-command shortcut overrides keyed by [AppShortcutCommand.id].
  ///
  /// A missing key means the platform default; the sentinel `off` disables
  /// the command. Values are [AppShortcutBinding.encode] strings.
  final Map<String, String> shortcuts;

  AppSettings copyWith({
    String? theme,
    String? locale,
    double? textScale,
    bool? detailedMode,
    String? sidebarMode,
    String? noteLinkMode,
    String? lastUpdateCheck,
    bool? autoUpdateZoteroIndex,
    bool? zoteroEnabled,
    Map<String, String>? shortcuts,
  }) => AppSettings(
    theme: theme ?? this.theme,
    locale: locale ?? this.locale,
    textScale: textScale ?? this.textScale,
    detailedMode: detailedMode ?? this.detailedMode,
    sidebarMode: sidebarMode ?? this.sidebarMode,
    noteLinkMode: noteLinkMode ?? this.noteLinkMode,
    lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
    autoUpdateZoteroIndex: autoUpdateZoteroIndex ?? this.autoUpdateZoteroIndex,
    zoteroEnabled: zoteroEnabled ?? this.zoteroEnabled,
    shortcuts: shortcuts ?? this.shortcuts,
  );

  Map<String, Object?> toJson() => {
    'theme': theme,
    'locale': locale,
    'textScale': textScale,
    'detailedMode': detailedMode,
    'sidebarMode': sidebarMode,
    'noteLinkMode': noteLinkMode,
    'lastUpdateCheck': lastUpdateCheck,
    'autoUpdateZoteroIndex': autoUpdateZoteroIndex,
    'zoteroEnabled': zoteroEnabled,
    'shortcuts': shortcuts,
  };

  static AppSettings fromJson(Object? value) {
    if (value is! Map) return const AppSettings();
    final map = Map<String, Object?>.from(value);
    final theme = map['theme']?.toString();
    final locale = map['locale']?.toString();
    final scale = map['textScale'] is num
        ? (map['textScale'] as num).toDouble()
        : double.tryParse(map['textScale']?.toString() ?? '');
    final detailed = map['detailedMode'];
    final sidebar = map['sidebarMode']?.toString();
    final noteLink = map['noteLinkMode']?.toString();
    final lastUpdate = map['lastUpdateCheck']?.toString() ?? '';
    final autoUpdateZotero = map['autoUpdateZoteroIndex'];
    final zoteroEnabled = map['zoteroEnabled'];
    final shortcuts = <String, String>{};
    final rawShortcuts = map['shortcuts'];
    if (rawShortcuts is Map) {
      for (final entry in rawShortcuts.entries) {
        final key = entry.key?.toString() ?? '';
        final value = entry.value?.toString() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) shortcuts[key] = value;
      }
    }
    return AppSettings(
      theme: theme == 'light' || theme == 'dark' ? theme! : 'system',
      locale: locale == 'zh' || locale == 'en' ? locale! : 'system',
      textScale: _normalizeTextScale(scale ?? 1.0),
      detailedMode: detailed is bool ? detailed : true,
      sidebarMode: sidebar == 'always' || sidebar == 'off' ? sidebar! : 'auto',
      noteLinkMode: noteLink == 'sidebar' ? 'sidebar' : 'page',
      lastUpdateCheck: lastUpdate,
      autoUpdateZoteroIndex: autoUpdateZotero is bool ? autoUpdateZotero : true,
      zoteroEnabled: zoteroEnabled is bool ? zoteroEnabled : true,
      shortcuts: shortcuts,
    );
  }
}

/// Device-local favorites, recent searches and settings. This is a separate
/// store from the read-only PDG snapshot. Writes are serialized and atomic:
/// a `.tmp` file is written and renamed; the previous file is kept as `.bak`.
class UserStore extends ChangeNotifier {
  UserStore._(this._file, this._data);

  final File? _file;
  final Map<String, Object?> _data;
  Future<void> _writeChain = Future.value();
  String? recoveryWarning;

  /// Reads only the saved settings for the boot screen, without opening or
  /// locking the full user store. Returns null when no settings exist yet.
  static Future<AppSettings?> previewSettings() async {
    try {
      final support = await appSupportDirectory();
      final file = File('${support.path}/ParticleDesk/user_store.json');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return AppSettings.fromJson(decoded['settings']);
    } catch (_) {
      return null;
    }
  }

  static Future<UserStore> open({String? overridePath}) async {
    File? file;
    if (overridePath != null) {
      file = File(overridePath);
    } else {
      try {
        final support = await appSupportDirectory();
        file = File('${support.path}/ParticleDesk/user_store.json');
      } catch (_) {
        file = null;
      }
    }
    final store = UserStore._(file, {});
    if (file == null) {
      store.recoveryWarning = '无法访问本机用户数据目录，设置和收藏不会保存';
    }
    await store._load();
    return store;
  }

  String? get storagePath => _file?.path;

  AppSettings get settings => AppSettings.fromJson(_data['settings']);

  Future<void> setSettings(AppSettings value) async {
    _data['settings'] = value.toJson();
    notifyListeners();
    await save();
  }

  Map<String, Object?>? reviewState(String key) {
    final raw = _data['reviewStates'];
    if (raw is! Map) return null;
    final value = raw[key];
    if (value is! Map) return null;
    return sanitizeReviewState(Map<String, Object?>.from(value));
  }

  /// Drops reading-state numbers the reader cannot use.
  ///
  /// The state also arrives through backups and files edited by hand, and JSON
  /// such as `1e999` decodes to infinity, which makes `toInt()` throw every
  /// time the review is opened. Fields that are not finite numbers in a sane
  /// range are removed so the reader falls back to its defaults; unknown keys
  /// are kept as they are.
  static Map<String, Object?> sanitizeReviewState(Map<String, Object?> state) {
    final clean = Map<String, Object?>.from(state);
    bool usable(Object? value, double min, double max) =>
        value is num && value.isFinite && value >= min && value <= max;
    void keepOnly(String key, double min, double max) {
      if (clean.containsKey(key) && !usable(clean[key], min, max)) {
        clean.remove(key);
      }
    }

    keepOnly('page', 1, 1000000);
    keepOnly('sidebarTab', 0, 100);
    keepOnly('sidebarWidth', 0, 100000);
    keepOnly('zoom', 0.1, 8);
    final scroll = clean['scroll'];
    if (clean.containsKey('scroll') &&
        !(scroll is List &&
            scroll.length == 2 &&
            usable(scroll[0], -1e7, 1e7) &&
            usable(scroll[1], -1e7, 1e7))) {
      clean.remove('scroll');
    }
    return clean;
  }

  Future<void> setReviewState(String key, Map<String, Object?> state) async {
    final raw = _data['reviewStates'];
    final states = raw is Map
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{};
    states[key] = state;
    _data['reviewStates'] = states;
    await save();
  }

  List<Favorite> get favorites {
    final raw = _data['favorites'];
    if (raw is! List) return const [];
    return [for (final item in raw) ?Favorite.fromJson(item)];
  }

  List<RecentQuery> get recents {
    final raw = _data['recents'];
    if (raw is! List) return const [];
    return [for (final item in raw) ?RecentQuery.fromJson(item)];
  }

  bool isFavorite(String key) =>
      favorites.any((favorite) => favorite.key == key);

  CachedReferenceTitle? cachedReferenceTitle(String doi) {
    final key = doi.trim().toLowerCase();
    if (key.isEmpty) return null;
    final raw = _data['referenceTitles'];
    if (raw is! Map) return null;
    final entry = raw[key];
    if (entry is! Map) return null;
    final map = Map<String, Object?>.from(entry);
    final title = map['title']?.toString() ?? '';
    if (title.isEmpty) return null;
    return CachedReferenceTitle(
      title: title,
      source: map['source']?.toString() ?? 'Crossref',
      fetchedAt:
          DateTime.tryParse(map['fetchedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<void> cacheReferenceTitle(
    String doi,
    String title, {
    String source = 'Crossref',
  }) async {
    final key = doi.trim().toLowerCase();
    final value = title.trim();
    if (key.isEmpty || value.isEmpty) return;
    final raw = _data['referenceTitles'];
    final map = raw is Map
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{};
    map[key] = {
      'title': value,
      'source': source,
      'fetchedAt': DateTime.now().toIso8601String(),
    };
    _data['referenceTitles'] = map;
    notifyListeners();
    await save();
  }

  Future<bool> toggleFavorite(Favorite favorite) async {
    final list = favorites.toList();
    final index = list.indexWhere((item) => item.key == favorite.key);
    final added = index < 0;
    if (added) {
      list.insert(0, favorite);
    } else {
      list.removeAt(index);
    }
    _data['favorites'] = [for (final item in list) item.toJson()];
    notifyListeners();
    await save();
    return added;
  }

  Future<void> removeFavorite(String key) async {
    final list = favorites.where((item) => item.key != key).toList();
    _data['favorites'] = [for (final item in list) item.toJson()];
    notifyListeners();
    await save();
  }

  Future<void> addRecent(String query, String scope) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final list = recents
        .where((item) => !(item.query == trimmed && item.scope == scope))
        .toList();
    list.insert(
      0,
      RecentQuery(query: trimmed, scope: scope, at: DateTime.now()),
    );
    _data['recents'] = [for (final item in list.take(20)) item.toJson()];
    notifyListeners();
    await save();
  }

  Future<void> removeRecent(String query, String scope) async {
    final list = recents
        .where((item) => !(item.query == query && item.scope == scope))
        .toList();
    if (list.length == recents.length) return;
    _data['recents'] = [for (final item in list) item.toJson()];
    notifyListeners();
    await save();
  }

  Future<void> clearRecents() async {
    _data['recents'] = <Object?>[];
    notifyListeners();
    await save();
  }

  Map<String, Object?> exportData() {
    final encoded = jsonDecode(jsonEncode(_data));
    return encoded is Map
        ? Map<String, Object?>.from(encoded)
        : <String, Object?>{};
  }

  /// Restores a full backup. Settings/favorites are merged rather than
  /// deleting anything local.
  Future<void> importData(Map<String, Object?> incoming) async {
    final rawSettings = incoming['settings'];
    if (rawSettings is Map) {
      final restored = AppSettings.fromJson(
        Map<String, Object?>.from(rawSettings),
      );
      _data['settings'] = restored.toJson();
    }
    final rawFavorites = incoming['favorites'];
    if (rawFavorites is List) {
      final merged = <String, Map<String, Object?>>{
        for (final item in favorites) item.key: item.toJson(),
      };
      for (final item in rawFavorites) {
        if (item is! Map) continue;
        final map = Map<String, Object?>.from(item);
        final key = map['key']?.toString();
        if (key != null && key.isNotEmpty) merged.putIfAbsent(key, () => map);
      }
      _data['favorites'] = merged.values.toList(growable: false);
    }
    final rawRecents = incoming['recents'];
    if (rawRecents is List) {
      final merged = <String, Map<String, Object?>>{};
      for (final item in [
        ...recents.map((item) => item.toJson()),
        ...rawRecents,
      ]) {
        if (item is! Map) continue;
        final map = Map<String, Object?>.from(item);
        final key = '${map['query']}\u0000${map['scope']}';
        merged.putIfAbsent(key, () => map);
      }
      _data['recents'] = merged.values.take(20).toList(growable: false);
    }
    final rawStates = incoming['reviewStates'];
    if (rawStates is Map) {
      final existing = _data['reviewStates'];
      final merged = <String, Object?>{
        if (existing is Map)
          for (final entry in existing.entries)
            entry.key.toString(): entry.value,
      };
      for (final entry in rawStates.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty || value is! Map) continue;
        merged.putIfAbsent(
          key,
          () => sanitizeReviewState(Map<String, Object?>.from(value)),
        );
      }
      _data['reviewStates'] = merged;
    }
    final rawTitles = incoming['referenceTitles'];
    if (rawTitles is Map) {
      final merged = <String, Object?>{
        for (final entry
            in ((_data['referenceTitles'] as Map?) ?? const {}).entries)
          entry.key.toString(): entry.value,
      };
      for (final entry in rawTitles.entries) {
        merged.putIfAbsent(entry.key.toString(), () => entry.value);
      }
      _data['referenceTitles'] = merged;
    }
    notifyListeners();
    await save();
  }

  Future<void> _load() async {
    final file = _file;
    if (file == null) return;
    final main = await _tryRead(file);
    if (main != null) {
      _data.addAll(main);
      return;
    }
    final backup = File('${file.path}.bak');
    final fromBackup = await _tryRead(backup);
    if (fromBackup != null) {
      _data.addAll(fromBackup);
      recoveryWarning = '从备份恢复用户数据';
      return;
    }
    if (await file.exists()) {
      recoveryWarning = '用户数据文件无法读取，已从空数据开始';
    }
  }

  Future<Map<String, Object?>?> _tryRead(File file) async {
    try {
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> save() {
    final file = _file;
    if (file == null) return Future.value();
    _writeChain = _writeChain.then((_) async {
      try {
        final dir = file.parent;
        if (!await dir.exists()) await dir.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(jsonEncode(_data), flush: true);
        if (await file.exists()) {
          try {
            await file.copy('${file.path}.bak');
          } catch (_) {}
        }
        await tmp.rename(file.path);
      } catch (_) {
        recoveryWarning = '本机用户数据写入失败，设置和收藏可能无法保存';
        notifyListeners();
      }
    });
    return _writeChain;
  }
}

const List<double> _textScaleLevels = [0.8, 0.9, 1.0, 1.1, 1.2];

double _normalizeTextScale(double value) {
  final clamped = value.clamp(0.8, 1.2).toDouble();
  var best = _textScaleLevels.first;
  for (final level in _textScaleLevels) {
    if ((level - clamped).abs() < (best - clamped).abs()) best = level;
  }
  return best;
}
