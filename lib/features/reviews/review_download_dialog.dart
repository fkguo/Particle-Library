import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_strings.dart';

/// One download progress sample.  `total` is null when the server sends no
/// Content-Length; the dialog then shows an indeterminate bar.
@immutable
class ReviewDownloadProgress {
  const ReviewDownloadProgress({required this.received, this.total});

  final int received;
  final int? total;

  double? get fraction {
    final size = total;
    if (size == null || size <= 0) return null;
    return (received / size).clamp(0.0, 1.0).toDouble();
  }
}

/// Modal progress for a review opened from search.
///
/// A SnackBar is deliberately not used here: its default timeout is shorter
/// than a slow download, so the "downloading" message would disappear while
/// the download is still running.
class ReviewDownloadDialog extends StatelessWidget {
  const ReviewDownloadDialog({
    super.key,
    required this.title,
    required this.progress,
    required this.strings,
  });

  final String title;
  final ValueListenable<ReviewDownloadProgress> progress;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(strings.searchReviewDownloading),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<ReviewDownloadProgress>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final fraction = value.fraction;
                  final status = fraction == null
                      ? (value.received == 0
                            ? strings.searchReviewPreparing
                            : strings.searchReviewReceived(
                                _formatBytes(value.received),
                              ))
                      : '${(fraction * 100).round()}% · '
                            '${_formatBytes(value.received)} / '
                            '${_formatBytes(value.total!)}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: fraction, minHeight: 6),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: palette.onSurfaceVariant),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                strings.searchReviewDownloadHint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: palette.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
