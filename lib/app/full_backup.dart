import '../core/app_paths.dart';

import 'dart:convert';
import 'dart:io';

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
    final encoder = ZipFileEncoder();
    var pdfs = 0;
    var regions = 0;
    var missingRegions = 0;
    try {
      // Region images are listed before backup.json is written: a note can
      // point at an image that is no longer on this device (it came in from a
      // notes file made elsewhere, or the file was removed). Refusing to back
      // up at all would block every later backup, so the annotation is stored
      // as having no image and the count is reported to the caller.
      final regionFiles = <File>[];
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
          regionFiles.add(entity);
        }
      }
      final includedRegions = {
        for (final file in regionFiles) file.uri.pathSegments.last,
      };
      final missing = requiredRegionNames.difference(includedRegions);
      if (missing.isNotEmpty) {
        _markRegionImagesMissing(notePayload, missing);
        missingRegions = missing.length;
      }
      final payload = <String, Object?>{
        'format': format,
        'formatVersion': 2,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'user': user.exportData(),
        'notes': notePayload,
      };
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
      for (final file in regionFiles) {
        await encoder.addFile(file, 'regions/${file.uri.pathSegments.last}');
        regions++;
      }
      await encoder.close();
      return FullBackupExport(
        notes: notes == null ? 0 : (notePayload['notes'] as List).length,
        pdfs: pdfs,
        regions: regions,
        missingRegions: missingRegions,
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

  // Limits for what a backup may ask this device to unpack. They sit far above
  // a real backup (a review PDF is a few MB, a region screenshot well under
  // 1 MB) and only stop archives built to exhaust memory or storage.
  static const int _maxBackupJsonBytes = 64 << 20;
  static const int _maxPdfBytes = 256 << 20;
  static const int _maxPngBytes = 64 << 20;
  static const int _maxRestoredBytes = 2 << 30;
  static const int _maxRestoredFiles = 5000;

  static const List<int> _pdfSignature = [
    0x25,
    0x50,
    0x44,
    0x46,
    0x2d,
  ]; // %PDF-
  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  ];

  static Future<FullBackupImport> import({
    required UserStore user,
    required NotesStore? notes,
    required String sourcePath,
    Directory? reviewRegionsDirectory,
    Directory? reviewCacheDirectory,
  }) async {
    final file = File(sourcePath);
    Map<String, Object?> payload;
    // Archive members are unpacked one at a time into a scratch directory and
    // checked there, so a backup is judged as a whole before anything in the
    // user's data is touched and memory never holds more than one member.
    final staged = <_StagedFile>[];
    Directory? scratch;
    InputFileStream? input;
    try {
      if (await _isZip(file)) {
        input = InputFileStream(file.path);
        final archive = ZipDecoder().decodeStream(input);
        ArchiveFile? backup;
        var restoredFiles = 0;
        var restoredBytes = 0;
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final lowerName = entry.name.toLowerCase();
          if (entry.name == 'backup.json') {
            backup = entry;
            continue;
          }
          final isPdf =
              entry.name.startsWith('reviews/') && lowerName.endsWith('.pdf');
          final isRegion =
              entry.name.startsWith('regions/') && lowerName.endsWith('.png');
          if (!isPdf && !isRegion) continue;
          final name = entry.name.split('/').last;
          if (!_isSafeFileName(name)) continue;
          if (++restoredFiles > _maxRestoredFiles) {
            throw const FormatException('备份中的文件数量异常');
          }
          final limit = isPdf ? _maxPdfBytes : _maxPngBytes;
          if (entry.size > limit ||
              restoredBytes + entry.size > _maxRestoredBytes) {
            throw FormatException('备份中的文件过大：${entry.name}');
          }
          scratch ??= await Directory.systemTemp.createTemp(
            'particle-restore-',
          );
          final unpacked = File('${scratch.path}/${staged.length}');
          final sink = OutputFileStream(unpacked.path);
          try {
            entry.decompress(sink);
          } finally {
            await sink.close();
          }
          entry.clear();
          final length = await unpacked.length();
          if (length > limit ||
              !await _startsWith(
                unpacked,
                isPdf ? _pdfSignature : _pngSignature,
              )) {
            throw FormatException(
              '备份中的文件不是有效的 ${isPdf ? 'PDF' : 'PNG'}：${entry.name}',
            );
          }
          restoredBytes += length;
          staged.add(
            _StagedFile(file: unpacked, name: name, isRegion: isRegion),
          );
        }
        if (backup == null) {
          throw const FormatException('备份中缺少 backup.json');
        }
        if (backup.size > _maxBackupJsonBytes) {
          throw const FormatException('backup.json 过大');
        }
        final decoded = jsonDecode(utf8.decode(backup.readBytes()!));
        if (decoded is! Map) throw const FormatException('备份 JSON 无效');
        payload = Map<String, Object?>.from(decoded);
      } else {
        if (await file.length() > _maxBackupJsonBytes) {
          throw const FormatException('备份 JSON 过大');
        }
        final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
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
      final regionsDirectory = staged.any((item) => item.isRegion)
          ? await _regionsDirectory(reviewRegionsDirectory)
          : null;
      if (regionsDirectory != null) {
        for (final item in staged.where((item) => item.isRegion)) {
          regionPaths[item.name] = '${regionsDirectory.path}/${item.name}';
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
      if (staged.isNotEmpty) {
        Directory? cacheRoot;
        if (staged.any((item) => !item.isRegion)) {
          cacheRoot =
              reviewCacheDirectory ?? (await ReviewCache.open()).rootDirectory;
          await cacheRoot.create(recursive: true);
        }
        if (regionsDirectory != null) {
          await regionsDirectory.create(recursive: true);
        }
        for (final item in staged) {
          final root = item.isRegion ? regionsDirectory : cacheRoot;
          if (root == null) continue;
          final target = File('${root.path}/${item.name}');
          // A file already on this device is kept: a backup never replaces a
          // cached review or a screenshot that is already there.
          if (await target.exists()) continue;
          await _moveFile(item.file, target);
          if (item.isRegion) {
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
    } finally {
      try {
        await input?.close();
      } catch (_) {}
      try {
        if (scratch != null) await scratch.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<bool> _isZip(File file) async {
    final handle = await file.open();
    try {
      final head = await handle.read(2);
      return head.length == 2 && head[0] == 0x50 && head[1] == 0x4b;
    } finally {
      await handle.close();
    }
  }

  static Future<bool> _startsWith(File file, List<int> signature) async {
    final handle = await file.open();
    try {
      final head = await handle.read(signature.length);
      if (head.length != signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (head[i] != signature[i]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }

  /// Names a backup is allowed to create inside the cache directories. The
  /// app never writes a name starting with a dot or holding a separator.
  static bool _isSafeFileName(String name) =>
      name.isNotEmpty &&
      !name.startsWith('.') &&
      !name.contains('..') &&
      !RegExp(r'[\\\x00-\x1f]').hasMatch(name);

  static Future<void> _moveFile(File from, File to) async {
    await to.parent.create(recursive: true);
    try {
      await from.rename(to.path);
    } on FileSystemException {
      // The scratch directory can sit on another volume.
      await from.copy(to.path);
    }
  }

  /// Rewrites every annotation whose region image is not available so the
  /// backup says so, instead of naming a file that is not in the archive.
  static void _markRegionImagesMissing(Object? value, Set<String> missing) {
    if (value is Map) {
      final imagePath = value['imagePath']?.toString() ?? '';
      if (imagePath.isNotEmpty &&
          missing.contains(imagePath.split(RegExp(r'[\\/]')).last)) {
        value.remove('imagePath');
        value['imageStale'] = true;
      }
      for (final child in value.values.toList()) {
        _markRegionImagesMissing(child, missing);
      }
    } else if (value is List) {
      for (final child in value) {
        _markRegionImagesMissing(child, missing);
      }
    }
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

class _StagedFile {
  const _StagedFile({
    required this.file,
    required this.name,
    required this.isRegion,
  });

  final File file;
  final String name;
  final bool isRegion;
}

class FullBackupExport {
  const FullBackupExport({
    required this.notes,
    required this.pdfs,
    this.regions = 0,
    this.missingRegions = 0,
  });

  final int notes;
  final int pdfs;
  final int regions;

  /// Region images that notes refer to but that were not on this device. The
  /// affected annotations are stored without an image and marked stale.
  final int missingRegions;
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
