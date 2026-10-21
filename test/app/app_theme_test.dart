import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows keeps Segoe UI and uses the two YaHei fallbacks', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final theme = AppTheme.light();

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Segoe UI');
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      AppFonts.windowsChineseFallback,
    );
    expect(AppFonts.monospaceFamily, 'Consolas');
  });

  test('macOS keeps native typography and Menlo monospace', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final theme = AppTheme.light();

    expect(theme.textTheme.bodyMedium?.fontFamily, '.AppleSystemUIFont');
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, isNull);
    expect(AppFonts.monospaceFamily, 'Menlo');
  });
}
