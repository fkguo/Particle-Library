import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_strings.dart';
import 'app_updater.dart';
import 'update_download.dart';
import 'app_version.g.dart';

/// Current application version. Generated from `pubspec.yaml` by
/// `tool/generate_app_version.py`; do not hardcode it here.
const String appVersion = generatedAppVersion;

/// Optional override for testing or for a self-hosted release manifest.
///
/// The default points at the public GitHub Releases API. While the repository
/// is private this returns 404; the UI reports "update check unavailable"
/// rather than crashing. Pass
/// `--dart-define=UPDATE_MANIFEST_URL=https://.../latest.json` to test another
/// endpoint.
/// App Store product ID. Set at build time for the iOS App Store build, e.g.
/// `--dart-define=APP_STORE_APP_ID=1234567890`. No GitHub update endpoint is
/// contacted on iOS.
const String appStoreAppId = String.fromEnvironment('APP_STORE_APP_ID');

const String updateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue:
      'https://api.github.com/repos/fkguo/Particle-Library/releases/latest',
);

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = '',
    this.androidDownloadUrl,
  });

  final String version;
  final String url;
  final String notes;

  /// Direct APK asset, when the release manifest (or GitHub API response)
  /// provides one. iOS never uses it and macOS updates through Sparkle.
  final String? androidDownloadUrl;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateChecker {
  UpdateChecker._();

  /// iOS updates are delivered by the App Store; the app must not direct users
  /// to download an IPA from GitHub.
  static bool get isAppStoreManaged => Platform.isIOS;

  static String? get appStoreUrl => appStoreAppId.trim().isEmpty
      ? null
      : 'https://apps.apple.com/app/id${appStoreAppId.trim()}';

  static bool get isConfigured =>
      !isAppStoreManaged &&
      (Uri.tryParse(updateManifestUrl)?.hasScheme ?? false);

  /// Returns a newer release, or null when the app is current.
  ///
  /// Accepts either a GitHub Releases API response or a small manifest:
  /// `{"version":"0.2.0","url":"https://...","notes":"..."}`.
  ///
  /// The default check tries a CDN-hosted manifest first (accessible where the
  /// GitHub API is blocked/rate-limited), then raw GitHub, then the API.
  static Future<UpdateInfo?> check({
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (isAppStoreManaged) {
      throw const UpdateCheckException(
        'Updates for iOS are delivered by the App Store.',
      );
    }
    if (endpoint != null) return _checkOne(endpoint, timeout);
    final override = const String.fromEnvironment('UPDATE_MANIFEST_URL');
    final endpoints = override.isNotEmpty
        ? [Uri.parse(override)]
        : _defaultEndpoints;
    Object? lastError;
    UpdateInfo? best;
    var responded = 0;
    for (final uri in endpoints) {
      try {
        final candidate = await _checkOne(uri, timeout);
        responded++;
        if (candidate != null &&
            (best == null ||
                compareVersions(candidate.version, best.version) > 0)) {
          best = candidate;
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (best != null) return best;
    if (responded == 0) {
      throw UpdateCheckException(
        'No update endpoint responded. Last error: $lastError',
      );
    }
    return null;
  }

  static final List<Uri> _defaultEndpoints = [
    Uri.parse(
      'https://cdn.jsdelivr.net/gh/fkguo/Particle-Library@main/update.json',
    ),
    Uri.parse(
      'https://raw.githubusercontent.com/fkguo/Particle-Library/main/update.json',
    ),
    Uri.parse(updateManifestUrl),
  ];

  static Future<UpdateInfo?> _checkOne(Uri uri, Duration timeout) async {
    if (!uri.hasScheme) {
      throw const UpdateCheckException('No update endpoint is configured.');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ParticleLibrary');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateCheckException(
          response.statusCode == HttpStatus.notFound
              ? 'No published release is reachable yet.'
              : 'Update server returned HTTP ${response.statusCode}.',
        );
      }
      final body = await _readBody(response, timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const UpdateCheckException('Invalid update response.');
      }
      final data = Map<String, Object?>.from(decoded);
      final version =
          (data['version'] ?? data['tag_name'])?.toString().trim() ?? '';
      final url = (data['html_url'] ?? data['url'])?.toString().trim() ?? '';
      final notes = (data['notes'] ?? data['body'])?.toString().trim() ?? '';
      if (version.isEmpty || url.isEmpty) {
        throw const UpdateCheckException('Update response lacks version/url.');
      }
      final androidDownloadUrl = _androidDownloadUrl(data);
      return compareVersions(version, appVersion) > 0
          ? UpdateInfo(
              version: version.replaceFirst(RegExp(r'^[vV]'), ''),
              url: url,
              notes: notes,
              androidDownloadUrl: androidDownloadUrl,
            )
          : null;
    } on UpdateCheckException {
      rethrow;
    } on SocketException catch (error) {
      throw UpdateCheckException('Cannot reach the update server: $error');
    } on HttpException catch (error) {
      throw UpdateCheckException('Update request failed: $error');
    } on TimeoutException {
      throw const UpdateCheckException(
        'The update server did not respond in time.',
      );
    } on FormatException catch (error) {
      throw UpdateCheckException('Invalid update data: $error');
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readBody(
    HttpClientResponse response,
    Duration timeout,
  ) async {
    const maxBytes = 1 << 20;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const UpdateCheckException('Update response is too large.');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: false);
  }

  /// Accepts either a small manifest's `downloads.android` or the GitHub API's
  /// `assets` array. Asset names are stable across releases.
  static String? _androidDownloadUrl(Map<String, Object?> data) {
    final downloads = data['downloads'];
    if (downloads is Map) {
      final raw = (downloads['android'] ?? downloads['apk'])?.toString() ?? '';
      if (isSafeUpdateUrl(raw) && raw.toLowerCase().endsWith('.apk')) {
        return raw;
      }
    }
    final assets = data['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map) continue;
        final name = item['name']?.toString().toLowerCase() ?? '';
        final raw = item['browser_download_url']?.toString() ?? '';
        if (name.endsWith('.apk') &&
            name.contains('arm64') &&
            isSafeUpdateUrl(raw)) {
          return raw;
        }
      }
    }
    return null;
  }

  static int compareVersions(String a, String b) {
    final left = _Version.parse(a);
    final right = _Version.parse(b);
    for (var i = 0; i < 3; i++) {
      final comparison = left.core[i].compareTo(right.core[i]);
      if (comparison != 0) return comparison;
    }
    // A release sorts after all of its prereleases; build metadata is ignored.
    if (left.pre.isEmpty && right.pre.isEmpty) return 0;
    if (left.pre.isEmpty) return 1;
    if (right.pre.isEmpty) return -1;
    final length = left.pre.length > right.pre.length
        ? left.pre.length
        : right.pre.length;
    for (var i = 0; i < length; i++) {
      if (i >= left.pre.length) return -1;
      if (i >= right.pre.length) return 1;
      final l = left.pre[i];
      final r = right.pre[i];
      final ln = int.tryParse(l);
      final rn = int.tryParse(r);
      if (ln != null && rn != null) {
        final comparison = ln.compareTo(rn);
        if (comparison != 0) return comparison;
      } else if (ln != null) {
        return -1; // numeric identifiers sort before alphanumeric ones
      } else if (rn != null) {
        return 1;
      } else {
        final comparison = l.compareTo(r);
        if (comparison != 0) return comparison;
      }
    }
    return 0;
  }
}

class _Version {
  _Version(this.core, this.pre);

  final List<int> core;
  final List<String> pre;

  static _Version parse(String raw) {
    final withoutV = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final withoutBuild = withoutV.split('+').first;
    final dash = withoutBuild.indexOf('-');
    final coreText = dash < 0 ? withoutBuild : withoutBuild.substring(0, dash);
    final preText = dash < 0 ? '' : withoutBuild.substring(dash + 1);
    final core = coreText
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    while (core.length < 3) {
      core.add(0);
    }
    return _Version(
      core,
      preText.isEmpty ? const <String>[] : preText.split('.'),
    );
  }
}

/// Whether [url] may be opened from the update dialog: an https address with a
/// host. The manifest comes from a CDN or a mirror and is not signed, so a
/// plain-http or host-less link is never offered.
bool isSafeUpdateUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  AppStrings strings,
  UpdateInfo info,
) async {
  final safeUrl = isSafeUpdateUrl(info.url);
  final host = Uri.tryParse(info.url)?.host ?? '';
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.updateAvailableTitle(info.version)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
        child: SingleChildScrollView(
          child: Text(
            // The page the button opens is shown, so a manifest that points
            // somewhere unexpected is visible before it is followed.
            [
              strings.updateAvailableMessage,
              if (info.notes.isNotEmpty) info.notes,
              if (host.isNotEmpty) host,
            ].join('\n\n'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.updateLater),
        ),
        FilledButton(
          onPressed: safeUrl ? () => Navigator.of(context).pop(true) : null,
          child: Text(_updateActionLabel(strings, info)),
        ),
      ],
    ),
  );
  if (open != true) return;
  if (await AppUpdater.checkForMacOSUpdates()) return;
  if (!context.mounted) return;
  final androidUrl = info.androidDownloadUrl;
  if (AppUpdater.isAndroid &&
      androidUrl != null &&
      isSafeUpdateUrl(androidUrl)) {
    await _downloadAndInstallAndroid(context, strings, info, androidUrl);
    return;
  }
  final uri = Uri.tryParse(info.url);
  if (uri != null && isSafeUpdateUrl(info.url)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String _updateActionLabel(AppStrings strings, UpdateInfo info) {
  if (AppUpdater.isMacOS) return strings.updateNow;
  if (AppUpdater.isAndroid &&
      info.androidDownloadUrl != null &&
      isSafeUpdateUrl(info.androidDownloadUrl!)) {
    return strings.updateInstall;
  }
  return strings.updateOpen;
}

bool _androidUpdateInProgress = false;

Future<void> _downloadAndInstallAndroid(
  BuildContext context,
  AppStrings strings,
  UpdateInfo info,
  String url,
) async {
  if (_androidUpdateInProgress) return;
  _androidUpdateInProgress = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<UpdateDownloadProgress>(
    const UpdateDownloadProgress(0, -1),
  );
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _AndroidUpdateProgressDialog(strings: strings, progress: progress),
  );
  final routeClosed = navigator.push(route);
  try {
    final file = await downloadUpdateAsset(
      Uri.parse(url),
      fileName:
          'Particle-Library-${info.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_')}-Android-arm64-v8a.apk',
      onProgress: (value) => progress.value = value,
    );
    // Remove only this route. If the navigator went away while downloading,
    // never pop whatever happens to be on top.
    if (route.isActive) navigator.removeRoute(route);
    await routeClosed;
    if (!context.mounted) return;
    await _installDownloadedAndroidApk(context, strings, info, file);
  } catch (error) {
    if (route.isActive) navigator.removeRoute(route);
    await routeClosed;
    if (context.mounted) {
      await _showAndroidUpdateError(context, strings, info, '$error');
    }
  } finally {
    _androidUpdateInProgress = false;
    progress.dispose();
  }
}

