import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Progress of an in-app APK download. [total] is -1 when the server did not
/// send a Content-Length.
class UpdateDownloadProgress {
  const UpdateDownloadProgress(this.received, this.total);

  final int received;
  final int total;

  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads a release asset to the app cache. Only HTTPS URLs are accepted.
Future<File> downloadUpdateAsset(
  Uri url, {
  required String fileName,
  required void Function(UpdateDownloadProgress) onProgress,
  Duration timeout = const Duration(seconds: 20),
  Duration totalTimeout = const Duration(minutes: 15),
}) async {
  if (url.scheme != 'https' || url.host.isEmpty) {
    throw const UpdateDownloadException('Refusing a non-HTTPS download.');
  }
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  await dir.create(recursive: true);
  final target = File('${dir.path}/$fileName');
  final partial = File('${target.path}.part');
  final client = HttpClient()..connectionTimeout = timeout;
  final deadline = DateTime.now().add(totalTimeout);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'ParticleLibrary');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateDownloadException(
        'Download server returned HTTP ${response.statusCode}.',
      );
    }
    final total = response.contentLength;
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.timeout(timeout)) {
        if (DateTime.now().isAfter(deadline)) {
          throw const UpdateDownloadException(
            'The download exceeded the overall time limit.',
          );
        }
        received += chunk.length;
        if (received > 300 * 1024 * 1024) {
          throw const UpdateDownloadException('Update file is too large.');
        }
        sink.add(chunk);
        onProgress(UpdateDownloadProgress(received, total));
      }
    } finally {
      await sink.close();
    }
    if (await target.exists()) await target.delete();
    return await partial.rename(target.path);
  } catch (error) {
    if (await partial.exists()) {
      try {
        await partial.delete();
      } catch (_) {
        // The partial file is in the cache; a later download overwrites it.
      }
    }
    if (error is UpdateDownloadException) rethrow;
    throw UpdateDownloadException('Download failed: $error');
  } finally {
    client.close(force: true);
  }
}
