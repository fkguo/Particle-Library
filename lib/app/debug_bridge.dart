import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/catalog/catalog_page.dart';
import '../features/entry/entry_route_page.dart';
import '../features/help/help_page.dart';
import '../features/reference/reference_page.dart';
import '../features/reviews/reviews_page.dart';
import '../features/reviews/review_viewer_page.dart';
import '../data/review_cache.dart';
import 'debug_hooks.dart';

/// Developer-only service extensions used by the screenshot harness.
///
/// They are registered only in debug builds and are not reachable from the
/// product UI. Pages opened here are the real pages with the real database.
void registerDebugBridge(GlobalKey<NavigatorState> navigatorKey) {
  if (!kDebugMode) return;

  void navigate(Widget page) {
    final navigator = navigatorKey.currentState;
    navigator?.push(debugRoute(page));
  }

  developer.registerExtension('ext.pdg.reviewViewer', (method, parameters) async {
    final file = parameters['file'] ?? 'rpp2026-rev-rpp-intro.pdf';
    final cache = await ReviewCache.open();
    final path = cache.fileFor(file).path;
    navigate(ReviewViewerPage(
      title: file,
      path: path,
      officialUrl: 'https://pdg.lbl.gov/2026/reviews/$file',
    ));
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.reviews', (method, parameters) async {
    navigate(const ReviewsPage());
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.help', (method, parameters) async {
    navigate(const HelpPage());
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.openPdgid', (method, parameters) async {
    final pdgid = parameters['pdgid'];
    if (pdgid == null || navigatorKey.currentState == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'navigator or pdgid missing',
      );
    }
    navigate(EntryRoutePage(pdgid: pdgid));
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.openReference', (method, parameters) async {
    final id = int.tryParse(parameters['id'] ?? '');
    if (id == null || navigatorKey.currentState == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'navigator or reference id missing',
      );
    }
    navigate(ReferencePage(referenceId: id));
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.search', (method, parameters) async {
    final query = parameters['q'];
    if (query == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'q missing',
      );
    }
    debugTabHook?.call(0);
    debugSearchHook?.call(query);
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.tab', (method, parameters) async {
    final index = int.tryParse(parameters['index'] ?? '');
    if (index == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'index missing',
      );
    }
    debugTabHook?.call(index);
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.theme', (method, parameters) async {
    final value = parameters['value'];
    if (value == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'value missing',
      );
    }
    debugThemeHook?.call(value);
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.openCatalog', (method, parameters) async {
    navigate(const CatalogPage());
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.scroll', (method, parameters) async {
    final target = double.tryParse(parameters['offset'] ?? '');
    if (target == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'offset missing',
      );
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      void visit(Element element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (position.hasPixels && position.hasContentDimensions) {
            position.jumpTo(target.clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ));
          }
        }
        element.visitChildren(visit);
      }

      visit(root);
    }
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  if (defaultTargetPlatform != TargetPlatform.windows) {
    developer.registerExtension('ext.pdg.resize', (method, parameters) async {
      final width = double.tryParse(parameters['width'] ?? '');
      final height = double.tryParse(parameters['height'] ?? '');
      if (width == null || height == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'width/height missing',
        );
      }
      await const MethodChannel('pdg.debug')
          .invokeMethod<void>('resize', {'width': width, 'height': height});
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    });
  }

  developer.registerExtension('ext.pdg.state', (method, parameters) async {
    final state = debugStateHook?.call() ?? '{"error":"no state hook"}';
    return developer.ServiceExtensionResponse.result(state);
  });

  developer.registerExtension('ext.pdg.openTrend', (method, parameters) async {
    final hook = debugTrendHook;
    if (hook == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'trend page not active',
      );
    }
    hook();
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });

  developer.registerExtension('ext.pdg.popToRoot', (method, parameters) async {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    return developer.ServiceExtensionResponse.result('{"ok":true}');
  });
}