class _AndroidUpdateProgressDialog extends StatelessWidget {
  const _AndroidUpdateProgressDialog({
    required this.strings,
    required this.progress,
  });

  final AppStrings strings;
  final ValueListenable<UpdateDownloadProgress> progress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(strings.updateDownloading),
        content: ValueListenableBuilder<UpdateDownloadProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            final total = value.total > 0
                ? '${(value.total / 1048576).toStringAsFixed(1)} MB'
                : '?';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: value.fraction),
                const SizedBox(height: 10),
                Text(
                  '${(value.received / 1048576).toStringAsFixed(1)} / $total',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _installDownloadedAndroidApk(
  BuildContext context,
  AppStrings strings,
  UpdateInfo info,
  File file,
) async {
  final result = await AppUpdater.installAndroidApk(file.path);
  if (result.success || !context.mounted) return;
  final permissionMissing =
      result.code == 'install_permission' ||
      (result.code == 'install_failed' &&
          !(await AppUpdater.canInstallAndroidPackages()));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.updateInstallFailedTitle),
      content: Text(
        permissionMissing
            ? strings.updateInstallPermission
            : (result.message?.trim().isNotEmpty == true
                  ? result.message!
                  : strings.updateInstallFailed),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.commonClose),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(
              _installDownloadedAndroidApk(context, strings, info, file),
            );
          },
          child: Text(strings.commonRetry),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(_openUpdatePage(info));
          },
          child: Text(strings.updateOpen),
        ),
      ],
    ),
  );
}

Future<void> _showAndroidUpdateError(
  BuildContext context,
  AppStrings strings,
  UpdateInfo info,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.updateDownloadFailed),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.commonClose),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(_openUpdatePage(info));
          },
          child: Text(strings.updateOpen),
        ),
      ],
    ),
  );
}

Future<void> _openUpdatePage(UpdateInfo info) async {
  final uri = Uri.tryParse(info.url);
  if (uri != null && isSafeUpdateUrl(info.url)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
