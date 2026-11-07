import 'dart:io';

import 'package:flutter/services.dart';

/// Platform bridge for in-app updates.
///
/// macOS delegates the download, signature check and replacement of the app
/// bundle to Sparkle. Android exposes an APK installer prompt; the operating
/// system still asks the user to confirm the installation.
class AppUpdater {
  AppUpdater._();

  static const MethodChannel _channel = MethodChannel('pdg.update');

  static bool get isMacOS => Platform.isMacOS;
  static bool get isAndroid => Platform.isAndroid;

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
  static Future<bool> installAndroidApk(String path) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('installApk', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Sparkle's standard update UI. Returns false when the native bridge
  /// is unavailable, so the caller can fall back to the release page.
  static Future<bool> checkForMacOSUpdates() async {
    if (!isMacOS) return false;
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
