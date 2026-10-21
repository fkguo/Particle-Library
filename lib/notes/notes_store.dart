import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/sqlite3.dart';

import 'note_markdown.dart';
import 'notes_exception.dart';
import 'notes_models.dart';
import '../core/app_paths.dart';

/// Local, writable user-notes database.
///
/// The store owns a separate SQLite file at
/// `<application support>/ParticleDesk/user.db` (overridable for tests). It
/// never opens, attaches or writes to the read-only PDG snapshot and it never
/// touches `user_store.json`.
///
/// ## Storage guarantees
///
/// * The file is opened with [OpenMode.readWriteCreate], WAL journaling,
///   `synchronous=FULL`, `foreign_keys=ON`, a 5 s busy timeout,
///   `trusted_schema=OFF` and `case_sensitive_like=OFF`.
/// * `PRAGMA quick_check` runs on every open. A corrupt database throws
///   [NotesException] with [NotesErrorCode.corrupt]; it is never deleted,
///   truncated or re-initialised.
/// * Every note+anchor+tag write runs in one `BEGIN IMMEDIATE` transaction.
/// * [backupTo] uses `VACUUM INTO` into a temporary file, verifies it, then
///   renames it into place; an existing destination is never overwritten.
///
/// ## Schema history / migration path
///
/// `PRAGMA user_version` is the authoritative schema version and is written in
/// the same transaction as the DDL. Current history:
///
/// * **v1** — `notes`, `note_anchors`, `note_tags`, `meta` and their indices.
/// * **v2** — `collections`, `note_collections` (many-to-many, cascade).
///
/// To add v2: bump [schemaVersion], add a `version == 2` branch to
/// [_applyMigration] that only creates/alters tables and indices, and set
/// `user_version = 2` inside the same transaction. Never drop or recreate a
/// user table during migration.
/// On open, databases with `user_version > schemaVersion` are refused with
/// [NotesErrorCode.unsupportedSchema] and left untouched; a `user_version = 0`
/// file that already contains tables is likewise refused rather than reset.
///
/// ## Concurrency
///
/// One connection is owned by this object. Public methods are asynchronous for
/// callers but all SQLite work (including a whole transaction) runs
/// synchronously without an intervening `await`, so operations cannot
/// interleave on the Dart event loop.
/// Outcome of importing a notes JSON export.
class NotesImportResult {
  const NotesImportResult({
    required this.added,
    required this.skipped,
    required this.failed,
    this.renamedCollections = const <String>[],
  });

  final int added;
  final int skipped;
  final int failed;
  final List<String> renamedCollections;
}

class NotesStore {
  NotesStore._(this._db, this._path);

  final Database _db;
  final String _path;
  bool _closed = false;

  /// Schema version understood by this code.
  static const int schemaVersion = 2;

  /// Default size of [recent].
  static const int defaultRecentLimit = 50;

  /// File name inside the application support directory.
  static const String databaseFileName = 'user.db';

  static const int _busyTimeoutMilliseconds = 5000;
  static const int _maxSqlParameters = 500;

  static const Map<String, Set<String>> _requiredColumns = {
    'notes': {
      'id',
      'uuid',
      'title',
      'body_md',
      'body_plain',
      'created_at',
      'updated_at',
      'deleted_at',
      'revision',
    },
    'note_anchors': {
      'id',
      'note_id',
      'target_kind',
      'target_key',
      'snapshot_hash',
      'target_label',
      'status',
      'context_json',
      'created_at',
    },
    'note_tags': {'note_id', 'tag'},
    'collections': {'id', 'name', 'created_at', 'updated_at'},
    'note_collections': {'note_id', 'collection_id'},
    'meta': {'key', 'value'},
  };

  /// Absolute path of the open database file.
  String get storagePath => _path;

