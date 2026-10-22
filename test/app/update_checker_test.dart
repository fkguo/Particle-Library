import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/update_checker.dart';

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
