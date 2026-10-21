import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_strings.dart';
import '../../app/app_theme.dart';
import '../../app/error_text.dart';
import '../../core/errors.dart';
import 'ui.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = AppScope.maybeOf(context)?.strings;
    return Padding(
      padding: EdgeInsets.all(compact ? Insets.l : Insets.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: Insets.m),
          Text(
            message ?? strings?.commonLoading ?? 'Loading…',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
    this.strings,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;
  final AppStrings? strings;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final strings = this.strings ?? AppScope.maybeOf(context)?.strings;
    final exception = error is AppException ? error as AppException : null;
    final message = strings == null
        ? error.toString()
        : errorText(error, strings);
    final detail = strings == null
        ? exception?.detail
        : errorDetailText(error, strings);
    final code = exception?.code ?? AppErrorCode.queryFailed;
    final title = switch (code) {
      AppErrorCode.snapshotMissing =>
        strings?.bootFailed ?? 'Data file missing',
      AppErrorCode.snapshotMismatch =>
        strings?.bootFailed ?? 'Data file mismatch',
      AppErrorCode.unsupportedSchema =>
        strings?.bootFailed ?? 'Unsupported database schema',
      AppErrorCode.corruptDatabase =>
        strings?.bootFailed ?? 'Database is corrupt',
      AppErrorCode.notFound => strings?.commonNotRecorded ?? 'Not found',
      AppErrorCode.invalidInput => strings?.commonError ?? 'Invalid input',
      AppErrorCode.ambiguous => strings?.commonError ?? 'Ambiguous result',
      AppErrorCode.storageUnavailable =>
        strings?.bootFailed ?? 'Storage unavailable',
      AppErrorCode.queryFailed => strings?.commonError ?? 'Query failed',
    };
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? Insets.l : Insets.xl),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: palette.error, size: 20),
              const SizedBox(width: Insets.s),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MetaChip(code.wireName, tone: BadgeTone.error),
            ],
          ),
          const SizedBox(height: Insets.s),
          SelectableText(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: palette.textPrimary),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: Insets.s),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                strings?.bootDetails ?? 'Details',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              children: [
                SelectableText(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    fontFamily: 'Menlo',
                  ),
                ),
              ],
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: Insets.s),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(strings?.commonRetry ?? 'Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.loading,
    this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T value) builder;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.future;
  }

  @override
  void didUpdateWidget(covariant AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.future, widget.future)) {
      _future = widget.future;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loading ?? const Center(child: LoadingPanel());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: ErrorPanel(
                error: snapshot.error!,
                onRetry: widget.onRetry,
              ),
            ),
          );
        }
        final value = snapshot.data;
        if (value == null) {
          return Center(
            child: EmptyPanel(
              message: AppScope.of(context).strings.commonNoData,
            ),
          );
        }
        return widget.builder(context, value);
      },
    );
  }
}
