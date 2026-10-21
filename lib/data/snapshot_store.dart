import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../core/contract.dart';
import '../core/errors.dart';
import '../core/app_paths.dart';
import '../app/boot_trace.dart';

class PreparedSnapshot {
  const PreparedSnapshot({
    required this.path,
    required this.sha256,
    required this.copiedFromBundle,
  });

  final String path;
  final String sha256;
  final bool copiedFromBundle;
}

/// Installs the bundled, verified snapshot into the application container.
///
/// The SHA-256 is verified on first install and whenever the installed file's
/// size or modification stamp changes. A small sidecar records the verified
/// hash so a normal launch does not re-read 64 MB on the UI isolate.
///
/// The file is never opened while it is being written: the bytes go to a
/// `.partial` file, are hashed, and only then renamed into place. A corrupt
/// installed file is quarantined and replaced from the bundle; user data lives
/// in a separate file and is never touched.
class SnapshotStore {
  SnapshotStore({this.assetName = SnapshotContract.assetName});

  final String assetName;

  /// Development override; production always stages the bundled asset.
  static const String _pathOverride = String.fromEnvironment(
    'PDG_SNAPSHOT_PATH',
  );

  Future<PreparedSnapshot> prepare({BootTrace? trace}) async {
    trace?.mark('prepare');
    if (_pathOverride.isNotEmpty) {
      final file = File(_pathOverride);
      if (!await file.exists()) {
        throw AppException(
          AppErrorCode.snapshotMissing,
          '开发指定数据库不存在。',
          detail: _pathOverride,
        );
      }
      final digest = await _hashFile(file);
      if (digest != SnapshotContract.expectedSha256) {
        throw AppException(
          AppErrorCode.snapshotMismatch,
          '开发数据库的哈希与设计基线不一致。',
          detail: '$digest\n$_pathOverride',
        );
      }
      return PreparedSnapshot(
        path: file.path,
        sha256: digest,
        copiedFromBundle: false,
      );
    }

    Directory dir;
    try {
      trace?.mark('path-start');
      final support = await appSupportDirectory();
      trace?.mark('path');
      dir = Directory('${support.path}/ParticleDesk');
      // create(recursive: true) is a no-op when the directory exists.
      await dir.create(recursive: true);
    } catch (error) {
      throw AppException(
        AppErrorCode.storageUnavailable,
        '无法访问应用数据目录。',
        detail: '$error',
      );
    }

    trace?.mark('dir');
    final target = File('${dir.path}/${SnapshotContract.fileName}');
    // A single stat replaces exists() + length() on the launch path.
    final targetStat = await target.stat();
    trace?.mark('stat');
    if (targetStat.type != FileSystemEntityType.notFound) {
      final correctSize = targetStat.size == SnapshotContract.expectedSizeBytes;
      if (correctSize) {
        final cached = await _cachedVerifiedHash(target, targetStat);
        trace?.mark('stamp');
        if (cached == SnapshotContract.expectedSha256) {
          return PreparedSnapshot(
            path: target.path,
            sha256: cached!,
            copiedFromBundle: false,
          );
        }
      }
      trace?.mark('hash-start');
      final digest = correctSize ? await _hashFile(target) : null;
      trace?.mark('hash');
      if (digest == SnapshotContract.expectedSha256) {
        await _writeVerificationStamp(target, digest!);
        return PreparedSnapshot(
          path: target.path,
          sha256: digest,
          copiedFromBundle: false,
        );
      }
      final quarantine = File(
        '${target.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
      try {
        await target.rename(quarantine.path);
      } catch (_) {
        try {
          await target.delete();
        } catch (_) {}
      }
    }

    trace?.mark('copy-start');
    final bytes = await _loadAsset();
    trace?.mark('asset');
    final digest = await Isolate.run(() => sha256.convert(bytes).toString());
    trace?.mark('verify');
    if (digest != SnapshotContract.expectedSha256) {
      throw AppException(
        AppErrorCode.snapshotMismatch,
        '随包数据库的哈希与已验证基线不一致，已拒绝启用。',
        detail: 'expected ${SnapshotContract.expectedSha256}\nactual   $digest',
      );
    }
    final partial = File('${target.path}.partial');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(target.path);
    } catch (error) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      throw AppException(
        AppErrorCode.storageUnavailable,
        '无法写入离线数据库副本。',
        detail: '$error',
      );
    }
    await _writeVerificationStamp(target, digest);
    trace?.mark('install');
    return PreparedSnapshot(
      path: target.path,
      sha256: digest,
      copiedFromBundle: true,
    );
  }

  File _stampFile(File target) => File('${target.path}.verified.json');

  Future<String?> _cachedVerifiedHash(File target, FileStat stat) async {
    try {
      // A missing stamp throws and is treated as "not verified yet", so the
      // launch path does not pay a separate exists() call.
      final decoded = jsonDecode(await _stampFile(target).readAsString());
      if (decoded is! Map) return null;
      if (decoded['size'] != stat.size ||
          decoded['modifiedMs'] != stat.modified.millisecondsSinceEpoch) {
        return null;
      }
      final hash = decoded['sha256'];
      return hash is String && hash.length == 64 ? hash : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeVerificationStamp(File target, String hash) async {
    try {
      final stat = await target.stat();
      await _stampFile(target).writeAsString(
        jsonEncode({
          'sha256': hash,
          'size': stat.size,
          'modifiedMs': stat.modified.millisecondsSinceEpoch,
        }),
        flush: true,
      );
    } catch (_) {
      // The hash is already verified; a missing cache only costs one re-hash
      // on the next launch.
    }
  }

  Future<Uint8List> _loadAsset() async {
    try {
      final data = await rootBundle.load(assetName);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (error) {
      throw AppException(
        AppErrorCode.snapshotMissing,
        '应用包内未找到离线数据库。',
        detail: '$error',
      );
    }
  }

  Future<String> _hashFile(File file) async {
    try {
      final path = file.path;
      final digest = await Isolate.run(() async {
        final digest = await sha256.bind(File(path).openRead()).first;
        return digest.toString();
      });
      return digest;
    } catch (error) {
      throw AppException(
        AppErrorCode.corruptDatabase,
        '无法校验数据库文件。',
        detail: '$error',
      );
    }
  }
}
