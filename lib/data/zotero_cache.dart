import '../core/app_paths.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'zotero_bridge.dart';

class ZoteroCacheException implements Exception {
  const ZoteroCacheException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A compact local index of Zotero items.
///
/// Building this index is explicit: it walks the read-only Zotero local API
/// once, then INSPIRE result lists can mark "in Zotero" and open items without
/// one HTTP lookup per row.
class ZoteroCacheIndex {
  ZoteroCacheIndex({
    required this.builtAt,
    required this.sourceItems,
    required this.indexedItems,
    required Map<String, String> recidKeys,
    required Map<String, String> doiKeys,
    required Map<String, String> arxivKeys,
    required Map<String, String> titles,
  }) : recidKeys = Map.unmodifiable(recidKeys),
       doiKeys = Map.unmodifiable(doiKeys),
       arxivKeys = Map.unmodifiable(arxivKeys),
       titles = Map.unmodifiable(titles);

  static const int _formatVersion = 1;

  /// The automatic updater rebuilds the index at most once per this interval.
  static const Duration refreshInterval = Duration(hours: 24);

  final DateTime builtAt;
  final int sourceItems;
  final int indexedItems;
  final Map<String, String> recidKeys;
  final Map<String, String> doiKeys;
  final Map<String, String> arxivKeys;
  final Map<String, String> titles;

  /// True when the index is older than [refreshInterval].
  bool get isStale => DateTime.now().isAfter(builtAt.add(refreshInterval));

  String? findItemKey({String? recid, String? doi, String? arxivId}) {
    final recidKey = recid?.trim() ?? '';
    if (recidKey.isNotEmpty) {
      final key = recidKeys[recidKey];
      if (key != null && key.isNotEmpty) return key;
    }
    final doiKey = ZoteroBridge.normalizeDoi(doi ?? '');
    if (doiKey.isNotEmpty) {
      final key = doiKeys[doiKey];
      if (key != null && key.isNotEmpty) return key;
    }
    final arxivKey = ZoteroBridge.normalizeArxiv(arxivId ?? '');
    if (arxivKey.isNotEmpty) {
      final key = arxivKeys[arxivKey];
      if (key != null && key.isNotEmpty) return key;
    }
    return null;
  }

  String? titleFor(String itemKey) {
    final title = titles[itemKey]?.trim() ?? '';
    return title.isEmpty ? null : title;
  }

  static Future<File> defaultFile() async {
    final support = await appSupportDirectory();
    return File('${support.path}/ParticleDesk/zotero_index.json');
  }

