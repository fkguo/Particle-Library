import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdgapp/app/app_theme.dart';
import 'package:pdgapp/features/common/async_view.dart';
import 'package:pdgapp/app/app_strings.dart';
import 'package:pdgapp/app/error_text.dart';
import 'package:pdgapp/core/errors.dart';
import 'package:pdgapp/domain/labels.dart';
import 'package:pdgapp/notes/notes_exception.dart';

void main() {
  const en = AppStrings(TextLang.en);
  const zh = AppStrings(TextLang.zh);

  test('English translates snapshot not-found messages', () {
    final text = errorText(const NotFoundException('当前快照未收录条目 S041C。'), en);
    expect(text, 'This snapshot does not contain entry S041C.');
    expect(text, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
  });

  test('English translates notes conflicts and backup format errors', () {
    expect(
      errorText(
        const NotesException(NotesErrorCode.conflict, '笔记已被其他编辑更新，请重新载入后再保存。'),
        en,
      ),
      contains('changed by another editor'),
    );
    expect(
      errorText(const FormatException('备份中缺少 backup.json'), en),
      'The backup is missing backup.json.',
    );
  });

  test('unknown CJK errors fall back to a localized generic message', () {
    final text = errorText(Exception('无法连接 Crossref'), en);
    expect(text, en.errorGeneric);
    expect(text, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
  });

  test('Chinese UI keeps the original detail', () {
    const message = '当前快照未收录条目 S041C。';
    expect(errorText(const NotFoundException(message), zh), contains(message));
  });

  testWidgets(
    'ErrorPanel never shows the Chinese not-found message in English',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ErrorPanel(
              error: NotFoundException('当前快照未收录条目 S041C。'),
              strings: en,
            ),
          ),
        ),
      );
      expect(
        find.text('This snapshot does not contain entry S041C.'),
        findsOneWidget,
      );
      expect(find.textContaining('当前快照'), findsNothing);
      expect(find.text('Not in this snapshot'), findsOneWidget);
    },
  );

  test('English hides CJK details but keeps technical details', () {
    expect(
      errorDetailText(
        const AppException(
          AppErrorCode.queryFailed,
          '查询失败',
          detail: 'SQLite error 11',
        ),
        en,
      ),
      'SQLite error 11',
    );
    expect(
      errorDetailText(
        const AppException(
          AppErrorCode.queryFailed,
          '查询失败',
          detail: '数据库连接已关闭。',
        ),
        en,
      ),
      isNull,
    );
  });
}
