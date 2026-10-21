import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory>? _supportDirectory;

/// Resolves the application support directory.
///
/// On iOS the first path_provider platform-channel call can take seconds in
/// debug builds and it is issued by several boot tasks at once. The app
/// container can be derived from dart:io's temporary directory without a
/// plugin call, so that path is used directly and the directory is created on
/// demand; path_provider remains the fallback when the derivation fails.
///
/// The result is cached for the process lifetime so the snapshot, user store
/// and notes store share a single resolution instead of racing three.
Future<Directory> appSupportDirectory() {
  return _supportDirectory ??= _resolveSupportDirectory();
}

Future<Directory> _resolveSupportDirectory() async {
  final watch = Stopwatch()..start();
  final derived = _deriveIosContainerSupport();
  if (kDebugMode) {
    debugPrint('PATH probe ${watch.elapsedMilliseconds}ms');
  }
  if (derived != null) {
    try {
      // One call: create(recursive: true) is a no-op when the directory
      // already exists, which avoids a separate stat on every launch.
      await derived.create(recursive: true);
      if (kDebugMode) {
        debugPrint('PATH resolved ${watch.elapsedMilliseconds}ms');
      }
      return derived;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PATH derive failed (${derived.path}): $error');
      }
    }
  }
  if (kDebugMode) {
    debugPrint('PATH fallback path_provider');
  }
  return getApplicationSupportDirectory();
}

/// iOS: `<container>/tmp` is the process temporary directory, so the support
/// directory is the sibling `Library/Application Support`. It frequently does
/// not exist yet on a fresh install, which is why existence is not required —
/// the caller creates it. Returns null when the shape is not an app container
/// (for example a macOS temporary directory).
Directory? _deriveIosContainerSupport() {
  if (!Platform.isIOS) return null;
  try {
    final temp = Directory.systemTemp;
    if (!temp.existsSync()) return null;
    final container = temp.parent;
    if (container.path.isEmpty) return null;
    return Directory('${container.path}/Library/Application Support');
  } catch (_) {
    return null;
  }
}

/// Test-only: forget the cached support directory.
@visibleForTesting
void resetAppSupportDirectoryCache() {
  _supportDirectory = null;
}
