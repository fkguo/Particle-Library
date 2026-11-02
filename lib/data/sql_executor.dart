import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../core/errors.dart';
import '../domain/models.dart';

/// Executes application-defined, parameterised read queries.
///
/// The production implementation owns a SQLite connection in a long-lived
/// background isolate. Tests use [DirectSqlExecutor] with the same query code.
abstract class SqlExecutor {
  Future<List<RawRow>> select(String sql, [List<Object?> params = const []]);

  Future<void> dispose();
}

class DirectSqlExecutor implements SqlExecutor {
  DirectSqlExecutor._(this._db);

  final Database _db;

  static Future<DirectSqlExecutor> open(String path) async {
    try {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      db.execute('PRAGMA query_only=ON;');
      db.execute('PRAGMA trusted_schema=OFF;');
      return DirectSqlExecutor._(db);
    } catch (error) {
      throw AppException(AppErrorCode.corruptDatabase,
          '无法以只读方式打开数据库。', detail: '$error');
    }
  }

  @override
  Future<List<RawRow>> select(String sql, [List<Object?> params = const []]) async {
    try {
      final result = _db.select(sql, params);
      return [
        for (final row in result) Map<String, Object?>.from(row),
      ];
    } catch (error) {
      throw AppException(AppErrorCode.queryFailed, '数据库查询失败。',
          detail: '$error');
    }
  }

  @override
  Future<void> dispose() async {
    _db.close();
  }
}

/// Long-lived isolate holding one read-only connection.
class IsolateSqlExecutor implements SqlExecutor {
  IsolateSqlExecutor._(this._isolate, this._requests, this._port, this._errorPort);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _port;
  final ReceivePort _errorPort;
  final Map<int, Completer<List<RawRow>>> _pending = {};
  int _nextId = 1;
  bool _closed = false;
  bool _failed = false;

  static Future<IsolateSqlExecutor> open(String path) async {
    final port = ReceivePort();
    final errorPort = ReceivePort();
    final ready = Completer<SendPort>();
    IsolateSqlExecutor? instance;
    port.listen((message) {
      if (!ready.isCompleted) {
        if (message is Map && message['ok'] == true) {
          ready.complete(message['requests'] as SendPort);
        } else if (message is Map) {
          ready.completeError(AppException(AppErrorCode.corruptDatabase,
              '无法打开只读数据库。', detail: '${message['error']}'));
        }
        return;
      }
      instance?._onResponse(message);
    });
    errorPort.listen((message) {
      if (!ready.isCompleted) {
        ready.completeError(AppException(AppErrorCode.corruptDatabase,
            '后台数据库连接意外退出。', detail: '$message'));
      } else if (instance != null && !instance._closed) {
        instance._failAll(AppException(AppErrorCode.queryFailed,
            '后台数据库连接意外退出。', detail: '$message'));
      }
    });

    final isolate = await Isolate.spawn(
      _sqlWorkerMain,
      [port.sendPort, path],
      onError: errorPort.sendPort,
      debugName: 'pdg-sql-worker',
    );
    SendPort requests;
    try {
      requests = await ready.future;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      errorPort.close();
      rethrow;
    }
    instance = IsolateSqlExecutor._(isolate, requests, port, errorPort);
    return instance;
  }

  void _failAll(Object error) {
    _failed = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
  }

  void _onResponse(dynamic message) {
    if (message is! Map) return;
    final map = Map<String, Object?>.from(message);
    final id = map['id'];
    final key = id is int ? id : null;
    if (key == null) return;
    final completer = _pending.remove(key);
    if (completer == null) return;
    if (map['ok'] == true) {
      final rows = <RawRow>[];
      final rawRows = map['rows'];
      if (rawRows is List) {
        for (final row in rawRows) {
          if (row is Map) rows.add(Map<String, Object?>.from(row));
        }
      }
      completer.complete(rows);
    } else {
      completer.completeError(AppException(
        AppErrorCode.queryFailed,
        '数据库查询失败。',
        detail: map['error']?.toString(),
      ));
    }
  }

  @override
  Future<List<RawRow>> select(String sql, [List<Object?> params = const []]) {
    if (_closed) {
      return Future.error(
          AppException(AppErrorCode.queryFailed, '数据库连接已关闭。'));
    }
    if (_failed) {
      return Future.error(
          AppException(AppErrorCode.queryFailed, '数据库连接已失效。'));
    }
    final id = _nextId++;
    final completer = Completer<List<RawRow>>();
    _pending[id] = completer;
    _requests.send({
      'id': id,
      'sql': sql,
      'params': params,
    });
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _failAll(AppException(AppErrorCode.queryFailed, '数据库连接已关闭。'));
    try {
      _requests.send({'id': -1, 'close': true});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _port.close();
    _errorPort.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

void _sqlWorkerMain(List<Object?> args) {
  final readyPort = args[0] as SendPort;
  final path = args[1] as String;
  final requests = ReceivePort();
  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    db.execute('PRAGMA query_only=ON;');
    db.execute('PRAGMA trusted_schema=OFF;');
    db.execute('PRAGMA busy_timeout=2000;');
    readyPort.send({
      'ok': true,
      'requests': requests.sendPort,
    });
  } catch (error) {
    readyPort.send({'ok': false, 'error': '$error'});
    requests.close();
    db?.close();
    return;
  }

  requests.listen((message) {
    if (message is! Map) return;
    final map = Map<String, Object?>.from(message);
    final id = map['id'];
    if (map['close'] == true) {
      requests.close();
      db?.close();
      Isolate.exit();
    }
    if (id is! int) return;
    try {
      final sql = map['sql'] as String;
      final params = (map['params'] as List?)?.cast<Object?>() ?? const <Object?>[];
      final result = db!.select(sql, params);
      final rows = [
        for (final row in result) Map<String, Object?>.from(row),
      ];
      readyPort.send({'id': id, 'ok': true, 'rows': rows});
    } catch (error) {
      readyPort.send({'id': id, 'ok': false, 'error': '$error'});
    }
  }, onDone: () {
    db?.close();
  });
}
