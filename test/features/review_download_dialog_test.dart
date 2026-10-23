import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/features/reviews/review_download_dialog.dart';

void main() {
  testWidgets('review download dialog keeps a visible progress bar', (
    tester,
  ) async {
    final progress = ValueNotifier<ReviewDownloadProgress>(
      const ReviewDownloadProgress(received: 0),
    );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewDownloadDialog(
            title: 'Plots of Cross Sections and Related Quantities',
            progress: progress,
            strings: const AppStrings(TextLang.zh),
          ),
        ),
      ),
    );

    expect(find.text('正在下载综述…'), findsOneWidget);
    expect(find.textContaining('正在连接'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    progress.value = const ReviewDownloadProgress(received: 512, total: 1024);
    await tester.pump();

    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('512 B'), findsOneWidget);
    expect(find.textContaining('1.0 KB'), findsOneWidget);

    progress.value = const ReviewDownloadProgress(received: 1536);
    await tester.pump();

    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(find.textContaining('1.5 KB'), findsOneWidget);
  });
}
