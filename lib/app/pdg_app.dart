import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'app_shell.dart';
import 'app_strings.dart';
import 'app_theme.dart';
import '../domain/labels.dart';
import 'bootstrap.dart';
import 'boot_trace.dart';
import 'debug_bridge.dart';
import 'debug_hooks.dart';
import 'boot_screen.dart';
import '../user/user_store.dart';

class PdgApp extends StatefulWidget {
  const PdgApp({super.key, this.bootLoader});

  /// Injectable for widget tests; production uses [AppBootstrap.load].
  final Future<AppServices> Function()? bootLoader;

  @override
  State<PdgApp> createState() => _PdgAppState();
}

class _PdgAppState extends State<PdgApp> with WidgetsBindingObserver {
  AppServices? _services;
  Object? _error;
  TextLang? _bootLanguage;
  bool _loading = true;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _debugBridgeRegistered = false;
  final BootTrace _bootTrace = BootTrace('ui');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _services?.settings.updateSystemLocale(locale);
  }

  Future<void> _boot() async {
    final preview = UserStore.previewSettings();
    _bootTrace.mark('start');
    setState(() {
      _loading = true;
      _error = null;
      _services = null;
    });
    try {
      final loader = widget.bootLoader ?? AppBootstrap.load;
      final servicesFuture = loader();
      final savedSettings = await preview;
      if (mounted && savedSettings != null) {
        setState(() {
          _bootLanguage = savedSettings.locale == 'zh'
              ? TextLang.zh
              : savedSettings.locale == 'en'
              ? TextLang.en
              : null;
        });
      }
      final services = await servicesFuture;
      _bootTrace.mark('services');
      if (!mounted) return;
      setState(() {
        _services = services;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bootTrace.mark('first-frame');
        _bootTrace.dump();
      });
      debugThemeHook = (value) => services.settings.setTheme(value);
      debugStateHook = () =>
          '{"theme":"${services.settings.settings.theme}",'
          '"mode":"${services.settings.themeMode.name}",'
          '"locale":"${services.settings.language.name}",'
          '"scale":${services.settings.textScale}}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_debugBridgeRegistered) {
          _debugBridgeRegistered = true;
          registerDebugBridge(_navigatorKey);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _services == null) {
      return MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: BootScreen(
          error: _loading ? null : _error,
          onRetry: _boot,
          language: _bootLanguage,
        ),
      );
    }

    final services = _services!;
    final settings = services.settings;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        services.search.lang = settings.language;
        return AppScope(
          services: services,
          child: MaterialApp(
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => AppStrings(settings.language).appName,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            locale: settings.materialLocale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            scrollBehavior: const _AppScrollBehavior(),
            builder: (context, child) {
              final systemFactor =
                  MediaQuery.textScalerOf(context).scale(10) / 10.0;
              final factor = (systemFactor * settings.textScale).clamp(
                0.8,
                2.0,
              );
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(factor)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const AppShell(),
          ),
        );
      },
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}
