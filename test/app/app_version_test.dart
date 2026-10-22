import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/update_checker.dart';

void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)(?:\+\S+)?\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    // The update check and the About page read appVersion. When it lags the
    // pubspec, the installed release keeps offering itself as an update.
    expect(appVersion, match!.group(1));
  });

  test(
    'a release is not offered to the build that already is that release',
    () {
      expect(UpdateChecker.compareVersions('0.2.0', appVersion), 0);
      expect(UpdateChecker.compareVersions('v0.2.0', appVersion), 0);
      expect(
        UpdateChecker.compareVersions('0.2.1', appVersion),
        greaterThan(0),
      );
    },
  );
}
