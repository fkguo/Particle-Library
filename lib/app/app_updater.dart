import 'dart:io';

import 'package:flutter/services.dart';

/// Platform bridge for in-app updates.
///
/// macOS delegates the download, signature check and replacement of the app
/// bundle to Sparkle. Android exposes an APK installer prompt; the operating
/// system still asks the user to confirm the installation.
class AndroidInstallResult {
  const AndroidInstallResult({required this.success, this.code, this.message});

  final bool success;
  final String? code;
  final String? message;

  static const unsupported = AndroidInstallResult(
    success: false,
    code: 'unsupported',
    message: 'In-app installation is only available on Android.',
  );
}

class AppUpdater {
  AppUpdater._();

  static const MethodChannel _channel = MethodChannel('pdg.update');

  static bool get isMacOS => Platform.isMacOS;
  static bool get isAndroid => Platform.isAndroid;

  /// Invoked when Sparkle reports a failed update cycle. The update dialog
  /// registers this to show a Dart fallback with the release-page button.
  static void Function(String message)? onMacOSUpdateFailed;
  static bool _failureHandlerInstalled = false;

  static void _installFailureHandler() {
    if (_failureHandlerInstalled) return;
    _failureHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'updateFailed') return;
      final args = call.arguments;
      final message = args is Map ? args['message']?.toString() : null;
      final text = (message ?? '').trim();
      onMacOSUpdateFailed?.call(text);
    });
  }

  /// Whether the system currently permits this app to launch an APK installer.
  static Future<bool> canInstallAndroidPackages() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Launches the Android package installer. The user still has to confirm the
  /// installation in the system dialog.
  static Future<AndroidInstallResult> installAndroidApk(String path) async {
    if (!isAndroid) return AndroidInstallResult.unsupported;
    try {
      final success =
          await _channel.invokeMethod<bool>('installApk', {'path': path}) ??
          false;
      return success
          ? const AndroidInstallResult(success: true)
          : const AndroidInstallResult(success: false, code: 'install_failed');
    } on PlatformException catch (error) {
      return AndroidInstallResult(
        success: false,
        code: error.code,
        message: error.message,
      );
    } on MissingPluginException {
      return const AndroidInstallResult(success: false, code: 'unavailable');
    }
  }

  /// Opens Sparkle's standard update UI. Returns false when the native bridge
  /// is unavailable, so the caller can fall back to the release page.
  static Future<bool> checkForMacOSUpdates() async {
    if (!isMacOS) return false;
    _installFailureHandler();
    try {
      await _channel.invokeMethod<void>('checkForUpdates');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