  static Future<ZoteroCacheIndex?> load({File? file}) async {
    try {
      final target = file ?? await defaultFile();
      if (!await target.exists()) return null;
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      if (map['version'] != _formatVersion) return null;
      Map<String, String> stringMap(Object? value) {
        if (value is! Map) return const <String, String>{};
        return {
          for (final entry in value.entries)
            entry.key.toString(): entry.value.toString(),
        };
      }

      final builtAt = DateTime.tryParse(map['builtAt']?.toString() ?? '');
      if (builtAt == null) return null;
      return ZoteroCacheIndex(
        builtAt: builtAt.toLocal(),
        sourceItems: (map['sourceItems'] as num?)?.toInt() ?? 0,
        indexedItems: (map['indexedItems'] as num?)?.toInt() ?? 0,
        recidKeys: stringMap(map['recid']),
        doiKeys: stringMap(map['doi']),
        arxivKeys: stringMap(map['arxiv']),
        titles: stringMap(map['titles']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> save({File? file}) async {
    final target = file ?? await defaultFile();
    await target.parent.create(recursive: true);
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': _formatVersion,
      'builtAt': builtAt.toUtc().toIso8601String(),
      'sourceItems': sourceItems,
      'indexedItems': indexedItems,
      'recid': recidKeys,
      'doi': doiKeys,
      'arxiv': arxivKeys,
      'titles': titles,
    });
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
    return target;
  }
}

/// Builds [ZoteroCacheIndex] from the local read-only Zotero API.
class ZoteroCacheBuilder {
  static const _base = 'http://127.0.0.1:23119';
  static const _pageSize = 100;

  static Future<ZoteroCacheIndex> build({
    void Function(int fetched, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..idleTimeout = const Duration(seconds: 5);
    final recidKeys = <String, String>{};
    final doiKeys = <String, String>{};
    final arxivKeys = <String, String>{};
    final titles = <String, String>{};
    var sourceItems = 0;
    var indexedItems = 0;
    var fetched = 0;
    try {
      for (var start = 0; start < 100000; start += _pageSize) {
        if (isCancelled?.call() == true) {
          throw const ZoteroCacheException('已取消');
        }
        final uri = Uri.parse(
          '$_base/api/users/0/items/top?limit=$_pageSize&start=$start&format=json',
        );
        final response = await _get(client, uri);
        if (response.statusCode != 200) {
          throw ZoteroCacheException('Zotero 返回 HTTP ${response.statusCode}');
        }
        final totalHeader = response.headers.value('total-results');
        final total = int.tryParse(totalHeader ?? '');
        if (total != null && total > 0) sourceItems = total;
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is! List) {
          throw const ZoteroCacheException('Zotero 返回了无法识别的数据');
        }
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final data = raw['data'];
          final key = raw['key']?.toString() ?? '';
          if (key.isEmpty || data is! Map) continue;
          final item = Map<String, Object?>.from(data);
          final itemType = item['itemType']?.toString() ?? '';
          if (itemType == 'attachment' || itemType == 'note') continue;
          final recid = ZoteroBridge.extractInspireRecid(item);
          final doi = ZoteroBridge.extractDoi(item);
          final arxiv = ZoteroBridge.extractArxiv(item);
          if (recid == null && doi == null && arxiv == null) continue;
          indexedItems++;
          if (recid != null) recidKeys.putIfAbsent(recid, () => key);
          if (doi != null) doiKeys.putIfAbsent(doi, () => key);
          if (arxiv != null) arxivKeys.putIfAbsent(arxiv, () => key);
          final title = item['title']?.toString().trim() ?? '';
          if (title.isNotEmpty) titles.putIfAbsent(key, () => title);
        }
        fetched += decoded.length;
        onProgress?.call(fetched, sourceItems);
        if (decoded.length < _pageSize) break;
      }
      if (indexedItems == 0) {
        throw const ZoteroCacheException(
          'Zotero 中没有找到带 INSPIRE、DOI 或 arXiv 标识的条目',
        );
      }
      return ZoteroCacheIndex(
        builtAt: DateTime.now(),
        sourceItems: sourceItems == 0 ? fetched : sourceItems,
        indexedItems: indexedItems,
        recidKeys: recidKeys,
        doiKeys: doiKeys,
        arxivKeys: arxivKeys,
        titles: titles,
      );
    } on TimeoutException {
      throw const ZoteroCacheException('连接 Zotero 超时');
    } on SocketException {
      throw const ZoteroCacheException('无法连接 Zotero；请先启动 Zotero');
    } finally {
      client.close(force: true);
    }
  }

  static Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Particle Library/0.1 (Zotero index)',
    );
    return request.close();
  }
}

/// Rebuilds the local Zotero index when it is missing or older than one day.
///
/// This is a speed cache for large libraries, never a prerequisite for the
/// single-item Zotero actions. Failures leave the previous index untouched.
class ZoteroIndexAutoUpdater {
  ZoteroIndexAutoUpdater._();

  static Future<ZoteroCacheIndex?>? _inFlight;

  /// Returns the cached index, rebuilding it only when due.
  static Future<ZoteroCacheIndex?> updateIfDue() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _run();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    }).ignore();
    return future;
  }

  static Future<ZoteroCacheIndex?> _run() async {
    if (!ZoteroBridge.isSupportedPlatform) return null;
    final previous = await ZoteroCacheIndex.load();
    if (previous != null && !previous.isStale) return previous;
    final attemptFile = await _attemptFile();
    final lastAttempt = await _readAttempt(attemptFile);
    // A failed scan (for example, a library with no identifiable items) must
    // not be repeated on every launch.
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) <
            ZoteroCacheIndex.refreshInterval) {
      return previous;
    }
    if (!await const ZoteroBridge().isAvailable()) return previous;
    await _markAttempt(attemptFile);
    final index = await ZoteroCacheBuilder.build();
    await index.save();
    return index;
  }

  /// Allows the next automatic update to run immediately after a manual clear.
  static Future<void> clearAttempt() async {
    try {
      final file = await _attemptFile();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The marker is only a throttle; a leftover one cannot corrupt data.
    }
  }

  static Future<File> _attemptFile() async {
    final indexFile = await ZoteroCacheIndex.defaultFile();
    return File('${indexFile.path}.attempt');
  }

  static Future<DateTime?> _readAttempt(File file) async {
    try {
      if (!await file.exists()) return null;
      return DateTime.tryParse(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _markAttempt(File file) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        DateTime.now().toUtc().toIso8601String(),
        flush: true,
      );
    } catch (_) {
      // Best effort; without the marker the next launch may retry once.
    }
  }
}
