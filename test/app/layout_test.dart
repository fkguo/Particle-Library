import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/layout.dart';

void main() {
  group('AppLayout.ofSize', () {
    test('a phone keeps one class across rotation', () {
      expect(AppLayout.ofSize(const Size(393, 852)), LayoutClass.compact);
      expect(AppLayout.ofSize(const Size(852, 393)), LayoutClass.compact);
    });

    test('a small tablet keeps one class across rotation', () {
      expect(AppLayout.ofSize(const Size(834, 1194)), LayoutClass.medium);
      expect(AppLayout.ofSize(const Size(1194, 834)), LayoutClass.medium);
    });

    test('a large tablet keeps one class across rotation', () {
      expect(AppLayout.ofSize(const Size(1024, 1366)), LayoutClass.expanded);
      expect(AppLayout.ofSize(const Size(1366, 1024)), LayoutClass.expanded);
    });

    test('the class follows the shortest side, not the width', () {
      // Tall and narrow desktop windows stay in the small class.
      expect(AppLayout.ofSize(const Size(500, 1400)), LayoutClass.compact);
      // Wide but short windows are not promoted.
      expect(AppLayout.ofSize(const Size(1600, 500)), LayoutClass.compact);
    });

    test('the medium and expanded thresholds are inclusive', () {
      expect(AppLayout.ofSize(const Size(600, 600)), LayoutClass.medium);
      expect(AppLayout.ofSize(const Size(1024, 1024)), LayoutClass.expanded);
      expect(AppLayout.ofSize(const Size(599, 800)), LayoutClass.compact);
      expect(AppLayout.ofSize(const Size(1023, 1023)), LayoutClass.medium);
    });
  });
}
