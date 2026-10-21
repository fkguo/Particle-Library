import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import '../domain/labels.dart';
import '../features/common/async_view.dart';
import '../features/common/page.dart';

class BootScreen extends StatelessWidget {
  const BootScreen({
    super.key,
    this.error,
    required this.onRetry,
    this.language,
  });

  final Object? error;
  final VoidCallback onRetry;
  final TextLang? language;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lang =
        language ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh'
            ? TextLang.zh
            : TextLang.en);
    final strings = AppStrings(lang);
    final localized = language != null;
    return Scaffold(
      backgroundColor: palette.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 56),
                const SizedBox(height: Insets.l),
                Text(
                  kAppName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                if (localized) ...[
                  const SizedBox(height: 4),
                  Text(
                    strings.appTagline,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: Insets.xl),
                if (error == null)
                  if (localized)
                    LoadingPanel(message: strings.bootLoading)
                  else
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                else
                  ErrorPanel(error: error!, onRetry: onRetry, strings: strings),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
