import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/settings_controller.dart';
import 'package:pdgapp/user/user_store.dart';

void main() {
  test('cached reference titles survive a reopen', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.cacheReferenceTitle('10.1103/ABC.123', 'A cached title');
    final reopened = await UserStore.open(overridePath: path);
    final cached = reopened.cachedReferenceTitle('10.1103/abc.123');
    expect(cached?.title, 'A cached title');
    expect(cached?.source, 'Crossref');
    await dir.delete(recursive: true);
  });

  test('per-PDF reading state survives a reopen', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-reading-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.setReviewState('review.pdf', {
      'page': 7,
      'sidebarWidth': 380.0,
      'dark': true,
    });
    final reopened = await UserStore.open(overridePath: path);
    final state = reopened.reviewState('review.pdf');
    expect(state?['page'], 7);
    expect(state?['sidebarWidth'], 380.0);
    expect(state?['dark'], isTrue);
    await dir.delete(recursive: true);
  });

  test('recent searches are kept per scope', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.addRecent('ea "Jia, Jiangyong"', 'inspire');
    await store.addRecent('D0 lifetime', 'all');
    await store.addRecent('ea "Jia, Jiangyong"', 'inspire');
    expect(
      store.recents
          .where((item) => item.scope == 'inspire')
          .map((item) => item.query),
      ['ea "Jia, Jiangyong"'],
    );
    expect(store.recents.first.query, 'ea "Jia, Jiangyong"');
    await dir.delete(recursive: true);
  });

  test('individual recent searches can be removed', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.addRecent('D0 lifetime', 'all');
    await store.addRecent('BESIII', 'particles');
    await store.removeRecent('D0 lifetime', 'all');
    expect(store.recents.map((item) => item.query), ['BESIII']);
    final reopened = await UserStore.open(overridePath: path);
    expect(reopened.recents.map((item) => item.query), ['BESIII']);
    await dir.delete(recursive: true);
  });

  test('text scale supports five levels and clamps oversized values', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.setSettings(store.settings.copyWith(textScale: 1.2));
    final reopened = await UserStore.open(overridePath: path);
    expect(reopened.settings.textScale, 1.2);

    await store.setSettings(store.settings.copyWith(textScale: 2.0));
    final clamped = await UserStore.open(overridePath: path);
    expect(clamped.settings.textScale, 1.2);
    await dir.delete(recursive: true);
  });

  test('detailed mode persists with settings', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    await store.setSettings(
      store.settings.copyWith(
        detailedMode: false,
        sidebarMode: 'always',
        noteLinkMode: 'sidebar',
      ),
    );
    final reopened = await UserStore.open(overridePath: path);
    expect(reopened.settings.detailedMode, isFalse);
    expect(reopened.settings.sidebarMode, 'always');
    expect(reopened.settings.noteLinkMode, 'sidebar');
    await dir.delete(recursive: true);
  });

  test('automatic update check date persists across restarts', () async {
    final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
    final path = '${dir.path}/user_store.json';
    final store = await UserStore.open(overridePath: path);
    final settings = SettingsController(store);

    expect(settings.settings.lastUpdateCheck, isEmpty);
    await settings.markUpdateChecked('2026-10-19');
    expect(settings.settings.lastUpdateCheck, '2026-10-19');

    final reopened = await UserStore.open(overridePath: path);
    expect(reopened.settings.lastUpdateCheck, '2026-10-19');
    await dir.delete(recursive: true);
  });

  test(
    'Zotero integration and index auto-update default on and persist',
    () async {
      final dir = await Directory.systemTemp.createTemp('pdgapp-store-');
      final path = '${dir.path}/user_store.json';
      final store = await UserStore.open(overridePath: path);
      final settings = SettingsController(store);

      expect(AppSettings.fromJson(<String, Object?>{}).zoteroEnabled, isTrue);
      expect(
        AppSettings.fromJson(<String, Object?>{}).autoUpdateZoteroIndex,
        isTrue,
      );
      expect(settings.zoteroEnabled, isTrue);
      expect(settings.autoUpdateZoteroIndex, isTrue);

      await settings.setZoteroEnabled(false);
      await settings.setAutoUpdateZoteroIndex(false);
      final reopened = await UserStore.open(overridePath: path);
      expect(reopened.settings.zoteroEnabled, isFalse);
      expect(reopened.settings.autoUpdateZoteroIndex, isFalse);
      await dir.delete(recursive: true);
    },
  );
  group('reading state from untrusted JSON', () {
    test('non-finite and out-of-range numbers are dropped on read', () async {
      final dir = await Directory.systemTemp.createTemp('pdgapp-state-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/user_store.json';
      // 1e999 decodes to infinity; write it the way a hand-edited or hostile
      // file would carry it.
      await File(path).writeAsString(
        '{"reviewStates": {"bad.pdf": {"page": 1e999, "sidebarTab": 1e999, '
        '"zoom": 1e999, "scroll": [1e999, 3], "dark": true, '
        '"future": "kept"}, "ok.pdf": {"page": 7, "zoom": 1.5, '
        '"scroll": [10.0, 200.5], "sidebarWidth": 380}}}',
      );
      final store = await UserStore.open(overridePath: path);

      final bad = store.reviewState('bad.pdf')!;
      expect(bad.containsKey('page'), isFalse);
      expect(bad.containsKey('sidebarTab'), isFalse);
      expect(bad.containsKey('zoom'), isFalse);
      expect(bad.containsKey('scroll'), isFalse);
      expect(bad['dark'], isTrue);
      expect(bad['future'], 'kept');

      final ok = store.reviewState('ok.pdf')!;
      expect(ok['page'], 7);
      expect(ok['zoom'], 1.5);
      expect(ok['scroll'], [10.0, 200.5]);
      expect(ok['sidebarWidth'], 380);
    });

    test('a zoom far outside the reader range is dropped', () {
      final clean = UserStore.sanitizeReviewState({'zoom': 500.0, 'page': 0});
      expect(clean, isEmpty);
    });

    test('restoring a backup does not carry unusable numbers in', () async {
      final dir = await Directory.systemTemp.createTemp('pdgapp-state-');
      addTearDown(() => dir.delete(recursive: true));
      final store = await UserStore.open(
        overridePath: '${dir.path}/user_store.json',
      );
      await store.importData({
        'reviewStates': {
          'x.pdf': {'page': double.infinity, 'dark': true},
        },
      });
      final state = store.reviewState('x.pdf')!;
      expect(state.containsKey('page'), isFalse);
      expect(state['dark'], isTrue);
    });
  });
}
