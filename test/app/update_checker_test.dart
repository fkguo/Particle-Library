import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/update_checker.dart';
import 'package:pdgapp/app/update_download.dart';

void main() {
  test('version comparison handles v-prefix and numeric parts', () {
    expect(UpdateChecker.compareVersions('v0.2.0', '0.1.0'), greaterThan(0));
    expect(UpdateChecker.compareVersions('0.1', '0.1.0'), 0);
    expect(UpdateChecker.compareVersions('0.0.9', '0.1.0'), lessThan(0));
    expect(UpdateChecker.compareVersions('0.1.0-rc1', '0.1.0'), lessThan(0));
    expect(
      UpdateChecker.compareVersions('0.1.0-rc2', '0.1.0-rc1'),
      greaterThan(0),
    );
    expect(UpdateChecker.compareVersions('0.1.0+1', '0.1.0'), 0);
  });

  test('reads a manifest and detects a newer version', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'version': '9.9.9',
          'url': 'https://example.com/releases/9.9.9',
          'notes': 'New PDF tools',
        }),
      );
      await request.response.close();
    });
    final info = await UpdateChecker.check(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
    );
    expect(info, isNotNull);
    expect(info!.version, '9.9.9');
    expect(info.notes, 'New PDF tools');
  });

  test('refuses a non-HTTPS update download', () async {
    await expectLater(
      downloadUpdateAsset(
        Uri.parse('http://example.com/app.apk'),
        fileName: 'app.apk',
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
  });

  test('reads an Android APK download from the manifest', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write(
        jsonEncode({
          'version': '9.9.9',
          'url': 'https://example.com/releases/9.9.9',
          'downloads': {
            'android':
                'https://example.com/releases/Particle-Library-9.9.9-arm64.apk',
          },
        }),
      );
      await request.response.close();
    });
    final info = await UpdateChecker.check(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
    );
    expect(info, isNotNull);
    expect(
      info!.androidDownloadUrl,
      'https://example.com/releases/Particle-Library-9.9.9-arm64.apk',
    );
  });

  test('falls back to the arm64 APK asset in a GitHub API response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write(
        jsonEncode({
          'tag_name': 'v9.9.9',
          'html_url': 'https://example.com/releases/9.9.9',
          'assets': [
            {
              'name': 'Particle-Library-9.9.9-macOS-universal.zip',
              'browser_download_url': 'https://example.com/app.zip',
            },
            {
              'name': 'Particle-Library-9.9.9-Android-arm64-v8a.apk',
              'browser_download_url': 'https://example.com/app-arm64.apk',
            },
          ],
        }),
      );
      await request.response.close();
    });
    final info = await UpdateChecker.check(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
    );
    expect(info?.androidDownloadUrl, 'https://example.com/app-arm64.apk');
  });

  test(
    'current version returns null and missing release is an error',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var missing = false;
      server.listen((request) async {
        if (missing) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.write(
            jsonEncode({
              'version': '0.1.1',
              'url': 'https://example.com/releases/0.1.1',
            }),
          );
        }
        await request.response.close();
      });
      expect(
        await UpdateChecker.check(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
        ),
        isNull,
      );
      missing = true;
      await expectLater(
        UpdateChecker.check(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    },
  );
}
