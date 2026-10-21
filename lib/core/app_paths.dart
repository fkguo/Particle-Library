import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves the application support directory.
///
/// On iOS the first path_provider platform-channel call can take seconds in
/// debug builds. The app container can be derived from dart:io's temporary
/// directory without a plugin call; fall back to path_provider only when that
/// derivation fails.
Future<Directory> appSupportDirectory() async {
  if (Platform.isIOS) {
    try {
      final temp = Directory.systemTemp;
      final support = Directory(
        '${temp.parent.path}/Library/Application Support',
      );
      if (await support.exists()) return support;
    } catch (_) {}
  }
  debugPrint('PATH fallback path_provider');
  return getApplicationSupportDirectory();
}
