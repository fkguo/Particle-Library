import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../core/app_paths.dart';
import '../core/review_index_contract.dart';
import 'sql_executor.dart';

/// Installs the bundled review index into the application container and opens
/// it read-only.  The index is independent from the pdgall snapshot: a review
/// failure never prevents the PDG library from opening.
class ReviewIndexStore {
  ReviewIndexStore({this.assetName = ReviewIndexContract.assetName});

  final String assetName;
  Future<SqlExecutor>? _opening;
  SqlExecutor? _executor;

  Future<SqlExecutor> open() {
    final existing = _executor;
    if (existing != null) return Future<SqlExecutor>.value(existing);
    final running = _opening;
    if (running != null) return running;
    final future = _open();
    _opening = future;
    future
        .then<void>((executor) => _executor = executor, onError: (Object _) {})
        .ignore();
    future.whenComplete(() {
      if (identical(_opening, future)) _opening = null;
    }).ignore();
    return future;
  }

  Future<SqlExecutor> _open() async {
    final support = await appSupportDirectory();
    final dir = Directory(
      '${support.path}/ParticleDesk/review_index/'
      '${ReviewIndexContract.expectedEdition}',
    );
    await dir.create(recursive: true);
    final target = File('${dir.path}/review_index.sqlite');

    var valid = false;
    if (await target.exists() &&
        await target.length() == ReviewIndexContract.expectedSizeBytes) {
      final installed = await target.readAsBytes();
      valid =
          sha256.convert(installed).toString() ==
          ReviewIndexContract.expectedSha256;
    }
    if (!valid) {
      final data = await rootBundle.load(assetName);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != ReviewIndexContract.expectedSizeBytes ||
          sha256.convert(bytes).toString() !=
              ReviewIndexContract.expectedSha256) {
        throw StateError('综述索引资产与 contract 不一致。');
      }
      final partial = File('${target.path}.partial');
      await partial.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    }
    return IsolateSqlExecutor.open(target.path);
  }
}
