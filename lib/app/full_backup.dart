import '../core/app_paths.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import '../data/review_cache.dart';
import '../features/notes/notes_format.dart';
import '../notes/notes.dart';
import '../user/user_store.dart';

/// Versioned full backup containing user settings/favorites, notes (including
/// PDF annotation anchors) and cached PDG review PDFs.
class FullBackup {
  static const String format = 'particle-library.full-backup.v1';

  static Future<FullBackupExport> export({
    required UserStore user,
    required NotesStore? notes,
    required String destinationPath,
    Directory? reviewRegionsDirectory,
  }) async {
    final notePayload = notes == null
        ? <String, Object?>{'notes': <Object?>[]}
        : Map<String, Object?>.from(
            jsonDecode(
              notesExportJson(
                await notes.allForExport(includeDeleted: true),
                collections: await notes.collections(),
              ),
            ) as Map,
          );
    _makeRegionPathsPortable(notePayload);
    final requiredRegionNames = _regionBasenames(notePayload);
    final payload = <String, Object?>{
      'format': format,
      'formatVersion': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': user.exportData(),
      'notes': notePayload,
    };
    final encoder = ZipFileEncoder();
    var pdfs = 0;
    var regions = 0;
    try {
      encoder.create(destinationPath);
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      encoder.addArchiveFile(ArchiveFile('backup.json', bytes.length, bytes));
      try {
        final cache = await ReviewCache.open();
        if (await cache.rootDirectory.exists()) {
          await for (final entity in cache.rootDirectory.list(
            recursive: true,
          )) {
            if (entity is! File ||
                !entity.path.toLowerCase().endsWith('.pdf')) {
              continue;
            }
            final name = entity.uri.pathSegments.last;
            await encoder.addFile(entity, 'reviews/$name');
            pdfs++;
          }
        }
      } catch (_) {
        // A missing/unreadable cache does not prevent the data backup.
      }
      final includedRegions = <String>{};
      Directory? regionsDirectory;
      try {
        regionsDirectory = await _regionsDirectory(reviewRegionsDirectory);
      } catch (_) {
        if (requiredRegionNames.isNotEmpty) rethrow;
      }
      if (regionsDirectory != null && await regionsDirectory.exists()) {
        await for (final entity in regionsDirectory.list()) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.png')) {
            continue;
          }
          final name = entity.uri.pathSegments.last;
          await encoder.addFile(entity, 'regions/$name');
          includedRegions.add(name);
          regions++;
        }
      }
      final missing = requiredRegionNames.difference(includedRegions);
      if (missing.isNotEmpty) {
        throw FormatException('完整备份缺少区域截图：${missing.join(', ')}');
      }
      await encoder.close();
      return FullBackupExport(
        notes: notes == null ? 0 : (notePayload['notes'] as List).length,
        pdfs: pdfs,
        regions: regions,
      );
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      try {
        final partial = File(destinationPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<FullBackupImport> import({
    required UserStore user,
    required NotesStore? notes,
    required String sourcePath,
    Directory? reviewRegionsDirectory,
  }) async {
    final file = File(sourcePath);
    final bytes = await file.readAsBytes();
    Map<String, Object?> payload;
    final entries = <String, Uint8List>{};
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      final archive = ZipDecoder().decodeStream(InputFileStream(file.path));
      ArchiveFile? backup;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name == 'backup.json') {
          backup = entry;
        } else if ((entry.name.startsWith('reviews/') &&
                entry.name.toLowerCase().endsWith('.pdf')) ||
            (entry.name.startsWith('regions/') &&
                entry.name.toLowerCase().endsWith('.png'))) {
          final data = entry.readBytes();
          if (data != null) entries[entry.name] = data;
        }
      }
      if (backup == null) {
        throw const FormatException('备份中缺少 backup.json');
      }
      final decoded = jsonDecode(utf8.decode(backup.readBytes()!));
      if (decoded is! Map) throw const FormatException('备份 JSON 无效');
      payload = Map<String, Object?>.from(decoded);
    } else {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('备份 JSON 无效');
      payload = Map<String, Object?>.from(decoded);
    }

