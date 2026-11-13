import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS Sparkle failure is forwarded to the Dart fallback', () async {
    const channel = MethodChannel('pdg.update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final messages = <String>[];
    AppUpdater.onMacOSUpdateFailed = messages.add;
    addTearDown(() => AppUpdater.onMacOSUpdateFailed = null);

    expect(await AppUpdater.checkForMacOSUpdates(), isTrue);
    await messenger.handlePlatformMessage(
      'pdg.update',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('updateFailed', {'message': 'feed unavailable'}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(messages, ['feed unavailable']);
  }, skip: !Platform.isMacOS);
}
