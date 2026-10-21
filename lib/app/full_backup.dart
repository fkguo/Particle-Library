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
  }) async {
    final notePayload = notes == null
        ? <String, Object?>{'notes': <Object?>[]}
        : Map<String, Object?>.from(
            jsonDecode(notesExportJson(await notes.allForExport())) as Map,
          );
    final payload = <String, Object?>{
      'format': format,
      'formatVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'user': user.exportData(),
      'notes': notePayload,
    };
    final encoder = ZipFileEncoder();
    var pdfs = 0;
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
      await encoder.close();
      return FullBackupExport(
        notes: notes == null ? 0 : (notePayload['notes'] as List).length,
        pdfs: pdfs,
      );
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<FullBackupImport> import({
    required UserStore user,
    required NotesStore? notes,
    required String sourcePath,
  }) async {
    final file = File(sourcePath);
    final bytes = await file.readAsBytes();
    Map<String, Object?> payload;
    final entries = <String, Uint8List>{};
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? backup;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name == 'backup.json') {
          backup = entry;
        } else if (entry.name.startsWith('reviews/') &&
            entry.name.toLowerCase().endsWith('.pdf')) {
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
    if (isFull && payload['formatVersion'] != 1) {
      throw const FormatException('不支持的完整备份版本');
    }
    final rawUser = payload['user'];
    if (isFull && rawUser is Map) {
      await user.importData(Map<String, Object?>.from(rawUser));
    }
    final rawNotes = payload['notes'];
    var importedNotes = 0;
    if (rawNotes != null && notes != null) {
      final result = await notes.importJson(rawNotes);
      importedNotes = result.added;
    }
    var restoredPdfs = 0;
    if (entries.isNotEmpty) {
      final cache = await ReviewCache.open();
      await cache.rootDirectory.create(recursive: true);
      for (final entry in entries.entries) {
        final name = entry.key.split('/').last;
        if (name.isEmpty || name.contains('..')) continue;
        await File('${cache.rootDirectory.path}/$name')
            .writeAsBytes(entry.value, flush: true);
        restoredPdfs++;
      }
    }
    return FullBackupImport(
      full: isFull,
      notes: importedNotes,
      pdfs: restoredPdfs,
    );
  }
}

class FullBackupExport {
  const FullBackupExport({required this.notes, required this.pdfs});

  final int notes;
  final int pdfs;
}

class FullBackupImport {
  const FullBackupImport({
    required this.full,
    required this.notes,
    required this.pdfs,
  });

  final bool full;
  final int notes;
  final int pdfs;
}