    final isFull = payload['format'] == format;
    if (isFull &&
        payload['formatVersion'] != 1 &&
        payload['formatVersion'] != 2) {
      throw const FormatException('不支持的完整备份版本');
    }
    final rawNotes = payload['notes'];
    final regionPaths = <String, String>{};
    if (entries.keys.any((name) => name.startsWith('regions/'))) {
      final regionsDirectory = await _regionsDirectory(reviewRegionsDirectory);
      for (final name in entries.keys.where(
        (name) => name.startsWith('regions/'),
      )) {
        regionPaths[name.split('/').last] =
            '${regionsDirectory.path}/${name.split('/').last}';
      }
      _rewriteRegionPaths(rawNotes, regionPaths);
    }
    var importedNotes = 0;
    var renamedCollections = const <String>[];
    if (rawNotes != null && notes != null) {
      final result = await notes.importJson(rawNotes);
      importedNotes = result.added;
      renamedCollections = result.renamedCollections;
    }
    // Import notes first: a malformed notes payload must not overwrite the
    // user's settings before it is rejected.
    final rawUser = payload['user'];
    if (isFull && rawUser is Map) {
      await user.importData(Map<String, Object?>.from(rawUser));
    }
    var restoredPdfs = 0;
    var restoredRegions = 0;
    if (entries.isNotEmpty) {
      final hasPdfs = entries.keys.any((name) => name.startsWith('reviews/'));
      final hasRegions = entries.keys.any(
        (name) => name.startsWith('regions/'),
      );
      Directory? cacheRoot;
      if (hasPdfs) {
        final cache = await ReviewCache.open();
        await cache.rootDirectory.create(recursive: true);
        cacheRoot = cache.rootDirectory;
      }
      final regionsDirectory = hasRegions
          ? await _regionsDirectory(reviewRegionsDirectory)
          : null;
      if (regionsDirectory != null) {
        await regionsDirectory.create(recursive: true);
      }
      for (final entry in entries.entries) {
        final name = entry.key.split('/').last;
        if (name.isEmpty || name.contains('..')) continue;
        final isRegion = entry.key.startsWith('regions/');
        final root = isRegion ? regionsDirectory : cacheRoot;
        if (root == null) continue;
        final target = File('${root.path}/$name');
        await target.writeAsBytes(entry.value, flush: true);
        if (isRegion) {
          regionPaths[name] = target.path;
          restoredRegions++;
        } else {
          restoredPdfs++;
        }
      }
    }
    return FullBackupImport(
      full: isFull,
      notes: importedNotes,
      pdfs: restoredPdfs,
      regions: restoredRegions,
      renamedCollections: renamedCollections,
    );
  }

  static void _makeRegionPathsPortable(Object? value) {
    if (value is Map) {
      for (final entry in value.entries.toList()) {
        final key = entry.key.toString();
        final item = entry.value;
        if (key == 'imagePath' && item is String && item.isNotEmpty) {
          value[entry.key] = item.split(RegExp(r'[\\/]')).last;
        } else {
          _makeRegionPathsPortable(item);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _makeRegionPathsPortable(item);
      }
    }
  }

  static Set<String> _regionBasenames(Object? value) {
    final names = <String>{};
    void walk(Object? item) {
      if (item is Map) {
        final imagePath = item['imagePath']?.toString() ?? '';
        final name = imagePath.split(RegExp(r'[\\/]')).last;
        if (name.isNotEmpty) names.add(name);
        for (final child in item.values) {
          walk(child);
        }
      } else if (item is List) {
        for (final child in item) {
          walk(child);
        }
      }
    }

    walk(value);
    return names;
  }

  static void _rewriteRegionPaths(Object? value, Map<String, String> paths) {
    if (value is Map) {
      final imagePath = value['imagePath']?.toString() ?? '';
      final base = imagePath.split(RegExp(r'[\\/]')).last;
      final replacement = paths[base];
      if (replacement != null && value['imagePath'] != replacement) {
        value['imagePath'] = replacement;
      }
      for (final item in value.values) {
        if (item is Map || item is List) _rewriteRegionPaths(item, paths);
      }
    } else if (value is List) {
      for (final item in value) {
        if (item is Map || item is List) _rewriteRegionPaths(item, paths);
      }
    }
  }

  static Future<Directory> _regionsDirectory(Directory? override) async {
    if (override != null) return override;
    final support = await appSupportDirectory();
    return Directory('${support.path}/ParticleDesk/review_regions');
  }
}

class FullBackupExport {
  const FullBackupExport({
    required this.notes,
    required this.pdfs,
    this.regions = 0,
  });

  final int notes;
  final int pdfs;
  final int regions;
}

class FullBackupImport {
  const FullBackupImport({
    required this.full,
    required this.notes,
    required this.pdfs,
    this.regions = 0,
    this.renamedCollections = const <String>[],
  });

  final bool full;
  final int notes;
  final int pdfs;
  final int regions;
  final List<String> renamedCollections;
}