  /// Opens (and, if needed, creates/migrates) the notes database.
  ///
  /// [overridePath] is intended for tests and tooling. Without it the file is
  /// created at
  /// `<getApplicationSupportDirectory()>/ParticleDesk/user.db`.
  ///
  /// Throws [NotesException] when the directory/database is unavailable, when
  /// the file is corrupt, or when it has a newer/foreign schema.
  static Future<NotesStore> open({String? overridePath}) async {
    final path = await _resolvePath(overridePath);
    final parent = Directory(File(path).parent.path);
    try {
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
    } on FileSystemException catch (error) {
      throw NotesException(
        NotesErrorCode.unavailable,
        '无法创建笔记数据库目录。',
        cause: error,
      );
    }

    Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readWriteCreate);
    } on SqliteException catch (error) {
      throw _openFailure(error);
    }

    final store = NotesStore._(db, path);
    try {
      store._configureConnection();
      store._checkIntegrity();
      final version = store._readUserVersion();
      store._refuseUnsupportedVersion(version);
      store._enableWalAndDurability();
      store._migrateFrom(version);
      store._validateSchema();
      return store;
    } catch (_) {
      try {
        db.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<String> _resolvePath(String? overridePath) async {
    if (overridePath != null) {
      final trimmed = overridePath.trim();
      if (trimmed.isEmpty) {
        throw const NotesException(
          NotesErrorCode.invalidInput,
          'overridePath 不能为空。',
        );
      }
      return File(trimmed).absolute.path;
    }
    try {
      final support = await appSupportDirectory();
      return '${support.path}${Platform.pathSeparator}ParticleDesk'
          '${Platform.pathSeparator}$databaseFileName';
    } catch (error) {
      throw NotesException(
        NotesErrorCode.unavailable,
        '无法访问应用支持目录，笔记数据库不可用。',
        cause: error,
      );
    }
  }

  /// Creates a note with anchors and tags in one transaction.
  Future<NoteRecord> create({
    String title = '',
    String bodyMarkdown = '',
    Iterable<NoteAnchorInput> anchors = const <NoteAnchorInput>[],
    Iterable<String> tags = const <String>[],
    Iterable<String> collectionIds = const <String>[],
    String? uuid,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) async {
    _ensureOpen();
    final preparedAnchors = _normalizeAnchors(anchors);
    final preparedTags = _normalizeTags(tags);
    final preparedCollections = _normalizeCollectionIds(collectionIds);
    final now = createdAt == null ? _nowIso() : _formatTimestamp(createdAt);
    final updated = updatedAt == null ? now : _formatTimestamp(updatedAt);
    final id = _newUuid();
    final noteUuid = (uuid ?? '').trim().isEmpty ? _newUuid() : uuid!.trim();
    final bodyPlain = plainTextFromMarkdown(bodyMarkdown);

    _writeSync('创建笔记', () {
      _db.execute(
        'INSERT INTO notes('
        'id, uuid, title, body_md, body_plain, created_at, updated_at, '
        'deleted_at, revision'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
        [
          id,
          noteUuid,
          title,
          bodyMarkdown,
          bodyPlain,
          now,
          updated,
          deletedAt == null ? null : _formatTimestamp(deletedAt),
        ],
      );
      _insertAnchors(id, preparedAnchors, now);
      _insertTags(id, preparedTags);
      _insertCollections(id, preparedCollections);
    });
    return _requireNote(id);
  }

  /// Updates an active note.
  ///
  /// A `null` argument leaves the corresponding field unchanged. A non-null
  /// `anchors` or `tags` iterable replaces the whole set (pass an empty
  /// iterable to clear it). The revision is incremented in the same
  /// transaction. Throws [NotesErrorCode.notFound] for missing/soft-deleted
  /// notes and [NotesErrorCode.invalidInput] before writing anything when an
  /// anchor/tag is invalid.
  Future<NoteRecord> update(
    String id, {
    String? title,
    String? bodyMarkdown,
    Iterable<NoteAnchorInput>? anchors,
    Iterable<String>? tags,
    Iterable<String>? collectionIds,
    int? expectedRevision,
  }) async {
    _ensureOpen();
    final noteId = _requireNoteId(id);
    final preparedAnchors = anchors == null ? null : _normalizeAnchors(anchors);
    final preparedTags = tags == null ? null : _normalizeTags(tags);
    final preparedCollections = collectionIds == null
        ? null
        : _normalizeCollectionIds(collectionIds);
    final bodyPlain = bodyMarkdown == null
        ? null
        : plainTextFromMarkdown(bodyMarkdown);
    final now = _nowIso();

    _writeSync('更新笔记', () {
      final existing = _db.select(
        'SELECT deleted_at, revision FROM notes WHERE id = ?',
        [noteId],
      );
      if (existing.isEmpty || existing.first['deleted_at'] != null) {
        throw NotesException(NotesErrorCode.notFound, '笔记不存在或已删除：$noteId');
      }
      if (expectedRevision != null) {
        final current = existing.first['revision'];
        if (current is! num || current.toInt() != expectedRevision) {
          throw NotesException(
            NotesErrorCode.conflict,
            '笔记已被其他编辑更新，请重新载入后再保存。',
          );
        }
      }
      _db.execute(
        'UPDATE notes SET '
        'title = COALESCE(?, title), '
        'body_md = COALESCE(?, body_md), '
        'body_plain = COALESCE(?, body_plain), '
        'updated_at = ?, revision = revision + 1 '
        'WHERE id = ?',
        [title, bodyMarkdown, bodyPlain, now, noteId],
      );
      if (preparedAnchors != null) {
        _db.execute('DELETE FROM note_anchors WHERE note_id = ?', [noteId]);
        _insertAnchors(noteId, preparedAnchors, now);
      }
      if (preparedTags != null) {
        _db.execute('DELETE FROM note_tags WHERE note_id = ?', [noteId]);
        _insertTags(noteId, preparedTags);
      }
      if (preparedCollections != null) {
        _db.execute('DELETE FROM note_collections WHERE note_id = ?', [noteId]);
        _insertCollections(noteId, preparedCollections);
      }
    });
    return _requireNote(noteId);
  }

  /// Soft-deletes a note by setting `deleted_at`.
  ///
  /// Anchors and tags are retained. Calling [delete] twice is a no-op; a
  /// missing note throws [NotesErrorCode.notFound].
  Future<void> delete(String id) async {
    _ensureOpen();
    final noteId = _requireNoteId(id);
    final now = _nowIso();
    _writeSync('删除笔记', () {
      final existing = _db.select('SELECT deleted_at FROM notes WHERE id = ?', [
        noteId,
      ]);
      if (existing.isEmpty) {
        throw NotesException(NotesErrorCode.notFound, '笔记不存在：$noteId');
      }
      if (existing.first['deleted_at'] == null) {
        _db.execute(
          'UPDATE notes SET deleted_at = ?, updated_at = ?, '
          'revision = revision + 1 WHERE id = ?',
          [now, now, noteId],
        );
      }
    });
  }

  /// Soft-deleted notes, most recently deleted first.
  Future<List<NoteRecord>> deleted({int limit = defaultRecentLimit}) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    return _readSync('读取回收站', () {
      final rows = _db.select(
        'SELECT * FROM notes WHERE deleted_at IS NOT NULL '
        'ORDER BY deleted_at DESC, id ASC LIMIT ?',
        [limit],
      );
      return _loadNotes(rows);
    });
  }

  /// Restores one soft-deleted note.
  Future<NoteRecord> restore(String id) async {
    _ensureOpen();
    final noteId = _requireNoteId(id);
    _writeSync('恢复笔记', () {
      final existing = _db.select('SELECT deleted_at FROM notes WHERE id = ?', [
        noteId,
      ]);
      if (existing.isEmpty) {
        throw NotesException(NotesErrorCode.notFound, '笔记不存在：$noteId');
      }
      if (existing.first['deleted_at'] == null) {
        throw const NotesException(NotesErrorCode.invalidInput, '笔记未删除。');
      }
      _db.execute(
        'UPDATE notes SET deleted_at = NULL, updated_at = ?, '
        'revision = revision + 1 WHERE id = ?',
        [_nowIso(), noteId],
      );
    });
    return _requireNote(noteId);
  }

  /// Returns a note including soft-deleted rows, or `null` if it never existed.
  Future<NoteRecord?> get(String id) async {
    _ensureOpen();
    final noteId = _requireNoteId(id);
    return _readSync('读取笔记', () => _loadNote(noteId));
  }

  /// Active notes, most recently updated first.
  Future<List<NoteRecord>> recent({int limit = defaultRecentLimit}) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    return _readSync('读取最近笔记', () {
      final rows = _db.select(
        'SELECT * FROM notes WHERE deleted_at IS NULL '
        'ORDER BY updated_at DESC, created_at DESC, id ASC LIMIT ?',
        [limit],
      );
      return _loadNotes(rows);
    });
  }

  /// Active notes anchored to [targetKind]/[targetKey].
  ///
  /// [snapshotHash] restricts the result to one verified snapshot; omit it (or
  /// pass an empty string) to match anchors from any snapshot. A note that has
  /// several matching anchors is returned once.
  Future<List<NoteRecord>> notesForTarget(
    String targetKind,
    String targetKey, {
    String? snapshotHash,
    int? limit,
  }) async {
    _ensureOpen();
    final kind = _normalizeTargetKind(targetKind);
    final key = _requireTargetKey(targetKey);
    if (limit != null) _requirePositiveLimit(limit);
    final hash = snapshotHash?.trim() ?? '';
    final useHash = hash.isNotEmpty;

    return _readSync('查询目标笔记', () {
      final sql = StringBuffer(
        'SELECT DISTINCT n.* FROM notes n '
        'JOIN note_anchors a ON a.note_id = n.id '
        'WHERE n.deleted_at IS NULL AND a.target_kind = ? AND a.target_key = ?',
      );
      final parameters = <Object?>[kind, key];
      if (useHash) {
        sql.write(' AND a.snapshot_hash = ?');
        parameters.add(hash);
      }
      sql.write(' ORDER BY n.updated_at DESC, n.id ASC');
      if (limit != null) {
        sql.write(' LIMIT ?');
        parameters.add(limit);
      }
      return _loadNotes(_db.select(sql.toString(), parameters));
    });
  }

  /// Batch anchor counts, avoiding an N+1 query for list pages.
  ///
  /// Every requested [NoteTarget] is present in the result (with `0` when it
  /// has no notes). Counting is over distinct active notes, so a note with
  /// anchors to the same target in two snapshots counts once for a target
  /// without [NoteTarget.snapshotHash].
  Future<Map<NoteTarget, int>> countForTargets(
    Iterable<NoteTarget> targets,
  ) async {
    _ensureOpen();
    final normalized = <NoteTarget>[];
    final seen = <NoteTarget>{};
    for (final target in targets) {
      final kind = _normalizeTargetKind(target.kind);
      final key = _requireTargetKey(target.key);
      final hash = target.snapshotHash?.trim() ?? '';
      final normalizedTarget = NoteTarget(
        kind: kind,
        key: key,
        snapshotHash: hash.isEmpty ? null : hash,
      );
      if (seen.add(normalizedTarget)) normalized.add(normalizedTarget);
    }
    final counts = <NoteTarget, int>{
      for (final target in normalized) target: 0,
    };
    if (normalized.isEmpty) return counts;

    return _readSync('统计目标笔记', () {
      for (final chunk in _chunks(normalized, 100)) {
        final withSnapshot = <NoteTarget>[];
        final anySnapshot = <NoteTarget>[];
        for (final target in chunk) {
          (target.snapshotHash == null ? anySnapshot : withSnapshot).add(
            target,
          );
        }
        if (withSnapshot.isNotEmpty) {
          _countWithSnapshot(withSnapshot, counts);
        }
        if (anySnapshot.isNotEmpty) {
          _countAnySnapshot(anySnapshot, counts);
        }
      }
      return counts;
    });
  }

  /// Active collections, sorted by name.
  Future<List<NoteCollection>> collections() async {
    _ensureOpen();
    return _readSync('读取 collections', () {
      final rows = _db.select(
        'SELECT * FROM collections ORDER BY name COLLATE NOCASE, id',
      );
      return [for (final row in rows) _collectionFromRow(row)];
    });
  }

  /// Collections with their active-note counts in one query.
  Future<List<NoteCollectionSummary>> collectionSummaries() async {
    _ensureOpen();
    return _readSync('读取 collection 计数', () {
      final rows = _db.select('''
        SELECT c.*, COUNT(n.id) AS active_note_count
          FROM collections c
          LEFT JOIN note_collections nc ON nc.collection_id = c.id
          LEFT JOIN notes n ON n.id = nc.note_id AND n.deleted_at IS NULL
         GROUP BY c.id
         ORDER BY c.name COLLATE NOCASE, c.id
      ''');
      return [
        for (final row in rows)
          NoteCollectionSummary(
            collection: _collectionFromRow(row),
            activeNoteCount: (row['active_note_count'] as int?) ?? 0,
          ),
      ];
    });
  }

  /// Adds one note to one collection. Membership-only writes do not bump the
  /// note revision or updated_at; the operation is idempotent.
  Future<void> addNoteToCollection(String noteId, String collectionId) async {
    _ensureOpen();
    final id = _requireNoteId(noteId);
    final cid = _requireCollectionId(collectionId);
    _writeSync('加入 collection', () {
      _requireActiveNote(id);
      _requireCollection(cid);
      _db.execute(
        'INSERT OR IGNORE INTO note_collections(note_id, collection_id) '
        'VALUES (?, ?)',
        [id, cid],
      );
    });
  }

  /// Removes one note from one collection. The note itself is preserved;
  /// operation is idempotent.
  Future<void> removeNoteFromCollection(
    String noteId,
    String collectionId,
  ) async {
    _ensureOpen();
    final id = _requireNoteId(noteId);
    final cid = _requireCollectionId(collectionId);
    _writeSync('移出 collection', () {
      _requireActiveNote(id);
      _requireCollection(cid);
      _db.execute(
        'DELETE FROM note_collections WHERE note_id = ? AND collection_id = ?',
        [id, cid],
      );
    });
  }

  /// Active notes not assigned to any collection, newest first.
  Future<List<NoteRecord>> unfiled({
    int limit = defaultRecentLimit,
    int offset = 0,
  }) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    if (offset < 0) {
      throw const NotesException(NotesErrorCode.invalidInput, 'offset 不能为负数。');
    }
    return _readSync('读取未归入集合的笔记', () {
      final rows = _db.select(
        'SELECT n.* FROM notes n '
        'WHERE n.deleted_at IS NULL AND NOT EXISTS ('
        '  SELECT 1 FROM note_collections nc WHERE nc.note_id = n.id'
        ') ORDER BY n.updated_at DESC, n.id ASC LIMIT ? OFFSET ?',
        [limit, offset],
      );
      return _loadNotes(rows);
    });
  }

  Future<NoteCollection> createCollection(
    String name, {
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    _ensureOpen();
    final normalized = _normalizeCollectionName(name);
    final requestedId = id?.trim() ?? '';
    final collectionId = requestedId.isEmpty ? _newUuid() : requestedId;
    final created = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final updated = (updatedAt ?? created).toUtc();
    _writeSync('创建 collection', () {
      if (_collectionNameExists(normalized)) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          'collection 名称已存在：$normalized',
        );
      }
      final existing = _db.select('SELECT 1 FROM collections WHERE id = ?', [
        collectionId,
      ]);
      if (existing.isNotEmpty) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          'collection id 已存在：$collectionId',
        );
      }
      _db.execute(
        'INSERT INTO collections(id, name, created_at, updated_at) '
        'VALUES (?, ?, ?, ?)',
        [
          collectionId,
          normalized,
          created.toIso8601String(),
          updated.toIso8601String(),
        ],
      );
    });
    return _requireCollection(collectionId);
  }

  Future<NoteCollection> renameCollection(String id, String name) async {
    _ensureOpen();
    final collectionId = _requireCollectionId(id);
    final normalized = _normalizeCollectionName(name);
    final now = _nowIso();
    _writeSync('重命名 collection', () {
      _requireCollection(collectionId);
      if (_collectionNameExists(normalized, exceptId: collectionId)) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          'collection 名称已存在：$normalized',
        );
      }
      _db.execute(
        'UPDATE collections SET name = ?, updated_at = ? WHERE id = ?',
        [normalized, now, collectionId],
      );
    });
    return _requireCollection(collectionId);
  }

  Future<void> deleteCollection(String id) async {
    _ensureOpen();
    final collectionId = _requireCollectionId(id);
    _writeSync('删除 collection', () {
      final deleted = _db.select('SELECT 1 FROM collections WHERE id = ?', [
        collectionId,
      ]);
      if (deleted.isEmpty) {
        throw NotesException(
          NotesErrorCode.notFound,
          'collection 不存在：$collectionId',
        );
      }
      _db.execute('DELETE FROM collections WHERE id = ?', [collectionId]);
    });
  }

  /// Restores a collection and its note memberships in one transaction.
  ///
  /// Unlike [addNoteToCollection], this also restores memberships for notes
  /// that are currently in the trash, so undoing a collection delete does not
  /// silently detach deleted notes.
  Future<void> restoreCollection(
    NoteCollection collection,
    Iterable<String> noteIds,
  ) async {
    _ensureOpen();
    final normalizedName = _normalizeCollectionName(collection.name);
    final ids = <String>{for (final id in noteIds) id.trim()};
    _writeSync('恢复 collection', () {
      final nameRows = _db.select(
        'SELECT id FROM collections WHERE name = ? COLLATE NOCASE',
        [normalizedName],
      );
      if (nameRows.any((row) => row['id'] != collection.id)) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          'collection 名称已存在：$normalizedName',
        );
      }
      final existing = _db.select('SELECT 1 FROM collections WHERE id = ?', [
        collection.id,
      ]);
      if (existing.isNotEmpty) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          'collection id 已存在：${collection.id}',
        );
      }
      _db.execute(
        'INSERT INTO collections(id, name, created_at, updated_at) '
        'VALUES (?, ?, ?, ?)',
        [
          collection.id,
          normalizedName,
          collection.createdAt.toUtc().toIso8601String(),
          collection.updatedAt.toUtc().toIso8601String(),
        ],
      );
      for (final noteId in ids) {
        _insertCollections(noteId, [collection.id]);
      }
    });
  }

  Future<void> setNoteCollections(
    String noteId,
    Iterable<String> collectionIds,
  ) async {
    _ensureOpen();
    final id = _requireNoteId(noteId);
    final normalized = _normalizeCollectionIds(collectionIds);
    _writeSync('设置笔记 collections', () {
      final note = _db.select('SELECT deleted_at FROM notes WHERE id = ?', [
        id,
      ]);
      if (note.isEmpty || note.first['deleted_at'] != null) {
        throw NotesException(NotesErrorCode.notFound, '笔记不存在或已删除：$id');
      }
      _db.execute('DELETE FROM note_collections WHERE note_id = ?', [id]);
      _insertCollections(id, normalized);
      // Membership-only writes do not invalidate an open editor's content
      // revision and do not change the note's recent ordering.
    });
  }

  Future<List<NoteRecord>> notesInCollection(
    String collectionId, {
    int limit = defaultRecentLimit,
    int offset = 0,
  }) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    if (offset < 0) {
      throw const NotesException(NotesErrorCode.invalidInput, 'offset 不能为负数。');
    }
    final id = _requireCollectionId(collectionId);
    return _readSync('读取 collection 笔记', () {
      final rows = _db.select(
        'SELECT DISTINCT n.* FROM notes n '
        'JOIN note_collections nc ON nc.note_id = n.id '
        'WHERE nc.collection_id = ? AND n.deleted_at IS NULL '
        'ORDER BY n.updated_at DESC, n.id ASC LIMIT ? OFFSET ?',
        [id, limit, offset],
      );
      return _loadNotes(rows);
    });
  }

  /// Counts distinct active notes matching any target. Unlike summing
  /// [countForTargets], a note carrying DOI + document_id anchors is counted
  /// once.
  Future<int> countDistinctForTargets(Iterable<NoteTarget> targets) async {
    _ensureOpen();
    final normalized = <String>[];
    final seen = <String>{};
    for (final target in targets) {
      final kind = _normalizeTargetKind(target.kind);
      final key = _requireTargetKey(target.key);
      final id = '$kind\u0000$key';
      if (seen.add(id)) normalized.add(id);
    }
    if (normalized.isEmpty) return 0;
    final clauses = <String>[];
    final params = <Object?>[];
    for (final id in normalized) {
      final parts = id.split('\u0000');
      clauses.add('(a.target_kind = ? AND a.target_key = ?)');
      params
        ..add(parts[0])
        ..add(parts[1]);
    }
    final rows = _db.select(
      'SELECT COUNT(DISTINCT n.id) AS n FROM notes n '
      'JOIN note_anchors a ON a.note_id = n.id '
      'WHERE n.deleted_at IS NULL AND (${clauses.join(' OR ')})',
      params,
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Tag names with their active-note counts, most used first.
  Future<Map<String, int>> tagCounts({int limit = 100}) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    return _readSync('读取标签', () {
      final rows = _db.select(
        'SELECT t.tag AS tag, COUNT(*) AS n FROM note_tags t '
        'JOIN notes n ON n.id = t.note_id '
        'WHERE n.deleted_at IS NULL '
        'GROUP BY t.tag ORDER BY n DESC, t.tag ASC LIMIT ?',
        [limit],
      );
      return {
        for (final row in rows)
          row['tag'].toString(): (row['n'] as num?)?.toInt() ?? 0,
      };
    });
  }

  /// Renames one tag across every active note.
  ///
  /// Returns the number of notes whose tag set changed. Notes that already
  /// carry [to] keep a single tag instead of creating a duplicate.
  Future<int> renameTag(String from, String to) async {
    final oldTag = from.trim();
    final newTag = to.trim();
    if (oldTag.isEmpty || newTag.isEmpty || oldTag == newTag) return 0;
    return _writeSync('重命名标签', () {
      final rows = _db.select(
        'SELECT DISTINCT t.note_id AS id FROM note_tags t '
        'JOIN notes n ON n.id = t.note_id '
        'WHERE n.deleted_at IS NULL AND t.tag = ?',
        [oldTag],
      );
      if (rows.isEmpty) return 0;
      final ids = [for (final row in rows) row['id'].toString()];
      for (final id in ids) {
        _db.execute(
          'INSERT OR IGNORE INTO note_tags(note_id, tag) VALUES (?, ?)',
          [id, newTag],
        );
      }
      _db.execute(
        'DELETE FROM note_tags WHERE tag = ? AND note_id IN '
        '(${List<String>.filled(ids.length, '?').join(',')})',
        [oldTag, ...ids],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      _db.execute(
        'UPDATE notes SET updated_at = ? WHERE id IN '
        '(${List<String>.filled(ids.length, '?').join(',')})',
        [now, ...ids],
      );
      return ids.length;
    });
  }

  /// Removes one tag from every note without deleting the notes.
  Future<int> deleteTag(String tag) async {
    final name = tag.trim();
    if (name.isEmpty) return 0;
    return _writeSync('删除标签', () {
      final rows = _db.select(
        'SELECT DISTINCT t.note_id AS id FROM note_tags t '
        'JOIN notes n ON n.id = t.note_id '
        'WHERE n.deleted_at IS NULL AND t.tag = ?',
        [name],
      );
      if (rows.isEmpty) return 0;
      final ids = [for (final row in rows) row['id'].toString()];
      _db.execute('DELETE FROM note_tags WHERE tag = ?', [name]);
      final now = DateTime.now().toUtc().toIso8601String();
      _db.execute(
        'UPDATE notes SET updated_at = ? WHERE id IN '
        '(${List<String>.filled(ids.length, '?').join(',')})',
        [now, ...ids],
      );
      return ids.length;
    });
  }

  /// Active notes carrying every tag in [tags]. An empty [tags] list returns
  /// recent notes.
  Future<List<NoteRecord>> notesByTags(
    Iterable<String> tags, {
    String? collectionId,
    int limit = 50,
  }) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    final names = <String>[];
    final seen = <String>{};
    for (final tag in tags) {
      final name = tag.trim();
      if (name.isNotEmpty && seen.add(name)) names.add(name);
    }
    if (names.isEmpty) return recent(limit: limit);
    final collection = collectionId?.trim() ?? '';
    final clauses = <String>[];
    final params = <Object?>[];
    for (final name in names) {
      clauses.add(
        'EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = notes.id '
        'AND t.tag = ?)',
      );
      params.add(name);
    }
    if (collection.isNotEmpty) {
      clauses.add(
        'EXISTS (SELECT 1 FROM note_collections nc '
        'WHERE nc.note_id = notes.id AND nc.collection_id = ?)',
      );
      params.add(collection);
    }
    final rows = _db.select(
      'SELECT * FROM notes WHERE deleted_at IS NULL '
      'AND ${clauses.join(' AND ')} '
      'ORDER BY updated_at DESC, id ASC LIMIT ?',
      [...params, limit],
    );
    return _loadNotes(rows);
  }

  /// Removes the old `<!-- measurement:N -->` dedupe marker that earlier
  /// builds wrote into note bodies. It was never meant to be visible; new
  /// notes use a normal source link instead. Returns the number of notes
  /// cleaned.
  Future<int> cleanupLegacyMeasurementMarkers() async {
    _ensureOpen();
    return _writeSync('清理旧测量标记', () {
      final rows = _db.select(
        "SELECT id, body_md FROM notes WHERE body_md LIKE '%<!-- measurement:%'",
      );
      var cleaned = 0;
      for (final row in rows) {
        final body = row['body_md']?.toString() ?? '';
        final next = body
            .replaceAll(
              RegExp(r'[ \t]*\n?<!--\s*measurement:\d+\s*-->[ \t]*\n?'),
              '\n',
            )
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trimRight();
        if (next == body.trimRight()) continue;
        _db.execute(
          'UPDATE notes SET body_md = ?, body_plain = ?, updated_at = ?, '
          'revision = revision + 1 WHERE id = ?',
          [next, plainTextFromMarkdown(next), _nowIso(), row['id']],
        );
        cleaned++;
      }
      return cleaned;
    });
  }

  /// Active note by its database id.
  Future<NoteRecord?> noteById(String id, {bool includeDeleted = false}) async {
    _ensureOpen();
    final key = id.trim();
    if (key.isEmpty) return null;
    return _readSync('读取笔记', () {
      final rows = _db.select(
        includeDeleted
            ? 'SELECT * FROM notes WHERE id = ? LIMIT 1'
            : 'SELECT * FROM notes WHERE id = ? AND deleted_at IS NULL LIMIT 1',
        [key],
      );
      if (rows.isEmpty) return null;
      return _loadNotes(rows).single;
    });
  }

  /// Active note by its stable UUID.
  Future<NoteRecord?> noteByUuid(
    String uuid, {
    bool includeDeleted = false,
  }) async {
    _ensureOpen();
    final key = uuid.trim();
    if (key.isEmpty) return null;
    return _readSync('读取笔记', () {
      final rows = _db.select(
        includeDeleted ? 'SELECT * FROM notes WHERE uuid = ? LIMIT 1' : 'SELECT * FROM notes WHERE uuid = ? AND deleted_at IS NULL LIMIT 1',
        [key],
      );
      if (rows.isEmpty) return null;
      return _loadNotes(rows).single;
    });
  }

  /// Notes whose Markdown body contains a typed PDG link to one of [targets],
  /// e.g. `[D0](pdgid:S032M)`. This complements anchor backlinks: a user can
  /// link an entity in prose without adding a formal anchor.
  Future<List<NoteRecord>> notesMentioningTargets(
    Iterable<NoteTarget> targets, {
    int limit = 50,
  }) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    final ids = <String>[];
    final seen = <String>{};
    for (final target in targets) {
      final kind = _normalizeTargetKind(target.kind);
      final key = _requireTargetKey(target.key);
      final id = '$kind:$key';
      if (seen.add(id)) ids.add(id);
    }
    if (ids.isEmpty) return const <NoteRecord>[];
    final clauses = <String>[];
    final params = <Object?>[];
    for (final id in ids) {
      clauses.add('body_md LIKE ?');
      params.add(_likePattern(']($id)'));
    }
    final anchorClauses = <String>[];
    final anchorParams = <Object?>[];
    for (final target in targets) {
      final kind = _normalizeTargetKind(target.kind);
      final key = _requireTargetKey(target.key);
      anchorClauses.add('(a.target_kind = ? AND a.target_key = ?)');
      anchorParams
        ..add(kind)
        ..add(key);
    }
    final rows = _db.select(
      'SELECT DISTINCT * FROM notes WHERE deleted_at IS NULL '
      'AND (${clauses.join(' OR ')}) '
      'AND NOT EXISTS (SELECT 1 FROM note_anchors a '
      'WHERE a.note_id = notes.id AND (${anchorClauses.join(' OR ')})) '
      'ORDER BY updated_at DESC, id ASC LIMIT ?',
      [...params, ...anchorParams, limit],
    );
    return _loadNotes(rows);
  }

  /// Case-insensitive substring search over title, body, anchor keys/labels,
  /// tags and collection names. This lets a PDG identifier such as `S032M` find
  /// a note even when the identifier appears only in its metadata.
  ///
  /// Uses SQLite `LIKE` with `%`, `_` and `\` escaped, so CJK substrings work
  /// without tokenisation. ASCII case-insensitivity is provided by SQLite's
  /// default `LIKE`; `PRAGMA case_sensitive_like` is explicitly off.
  Future<List<NoteRecord>> search(
    String query, {
    int limit = 50,
    String? collectionId,
  }) async {
    _ensureOpen();
    _requirePositiveLimit(limit);
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <NoteRecord>[];
    final pattern = _likePattern(trimmed);
    final collection = collectionId?.trim() ?? '';

    return _readSync('搜索笔记', () {
      const escape = "ESCAPE '\\'";
      final rows = _db.select(
        'SELECT * FROM notes WHERE deleted_at IS NULL AND ('
        'title LIKE ? $escape OR '
        'body_plain LIKE ? $escape OR '
        'body_md LIKE ? $escape OR '
        'EXISTS (SELECT 1 FROM note_anchors a WHERE a.note_id = notes.id '
        '  AND (a.target_key LIKE ? $escape OR a.target_label LIKE ? $escape)) OR '
        'EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = notes.id '
        '  AND t.tag LIKE ? $escape) OR '
        'EXISTS (SELECT 1 FROM note_collections nc '
        '  JOIN collections c ON c.id = nc.collection_id '
        '  WHERE nc.note_id = notes.id AND c.name LIKE ? $escape)'
        ')${collection.isEmpty ? '' : ' AND EXISTS (SELECT 1 FROM note_collections nc2 '
                  'WHERE nc2.note_id = notes.id AND nc2.collection_id = ?)'} '
        'ORDER BY updated_at DESC, id ASC LIMIT ?',
        [
          pattern,
          pattern,
          pattern,
          pattern,
          pattern,
          pattern,
          pattern,
          if (collection.isNotEmpty) collection,
          limit,
        ],
      );
      return _loadNotes(rows);
    });
  }

  /// Anchors whose [NoteAnchorStatus] is not resolved (`fuzzy`/`unresolved`),
  /// belonging to active notes.
  Future<List<NoteAnchor>> unresolved({int? limit}) async {
    _ensureOpen();
    if (limit != null) _requirePositiveLimit(limit);
    return _readSync('读取未解析锚点', () {
      final sql = StringBuffer(
        'SELECT a.* FROM note_anchors a '
        'JOIN notes n ON n.id = a.note_id '
        'WHERE n.deleted_at IS NULL '
        "AND a.status NOT IN ('exact', 'resolved') "
        'ORDER BY a.created_at DESC, a.id ASC',
      );
      final parameters = <Object?>[];
      if (limit != null) {
        sql.write(' LIMIT ?');
        parameters.add(limit);
      }
      return [
        for (final row in _db.select(sql.toString(), parameters))
          _anchorFromRow(row),
      ];
    });
  }

  /// All notes with anchors and tags, ordered by creation time.
  ///
  /// Soft-deleted notes are excluded unless [includeDeleted] is true.
  /// Imports the JSON produced by [allForExport] (or a bare list of records).
  ///
  /// Records with a UUID that already exists are skipped, never merged: an
  /// import must not silently overwrite newer local edits. Missing collections
  /// are created by name. Malformed records are counted in [failed] while the
  /// rest of the file continues to import.
  /// Imports notes and collections from a notes.v1/v2 payload.
  ///
  /// The payload is validated completely before anything is written. All
  /// collections and notes are then inserted in one transaction; a database
  /// failure rolls the whole import back. Duplicate note UUIDs are skipped.
  Future<NotesImportResult> importJson(Object? decoded) async {
    _ensureOpen();
    final root = decoded is Map ? decoded['notes'] : decoded;
    if (root is! List) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        '导入文件不是笔记 JSON 数组。',
      );
    }
    _validateImportPayload(decoded, root);
    final localCollections = await collections();
    final localById = <String, String>{
      for (final collection in localCollections) collection.id: collection.id,
    };
    final knownByName = <String, String>{
      for (final collection in localCollections)
        collection.name.toLowerCase(): collection.id,
    };
    final knownByImportedId = <String, String>{};
    final plannedCollections = <_ImportCollectionPlan>[];
    final renamedCollections = <String>[];
    final plannedNames = <String>{
      for (final collection in localCollections) collection.name.toLowerCase(),
    };

    String uniqueCollectionName(String base) {
      var candidate = '$base (imported)';
      var index = 2;
      while (plannedNames.contains(candidate.toLowerCase())) {
        candidate = '$base (imported $index)';
        index++;
      }
      return candidate;
    }

    String resolveCollection({
      required String rawId,
      required String name,
      DateTime? createdAt,
      DateTime? updatedAt,
    }) {
      final trimmedName = name.trim();
      final trimmedId = rawId.trim();
      if (trimmedId.isNotEmpty) {
        final local = localById[trimmedId] ?? knownByImportedId[trimmedId];
        if (local != null) return local;
      }
      final lookup = trimmedName.toLowerCase();
      if (trimmedId.isEmpty) {
        final existing = knownByName[lookup];
        if (existing != null) return existing;
      }
      var targetName = trimmedName;
      if (trimmedId.isNotEmpty && knownByName.containsKey(lookup)) {
        targetName = uniqueCollectionName(trimmedName);
      }
      final id = trimmedId.isEmpty ? _newUuid() : trimmedId;
      if (targetName != trimmedName) {
        renamedCollections.add('$trimmedName → $targetName');
      }
      final normalizedTarget = _normalizeCollectionName(targetName);
      final plan = _ImportCollectionPlan(
        id: id,
        name: normalizedTarget,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      plannedCollections.add(plan);
      plannedNames.add(normalizedTarget.toLowerCase());
      knownByName[normalizedTarget.toLowerCase()] = id;
      if (normalizedTarget == trimmedName) knownByName[lookup] = id;
      if (trimmedId.isNotEmpty) {
        knownByImportedId[trimmedId] = id;
        localById[trimmedId] = id;
      }
      return id;
    }

    final registry = decoded is Map ? decoded['collections'] : null;
    if (registry is List) {
      for (final value in registry) {
        if (value is! Map) continue;
        resolveCollection(
          rawId: value['id']?.toString() ?? '',
          name: value['name']?.toString() ?? '',
          createdAt: DateTime.tryParse(value['createdAt']?.toString() ?? ''),
          updatedAt: DateTime.tryParse(value['updatedAt']?.toString() ?? ''),
        );
      }
    }

    final existingUuids = _readSync('读取导入去重键', () {
      return {
        for (final row in _db.select('SELECT uuid FROM notes'))
          row['uuid']?.toString() ?? '',
      };
    });
    final seenUuids = <String>{};
    final notes = <_ImportNotePlan>[];
    var skipped = 0;
    for (final raw in root) {
      if (raw is! Map) continue;
      final uuid = raw['uuid']?.toString().trim() ?? '';
      if (existingUuids.contains(uuid) || !seenUuids.add(uuid)) {
        skipped++;
        continue;
      }
      final anchors = <NoteAnchorInput>[];
      final rawAnchors = raw['anchors'];
      if (rawAnchors is List) {
        for (final value in rawAnchors) {
          if (value is! Map) continue;
          final anchor = Map<String, Object?>.from(value);
          final kind = anchor['targetKind']?.toString().trim() ?? '';
          final key = anchor['targetKey']?.toString().trim() ?? '';
          if (kind.isEmpty || key.isEmpty) continue;
          final statusName = anchor['status']?.toString();
          final status = statusName == 'resolved'
              ? NoteAnchorStatus.exact
              : NoteAnchorStatus.values.firstWhere(
                  (candidate) => candidate.wireName == statusName,
                  orElse: () => NoteAnchorStatus.exact,
                );
          final rawContext = anchor['context'];
          anchors.add(
            NoteAnchorInput(
              targetKind: kind,
              targetKey: key,
              snapshotHash: anchor['snapshotHash']?.toString(),
              targetLabel: anchor['targetLabel']?.toString() ?? '',
              status: status,
              context: rawContext is Map
                  ? Map<String, Object?>.from(rawContext)
                  : null,
            ),
          );
        }
      }
      final tags = <String>[];
      final rawTags = raw['tags'];
      if (rawTags is List) {
        for (final value in rawTags) {
          final tag = value?.toString().trim() ?? '';
          if (tag.isNotEmpty) tags.add(tag);
        }
      }
      final collectionIds = <String>[];
      final rawCollections = raw['collections'];
      if (rawCollections is List) {
        for (final value in rawCollections) {
          if (value is! Map) continue;
          final id = resolveCollection(
            rawId: value['id']?.toString() ?? '',
            name: value['name']?.toString() ?? '',
          );
          if (!collectionIds.contains(id)) collectionIds.add(id);
        }
      }
      final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
      final updatedAt = DateTime.tryParse(raw['updatedAt']?.toString() ?? '');
      final deletedAt = DateTime.tryParse(raw['deletedAt']?.toString() ?? '');
      notes.add(
        _ImportNotePlan(
          uuid: uuid,
          title: raw['title']?.toString() ?? '',
          bodyMarkdown: raw['bodyMarkdown']?.toString() ?? '',
          anchors: _normalizeAnchors(anchors),
          tags: _normalizeTags(tags),
          collectionIds: collectionIds,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
        ),
      );
    }

    _writeSync('导入笔记', () {
      for (final collection in plannedCollections) {
        _db.execute(
          'INSERT INTO collections(id, name, created_at, updated_at) '
          'VALUES (?, ?, ?, ?)',
          [
            collection.id,
            collection.name,
            (collection.createdAt ?? DateTime.now().toUtc())
                .toUtc()
                .toIso8601String(),
            (collection.updatedAt ??
                    collection.createdAt ??
                    DateTime.now().toUtc())
                .toUtc()
                .toIso8601String(),
          ],
        );
      }
      for (final note in notes) {
        final id = _newUuid();
        final createdAt = note.createdAt ?? DateTime.now().toUtc();
        final updatedAt = note.updatedAt ?? createdAt;
        final created = _formatTimestamp(createdAt);
        _db.execute(
          'INSERT INTO notes('
          'id, uuid, title, body_md, body_plain, created_at, updated_at, '
          'deleted_at, revision'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
          [
            id,
            note.uuid,
            note.title,
            note.bodyMarkdown,
            plainTextFromMarkdown(note.bodyMarkdown),
            created,
            _formatTimestamp(updatedAt),
            note.deletedAt == null ? null : _formatTimestamp(note.deletedAt!),
          ],
        );
        _insertAnchors(id, note.anchors, created);
        _insertTags(id, note.tags);
        _insertCollections(id, note.collectionIds);
      }
    });
    return NotesImportResult(
      added: notes.length,
      skipped: skipped,
      failed: 0,
      renamedCollections: List<String>.unmodifiable(renamedCollections),
    );
  }

  void _validateImportPayload(Object? decoded, List<Object?> root) {
    final collectionIds = <String>{};
    final registry = decoded is Map ? decoded['collections'] : null;
    if (registry != null && registry is! List) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        '导入文件的 collections 必须是数组。',
      );
    }
    if (registry is List) {
      for (final value in registry) {
        if (value is! Map) {
          throw const NotesException(
            NotesErrorCode.invalidInput,
            '导入文件包含无效的集合记录。',
          );
        }
        final name = value['name']?.toString().trim() ?? '';
        if (name.isEmpty) {
          throw const NotesException(
            NotesErrorCode.invalidInput,
            '导入文件包含空名称集合。',
          );
        }
        final id = value['id']?.toString().trim() ?? '';
        if (id.isNotEmpty && !collectionIds.add(id)) {
          throw NotesException(
            NotesErrorCode.invalidInput,
            '导入文件包含重复集合 id：$id',
          );
        }
      }
    }
    for (final raw in root) {
      if (raw is! Map) {
        throw const NotesException(NotesErrorCode.invalidInput, '导入文件包含非对象笔记。');
      }
      final uuid = raw['uuid']?.toString().trim() ?? '';
      if (uuid.isEmpty) {
        throw const NotesException(
          NotesErrorCode.invalidInput,
          '导入文件包含缺少 uuid 的笔记。',
        );
      }
      final rawAnchors = raw['anchors'];
      if (rawAnchors != null && rawAnchors is! List) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          '笔记 $uuid 的 anchors 必须是数组。',
        );
      }
      if (rawAnchors is List) {
        for (final value in rawAnchors) {
          if (value is! Map) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 包含无效锚点。',
            );
          }
          final kind = value['targetKind']?.toString().trim() ?? '';
          final key = value['targetKey']?.toString().trim() ?? '';
          if (kind.isEmpty || key.isEmpty) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 包含缺少 targetKind/targetKey 的锚点。',
            );
          }
          final status = value['status']?.toString();
          if (status != null &&
              status != 'resolved' &&
              !NoteAnchorStatus.values.any((s) => s.wireName == status)) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 包含未知锚点状态：$status',
            );
          }
          final context = value['context'];
          if (context != null && context is! Map) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 的锚点 context 必须是对象或 null。',
            );
          }
        }
      }
      final rawCollections = raw['collections'];
      if (rawCollections != null && rawCollections is! List) {
        throw NotesException(
          NotesErrorCode.invalidInput,
          '笔记 $uuid 的 collections 必须是数组。',
        );
      }
      if (rawCollections is List) {
        for (final value in rawCollections) {
          if (value is! Map) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 包含无效集合引用。',
            );
          }
          final id = value['id']?.toString().trim() ?? '';
          final name = value['name']?.toString().trim() ?? '';
          if (id.isEmpty && name.isEmpty) {
            throw NotesException(
              NotesErrorCode.invalidInput,
              '笔记 $uuid 包含缺少 id/name 的集合引用。',
            );
          }
        }
      }
    }
  }

  Future<List<NoteRecord>> allForExport({bool includeDeleted = false}) async {
    _ensureOpen();
    return _readSync('导出笔记', () {
      final rows = _db.select(
        'SELECT * FROM notes'
        '${includeDeleted ? '' : ' WHERE deleted_at IS NULL'} '
        'ORDER BY created_at ASC, id ASC',
      );
      return _loadNotes(rows);
    });
  }

  /// Writes a consistent, verified backup of this database to
  /// [destinationPath] using `VACUUM INTO`.
  ///
  /// The backup is built in a temporary file in the destination directory,
  /// checked with `PRAGMA quick_check` and for the expected `user_version`,
  /// and only then renamed into place. [destinationPath] must not exist.
  /// Throws [NotesErrorCode.backupFailed] on failure (leaving no partial file)
  /// and [NotesErrorCode.invalidInput] if the destination is the live database.
  Future<void> backupTo(String destinationPath) async {
    _ensureOpen();
    final trimmed = destinationPath.trim();
    if (trimmed.isEmpty) {
      throw const NotesException(NotesErrorCode.invalidInput, '备份路径不能为空。');
    }
    final destination = File(trimmed).absolute;
    final live = File(_path).absolute;
    if (destination.path == live.path) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        '备份路径不能是正在使用的笔记数据库。',
      );
    }
    if (await destination.exists()) {
      throw const NotesException(NotesErrorCode.backupFailed, '备份目标已存在，未覆盖。');
    }
    try {
      await destination.parent.create(recursive: true);
    } on FileSystemException catch (error) {
      throw NotesException(
        NotesErrorCode.unavailable,
        '无法创建备份目录。',
        cause: error,
      );
    }

    final temporary = File('${destination.path}.partial-${_newUuid()}')
        .absolute;
    try {
      _db.execute('VACUUM INTO ${_sqlStringLiteral(temporary.path)}');
      _verifyBackup(temporary.path);
      await temporary.rename(destination.path);
    } catch (error) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      if (error is NotesException) {
        throw NotesException(
          NotesErrorCode.backupFailed,
          '备份笔记数据库失败：${error.message}',
          cause: error,
        );
      }
      if (error is SqliteException) {
        throw _mapSqlite(
          error,
          '备份笔记数据库',
          fallback: NotesErrorCode.backupFailed,
        );
      }
      throw NotesException(
        NotesErrorCode.backupFailed,
        '备份笔记数据库失败。',
        cause: error,
      );
    }
  }

  /// Closes the connection. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    try {
      _db.dispose();
    } catch (_) {}
  }

  /// Read-only connection diagnostics (journal mode, pragmas, user_version).
  ///
  /// Useful for settings/diagnostics screens and for tests that need to assert
  /// the connection configuration.
  Future<Map<String, Object?>> diagnostics() async {
    _ensureOpen();
    return _readSync('读取数据库状态', () {
      return <String, Object?>{
        'path': _path,
        'userVersion': _db.userVersion,
        'journalMode': _pragmaValue('journal_mode'),
        'synchronous': _pragmaValue('synchronous'),
        'foreignKeys': _pragmaValue('foreign_keys'),
        'busyTimeout': _pragmaValue('busy_timeout'),
        'trustedSchema': _pragmaValue('trusted_schema'),
      };
    });
  }

  // ---------------------------------------------------------------------------
  // Connection setup and schema
  // ---------------------------------------------------------------------------

  void _configureConnection() {
    try {
      _db.execute('PRAGMA busy_timeout = $_busyTimeoutMilliseconds');
      _db.execute('PRAGMA foreign_keys = ON');
      _db.execute('PRAGMA trusted_schema = OFF');
      _db.execute('PRAGMA case_sensitive_like = OFF');
      if (_pragmaValue('foreign_keys') != 1) {
        throw const NotesException(
          NotesErrorCode.unavailable,
          '无法启用 SQLite 外键约束。',
        );
      }
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _mapSqlite(error, '配置笔记数据库', fallback: NotesErrorCode.unavailable);
    }
  }

  void _enableWalAndDurability() {
    try {
      _db.execute('PRAGMA journal_mode = WAL');
      final mode = _pragmaValue('journal_mode');
      if (mode is! String || mode.toLowerCase() != 'wal') {
        throw NotesException(
          NotesErrorCode.unavailable,
          '无法启用笔记数据库 WAL 模式。',
          cause: mode,
        );
      }
      _db.execute('PRAGMA synchronous = FULL');
      if (_pragmaValue('synchronous') != 2) {
        throw const NotesException(
          NotesErrorCode.unavailable,
          '无法设置 synchronous=FULL。',
        );
      }
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _mapSqlite(
        error,
        '启用 WAL 模式',
        fallback: NotesErrorCode.unavailable,
      );
    }
  }

  int _readUserVersion() {
    try {
      return _db.userVersion;
    } on SqliteException catch (error) {
      throw _openFailure(error);
    }
  }

  void _refuseUnsupportedVersion(int version) {
    if (version > schemaVersion) {
      throw NotesException(
        NotesErrorCode.unsupportedSchema,
        '笔记数据库版本 $version 高于当前支持的 $schemaVersion，已拒绝打开。',
      );
    }
    if (version == 0 && _userTableCount() > 0) {
      throw const NotesException(
        NotesErrorCode.unsupportedSchema,
        'user_version 为 0 但数据库已有数据表，拒绝重置。',
      );
    }
  }

  void _migrateFrom(int version) {
    if (version == schemaVersion) return;
    for (var target = version + 1; target <= schemaVersion; target++) {
      _applyMigration(target);
    }
  }

  void _applyMigration(int version) {
    try {
      _db.execute('BEGIN IMMEDIATE');
    } on SqliteException catch (error) {
      throw _mapSqlite(
        error,
        '开始数据库迁移',
        fallback: NotesErrorCode.unsupportedSchema,
      );
    }
    try {
      // Another process may have completed the migration while this
      // connection waited for BEGIN IMMEDIATE; never run DDL twice.
      if (_db.userVersion >= version) {
        _db.execute('COMMIT');
        return;
      }
      if (version == 1) {
        _createSchemaV1();
      } else if (version == 2) {
        _createSchemaV2();
      } else {
        throw NotesException(
          NotesErrorCode.unsupportedSchema,
          '没有迁移到 user_version=$version 的路径。',
        );
      }
      _db.userVersion = version;
      _db.execute('COMMIT');
    } catch (error) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      if (error is NotesException) rethrow;
      if (error is SqliteException) {
        throw _mapSqlite(
          error,
          '迁移笔记数据库到 v$version',
          fallback: NotesErrorCode.unsupportedSchema,
        );
      }
      rethrow;
    }
  }

  void _createSchemaV1() {
    const statements = <String>[
      '''
CREATE TABLE notes (
  id TEXT PRIMARY KEY NOT NULL,
  uuid TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  body_md TEXT NOT NULL DEFAULT '',
  body_plain TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1)
)
''',
      '''
CREATE TABLE note_anchors (
  id TEXT PRIMARY KEY NOT NULL,
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  target_kind TEXT NOT NULL,
  target_key TEXT NOT NULL,
  snapshot_hash TEXT NOT NULL DEFAULT '',
  target_label TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'exact',
  context_json TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(note_id, target_kind, target_key, snapshot_hash)
)
''',
      '''
CREATE TABLE note_tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  PRIMARY KEY (note_id, tag)
) WITHOUT ROWID
''',
      '''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
) WITHOUT ROWID
''',
      // Recent list and search ordering (partial: active notes only).
      '''
CREATE INDEX idx_notes_recent
  ON notes(updated_at DESC) WHERE deleted_at IS NULL
''',
      // Title access for exact/prefix lookups and search planning. A
      // substring `LIKE '%x%'` cannot use a B-tree index; CJK matching is
      // deliberately a scan over the small local notes table, not FTS.
      '''
CREATE INDEX idx_notes_title ON notes(title COLLATE NOCASE)
''',
      '''
CREATE INDEX idx_notes_created ON notes(created_at)
''',
      // Target lookup: notesForTarget / countForTargets.
      '''
CREATE INDEX idx_anchors_target
  ON note_anchors(target_kind, target_key, snapshot_hash)
''',
      '''
CREATE INDEX idx_anchors_note ON note_anchors(note_id)
''',
      '''
CREATE INDEX idx_anchors_unresolved
  ON note_anchors(status) WHERE status NOT IN ('exact', 'resolved')
''',
      // Future tag browsing.
      '''
CREATE INDEX idx_tags_tag ON note_tags(tag, note_id)
''',
    ];
    for (final statement in statements) {
      _db.execute(statement);
    }
    _db.execute('INSERT OR IGNORE INTO meta(key, value) VALUES (?, ?)', [
      'schema_created_at',
      _nowIso(),
    ]);
    _db.execute('INSERT OR IGNORE INTO meta(key, value) VALUES (?, ?)', [
      'application',
      'Particle Library notes',
    ]);
  }

  void _createSchemaV2() {
    const statements = <String>[
      '''
CREATE TABLE collections (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
      '''
CREATE TABLE note_collections (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, collection_id)
) WITHOUT ROWID
''',
      '''
CREATE INDEX idx_note_collections_collection
  ON note_collections(collection_id, note_id)
''',
    ];
    for (final statement in statements) {
      _db.execute(statement);
    }
  }

  void _validateSchema() {
    try {
      if (_db.userVersion != schemaVersion) {
        throw NotesException(
          NotesErrorCode.unsupportedSchema,
          'user_version=${_db.userVersion}，期望 $schemaVersion。',
        );
      }
      final tableRows = _db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      final tables = <String>{
        for (final row in tableRows) row['name']?.toString() ?? '',
      };
      for (final entry in _requiredColumns.entries) {
        if (!tables.contains(entry.key)) {
          throw NotesException(
            NotesErrorCode.unsupportedSchema,
            '笔记数据库缺少数据表 ${entry.key}。',
          );
        }
        final info = _db.select("PRAGMA table_info('${entry.key}')");
        final columns = <String>{
          for (final row in info) row['name']?.toString() ?? '',
        };
        final missing = entry.value.where((c) => !columns.contains(c)).toList()
          ..sort();
        if (missing.isNotEmpty) {
          throw NotesException(
            NotesErrorCode.unsupportedSchema,
            '数据表 ${entry.key} 缺少列：${missing.join(', ')}。',
          );
        }
      }
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _mapSqlite(
        error,
        '校验笔记数据库结构',
        fallback: NotesErrorCode.unsupportedSchema,
      );
    }
  }

  int _userTableCount() {
    try {
      final row = _db
          .select(
            "SELECT COUNT(*) AS table_count FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .first;
      return (row['table_count'] as num?)?.toInt() ?? 0;
    } on SqliteException catch (error) {
      throw _openFailure(error);
    }
  }

  void _checkIntegrity() {
    try {
      _quickCheck(_db);
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _openFailure(error);
    }
  }

  void _verifyBackup(String path) {
    Database? backup;
    try {
      backup = sqlite3.open(path, mode: OpenMode.readOnly);
      backup.execute('PRAGMA busy_timeout = $_busyTimeoutMilliseconds');
      _quickCheck(backup);
      if (backup.userVersion != schemaVersion) {
        throw NotesException(
          NotesErrorCode.backupFailed,
          '备份文件 user_version=${backup.userVersion}，期望 $schemaVersion。',
        );
      }
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _mapSqlite(error, '校验备份文件', fallback: NotesErrorCode.backupFailed);
    } finally {
      try {
        backup?.dispose();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Reads and writes
  // ---------------------------------------------------------------------------

  T _readSync<T>(String operation, T Function() action) {
    _ensureOpen();
    try {
      return action();
    } on NotesException {
      rethrow;
    } on SqliteException catch (error) {
      throw _mapSqlite(error, operation);
    }
  }

  T _writeSync<T>(String operation, T Function() action) {
    _ensureOpen();
    try {
      _db.execute('BEGIN IMMEDIATE');
    } on SqliteException catch (error) {
      throw _mapSqlite(error, operation, fallback: NotesErrorCode.writeFailed);
    }
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (error) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      if (error is NotesException) rethrow;
      if (error is SqliteException) {
        throw _mapSqlite(
          error,
          operation,
          fallback: NotesErrorCode.writeFailed,
        );
      }
      rethrow;
    }
  }

  NoteRecord? _loadNote(String id) {
    final rows = _db.select('SELECT * FROM notes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _loadNotes(rows).single;
  }

  NoteRecord _requireNote(String id) {
    final note = _readSync('读取笔记', () => _loadNote(id));
    if (note == null) {
      throw NotesException(NotesErrorCode.corrupt, '刚写入的笔记无法读取：$id');
    }
    return note;
  }

  List<NoteRecord> _loadNotes(List<Row> rows) {
    if (rows.isEmpty) return const <NoteRecord>[];
    final ids = [for (final row in rows) _requiredText(row, 'id', 'notes')];
    final anchors = _loadAnchorsForNotes(ids);
    final tags = _loadTagsForNotes(ids);
    final collections = _loadCollectionsForNotes(ids);
    return [
      for (final row in rows)
        _noteFromRow(
          row,
          anchors[_requiredText(row, 'id', 'notes')] ?? const <NoteAnchor>[],
          tags[_requiredText(row, 'id', 'notes')] ?? const <NoteTag>[],
          collections[_requiredText(row, 'id', 'notes')] ??
              const <NoteCollection>[],
        ),
    ];
  }

  Map<String, List<NoteAnchor>> _loadAnchorsForNotes(List<String> noteIds) {
    final result = <String, List<NoteAnchor>>{};
    for (final chunk in _chunks(noteIds, _maxSqlParameters)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = _db.select(
        'SELECT * FROM note_anchors WHERE note_id IN ($placeholders) '
        'ORDER BY target_kind, target_key, snapshot_hash, id',
        chunk,
      );
      for (final row in rows) {
        final anchor = _anchorFromRow(row);
        (result[anchor.noteId] ??= <NoteAnchor>[]).add(anchor);
      }
    }
    return result;
  }

  Map<String, List<NoteTag>> _loadTagsForNotes(List<String> noteIds) {
    final result = <String, List<NoteTag>>{};
    for (final chunk in _chunks(noteIds, _maxSqlParameters)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = _db.select(
        'SELECT note_id, tag FROM note_tags WHERE note_id IN ($placeholders) '
        'ORDER BY note_id, tag',
        chunk,
      );
      for (final row in rows) {
        final noteId = _requiredText(row, 'note_id', 'note_tags');
        final tag = _requiredText(row, 'tag', 'note_tags');
        (result[noteId] ??= <NoteTag>[]).add(NoteTag(tag));
      }
    }
    return result;
  }

  Map<String, List<NoteCollection>> _loadCollectionsForNotes(
    List<String> noteIds,
  ) {
    final result = <String, List<NoteCollection>>{};
    for (final chunk in _chunks(noteIds, _maxSqlParameters)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = _db.select(
        'SELECT nc.note_id, c.* FROM note_collections nc '
        'JOIN collections c ON c.id = nc.collection_id '
        'WHERE nc.note_id IN ($placeholders) ORDER BY c.name COLLATE NOCASE',
        chunk,
      );
      for (final row in rows) {
        final noteId = _requiredText(row, 'note_id', 'note_collections');
        (result[noteId] ??= <NoteCollection>[]).add(_collectionFromRow(row));
      }
    }
    return result;
  }

  NoteRecord _noteFromRow(
    Row row,
    List<NoteAnchor> anchors,
    List<NoteTag> tags,
    List<NoteCollection> collections,
  ) {
    final id = _requiredText(row, 'id', 'notes');
    final deletedAtText = row['deleted_at']?.toString();
    return NoteRecord(
      id: id,
      uuid: _requiredText(row, 'uuid', 'notes'),
      title: _requiredText(row, 'title', 'notes'),
      bodyMarkdown: _requiredText(row, 'body_md', 'notes'),
      bodyPlain: _requiredText(row, 'body_plain', 'notes'),
      createdAt: _requiredDate(row, 'created_at', 'notes', id),
      updatedAt: _requiredDate(row, 'updated_at', 'notes', id),
      deletedAt: deletedAtText == null || deletedAtText.isEmpty
          ? null
          : _parseDate(deletedAtText, 'notes.deleted_at', id),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      anchors: anchors,
      tags: tags,
      collections: collections,
    );
  }

  NoteAnchor _anchorFromRow(Row row) {
    final id = _requiredText(row, 'id', 'note_anchors');
    final contextText = row['context_json']?.toString();
    Map<String, Object?>? context;
    if (contextText != null && contextText.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(contextText);
        if (decoded is! Map) {
          throw const FormatException('context_json 必须是 JSON 对象');
        }
        context = <String, Object?>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      } on FormatException catch (error) {
        // A single damaged optional anchor context must not make every note
        // unreadable. Keep the anchor, surface it without geometry, and leave
        // the note body/search usable.
        debugPrint('Ignoring malformed anchor context $id: $error');
        context = null;
      }
    }
    return NoteAnchor(
      id: id,
      noteId: _requiredText(row, 'note_id', 'note_anchors'),
      targetKind: _requiredText(row, 'target_kind', 'note_anchors'),
      targetKey: _requiredText(row, 'target_key', 'note_anchors'),
      snapshotHash: row['snapshot_hash']?.toString() ?? '',
      targetLabel: row['target_label']?.toString() ?? '',
      status: NoteAnchorStatus.fromWireName(row['status']?.toString()),
      context: context,
      createdAt: _requiredDate(row, 'created_at', 'note_anchors', id),
    );
  }

  void _insertAnchors(
    String noteId,
    List<NoteAnchorInput> anchors,
    String createdAt,
  ) {
    for (final anchor in anchors) {
      _db.execute(
        'INSERT INTO note_anchors('
        'id, note_id, target_kind, target_key, snapshot_hash, target_label, '
        'status, context_json, created_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          _newUuid(),
          noteId,
          anchor.targetKind,
          anchor.targetKey,
          anchor.snapshotHash ?? '',
          anchor.targetLabel,
          anchor.status.wireName,
          anchor.context == null ? null : jsonEncode(anchor.context),
          createdAt,
        ],
      );
    }
  }

  void _insertTags(String noteId, List<String> tags) {
    for (final tag in tags) {
      _db.execute('INSERT INTO note_tags(note_id, tag) VALUES (?, ?)', [
        noteId,
        tag,
      ]);
    }
  }

  // ---------------------------------------------------------------------------
  // Normalisation, validation and small helpers
  // ---------------------------------------------------------------------------

  List<NoteAnchorInput> _normalizeAnchors(Iterable<NoteAnchorInput> anchors) {
    final result = <NoteAnchorInput>[];
    final seen = <String>{};
    for (final anchor in anchors) {
      final kind = _normalizeTargetKind(anchor.targetKind);
      final key = _requireTargetKey(anchor.targetKey);
      final hash = anchor.snapshotHash?.trim() ?? '';
      if (anchor.context != null) {
        try {
          jsonEncode(anchor.context);
        } catch (error) {
          throw NotesException(
            NotesErrorCode.invalidInput,
            '锚点 context 无法转换为 JSON。',
            cause: error,
          );
        }
      }
      if (!seen.add('$kind\u0000$key\u0000$hash')) continue;
      result.add(
        NoteAnchorInput(
          targetKind: kind,
          targetKey: key,
          snapshotHash: hash.isEmpty ? null : hash,
          targetLabel: anchor.targetLabel.trim(),
          status: anchor.status,
          context: anchor.context,
        ),
      );
    }
    return result;
  }

  List<String> _normalizeTags(Iterable<String> tags) {
    final unique = <String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      unique.add(trimmed);
    }
    return unique.toList()..sort();
  }

  List<String> _normalizeCollectionIds(Iterable<String> ids) {
    final unique = <String>{};
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      unique.add(id);
    }
    final result = unique.toList()..sort();
    for (final id in result) {
      _requireCollection(id);
    }
    return result;
  }

  String _normalizeCollectionName(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        'collection 名称不能为空。',
      );
    }
    return name;
  }

  String _requireCollectionId(String value) {
    final id = value.trim();
    if (id.isEmpty) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        'collection id 不能为空。',
      );
    }
    return id;
  }

  bool _collectionNameExists(String name, {String? exceptId}) {
    final rows = _db.select(
      'SELECT id FROM collections WHERE name = ? COLLATE NOCASE',
      [name],
    );
    return rows.any((row) => row['id']?.toString() != exceptId);
  }

  NoteCollection _requireCollection(String id) {
    final rows = _db.select('SELECT * FROM collections WHERE id = ?', [id]);
    if (rows.isEmpty) {
      throw NotesException(NotesErrorCode.notFound, 'collection 不存在：$id');
    }
    return _collectionFromRow(rows.first);
  }

  void _requireActiveNote(String id) {
    final rows = _db.select('SELECT deleted_at FROM notes WHERE id = ?', [id]);
    if (rows.isEmpty || rows.first['deleted_at'] != null) {
      throw NotesException(NotesErrorCode.notFound, '笔记不存在或已删除：$id');
    }
  }

  void _insertCollections(String noteId, List<String> collectionIds) {
    for (final collectionId in collectionIds) {
      _db.execute(
        'INSERT OR IGNORE INTO note_collections(note_id, collection_id) '
        'VALUES (?, ?)',
        [noteId, collectionId],
      );
    }
  }

  NoteCollection _collectionFromRow(Row row) {
    final id = _requiredText(row, 'id', 'collections');
    return NoteCollection(
      id: id,
      name: _requiredText(row, 'name', 'collections'),
      createdAt: _requiredDate(row, 'created_at', 'collections', id),
      updatedAt: _requiredDate(row, 'updated_at', 'collections', id),
    );
  }

  String _normalizeTargetKind(String value) {
    final kind = value.trim().toLowerCase();
    if (kind.isEmpty) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        '锚点 targetKind 不能为空。',
      );
    }
    return kind;
  }

  String _requireTargetKey(String value) {
    final key = value.trim();
    if (key.isEmpty) {
      throw const NotesException(
        NotesErrorCode.invalidInput,
        '锚点 targetKey 不能为空。',
      );
    }
    return key;
  }

  String _requireNoteId(String value) {
    final id = value.trim();
    if (id.isEmpty) {
      throw const NotesException(NotesErrorCode.invalidInput, '笔记 id 不能为空。');
    }
    return id;
  }

  void _requirePositiveLimit(int limit) {
    if (limit <= 0) {
      throw const NotesException(NotesErrorCode.invalidInput, 'limit 必须大于 0。');
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const NotesException(NotesErrorCode.unavailable, '笔记数据库已关闭。');
    }
  }

  void _countWithSnapshot(
    List<NoteTarget> targets,
    Map<NoteTarget, int> counts,
  ) {
    final clauses = <String>[];
    final parameters = <Object?>[];
    for (final target in targets) {
      clauses.add(
        '(a.target_kind = ? AND a.target_key = ? AND a.snapshot_hash = ?)',
      );
      parameters.addAll([target.kind, target.key, target.snapshotHash]);
    }
    final rows = _db.select(
      'SELECT a.target_kind, a.target_key, a.snapshot_hash, '
      'COUNT(DISTINCT a.note_id) AS note_count '
      'FROM note_anchors a JOIN notes n ON n.id = a.note_id '
      'WHERE n.deleted_at IS NULL AND (${clauses.join(' OR ')}) '
      'GROUP BY a.target_kind, a.target_key, a.snapshot_hash',
      parameters,
    );
    for (final row in rows) {
      final kind = _requiredText(row, 'target_kind', 'count');
      final key = _requiredText(row, 'target_key', 'count');
      final hash = row['snapshot_hash']?.toString() ?? '';
      for (final target in targets) {
        if (target.kind == kind &&
            target.key == key &&
            target.snapshotHash == hash) {
          counts[target] = (row['note_count'] as num?)?.toInt() ?? 0;
          break;
        }
      }
    }
  }

  void _countAnySnapshot(
    List<NoteTarget> targets,
    Map<NoteTarget, int> counts,
  ) {
    final clauses = <String>[];
    final parameters = <Object?>[];
    for (final target in targets) {
      clauses.add('(a.target_kind = ? AND a.target_key = ?)');
      parameters.addAll([target.kind, target.key]);
    }
    final rows = _db.select(
      'SELECT a.target_kind, a.target_key, '
      'COUNT(DISTINCT a.note_id) AS note_count '
      'FROM note_anchors a JOIN notes n ON n.id = a.note_id '
      'WHERE n.deleted_at IS NULL AND (${clauses.join(' OR ')}) '
      'GROUP BY a.target_kind, a.target_key',
      parameters,
    );
    for (final row in rows) {
      final kind = _requiredText(row, 'target_kind', 'count');
      final key = _requiredText(row, 'target_key', 'count');
      for (final target in targets) {
        if (target.kind == kind && target.key == key) {
          counts[target] = (row['note_count'] as num?)?.toInt() ?? 0;
          break;
        }
      }
    }
  }

  static Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
    for (var start = 0; start < values.length; start += size) {
      yield values.sublist(
        start,
        start + size > values.length ? values.length : start + size,
      );
    }
  }

  static String _likePattern(String query) {
    final escaped = query
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    return '%$escaped%';
  }

  static String _sqlStringLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static String _requiredText(Row row, String column, String context) {
    final value = row[column]?.toString();
    if (value == null) {
      throw NotesException(NotesErrorCode.corrupt, '$context 缺少必需字段 $column。');
    }
    return value;
  }

  static DateTime _requiredDate(
    Row row,
    String column,
    String context,
    String id,
  ) => _parseDate(row[column]?.toString(), '$context.$column', id);

  static DateTime _parseDate(String? value, String field, String context) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    if (parsed == null) {
      throw NotesException(
        NotesErrorCode.corrupt,
        '$context 的 $field 时间戳无效：$value',
      );
    }
    return parsed;
  }

  Object? _pragmaValue(String pragma) {
    final rows = _db.select('PRAGMA $pragma');
    if (rows.isEmpty || rows.first.values.isEmpty) return null;
    return rows.first.values.first;
  }

  static NotesException _openFailure(SqliteException error) {
    final code = error.resultCode;
    if (code == 11 || code == 26) {
      return NotesException(
        NotesErrorCode.corrupt,
        '笔记数据库已损坏或不是 SQLite 数据库；文件未做任何修改。',
        cause: error,
      );
    }
    return NotesException(
      NotesErrorCode.unavailable,
      '无法打开笔记数据库。',
      cause: error,
    );
  }

  static NotesException _mapSqlite(
    SqliteException error,
    String operation, {
    NotesErrorCode fallback = NotesErrorCode.unavailable,
  }) {
    final code = error.resultCode;
    final mapped = switch (code) {
      11 || 26 => NotesErrorCode.corrupt, // CORRUPT / NOTADB
      5 || 6 || 8 || 10 || 13 || 14 =>
        NotesErrorCode.unavailable, // BUSY/LOCKED/READONLY/IOERR/FULL/CANTOPEN
      _ => fallback,
    };
    final message = switch (mapped) {
      NotesErrorCode.corrupt => '$operation：数据库已损坏。',
      NotesErrorCode.unavailable => '$operation：数据库当前不可用。',
      NotesErrorCode.backupFailed => '$operation失败。',
      NotesErrorCode.writeFailed => '$operation失败。',
      NotesErrorCode.unsupportedSchema => '$operation：数据库结构与当前版本不兼容。',
      NotesErrorCode.invalidInput => '$operation：参数无效。',
      NotesErrorCode.notFound => '$operation：对象不存在。',
      NotesErrorCode.conflict => '$operation：数据已被其他编辑更新。',
    };
    return NotesException(mapped, message, cause: error);
  }

  static void _quickCheck(Database db) {
    final rows = db.select('PRAGMA quick_check');
    if (rows.isEmpty) {
      throw const NotesException(NotesErrorCode.corrupt, '数据库完整性检查未返回结果。');
    }
    for (final row in rows) {
      final value = row.values.isEmpty ? null : row.values.first;
      if (value is! String || value.toLowerCase() != 'ok') {
        throw NotesException(NotesErrorCode.corrupt, '数据库完整性检查失败：$value');
      }
    }
  }

  static final Random _random = _createRandom();

  static Random _createRandom() {
    try {
      return Random.secure();
    } on UnsupportedError {
      return Random();
    }
  }

  static String _newUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _nowIso() => _formatTimestamp(DateTime.now());

  static String _formatTimestamp(DateTime value) {
    final utc = value.toUtc();
    String pad(int number, int width) => number.toString().padLeft(width, '0');
    final fraction = pad(utc.millisecond * 1000 + utc.microsecond, 6);
    return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
        'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
        '.${fraction}Z';
  }
}

class _ImportCollectionPlan {
  const _ImportCollectionPlan({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class _ImportNotePlan {
  const _ImportNotePlan({
    required this.uuid,
    required this.title,
    required this.bodyMarkdown,
    required this.anchors,
    required this.tags,
    required this.collectionIds,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String uuid;
  final String title;
  final String bodyMarkdown;
  final List<NoteAnchorInput> anchors;
  final List<String> tags;
  final List<String> collectionIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
}
