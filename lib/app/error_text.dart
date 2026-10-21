import '../core/errors.dart';
import '../domain/labels.dart';
import '../notes/notes_exception.dart';
import 'app_strings.dart';

final RegExp _cjk = RegExp(r'[\u3400-\u9fff]');

bool _hasCjk(String value) => _cjk.hasMatch(value);

/// Localizes known data-layer errors instead of leaking a Chinese exception
/// message into the English UI. Unknown technical errors fall back to a
/// generic localized message when they contain CJK text.
String errorText(Object error, AppStrings strings) {
  if (strings.lang != TextLang.en) return error.toString();
  if (error is AppException) {
    switch (error.code) {
      case AppErrorCode.notFound:
        final entry = RegExp(r'当前快照未收录条目 (.+?)。').firstMatch(error.message);
        if (entry != null) {
          return strings.errorEntryNotInSnapshot(entry.group(1)!);
        }
        final reference = RegExp(r'当前快照未收录文献记录 (.+?)。')
            .firstMatch(error.message);
        if (reference != null) {
          return strings.errorReferenceNotInSnapshot(reference.group(1)!);
        }
        return strings.commonNotRecorded;
      case AppErrorCode.invalidInput:
        return strings.errorInvalidInput;
      case AppErrorCode.snapshotMissing:
      case AppErrorCode.snapshotMismatch:
      case AppErrorCode.unsupportedSchema:
      case AppErrorCode.corruptDatabase:
        return strings.bootFailed;
      case AppErrorCode.storageUnavailable:
        return strings.errorNotesUnavailable;
      case AppErrorCode.queryFailed:
      case AppErrorCode.ambiguous:
        return strings.commonError;
    }
  }
  if (error is NotesException) {
    return switch (error.code) {
      NotesErrorCode.unavailable => strings.errorNotesUnavailable,
      NotesErrorCode.corrupt => strings.errorNotesCorrupt,
      NotesErrorCode.unsupportedSchema => strings.errorNotesCorrupt,
      NotesErrorCode.invalidInput => strings.errorInvalidInput,
      NotesErrorCode.notFound => strings.errorNoteMissing,
      NotesErrorCode.conflict => strings.errorNotesConflict,
      NotesErrorCode.writeFailed => strings.errorNotesWriteFailed,
      NotesErrorCode.backupFailed => strings.errorNotesBackupFailed,
    };
  }
  if (error is FormatException) {
    final message = error.message;
    if (message.contains('缺少 backup.json')) {
      return strings.errorBackupMissing;
    }
    if (message.contains('备份 JSON 无效')) {
      return strings.errorBackupInvalid;
    }
    if (message.contains('不支持的完整备份版本')) {
      return strings.errorBackupVersion;
    }
    if (message.contains('笔记 JSON 数组')) {
      return strings.errorImportNotArray;
    }
    if (_hasCjk(message)) return strings.errorGeneric;
    return message;
  }
  final text = error.toString();
  if (_hasCjk(text)) return strings.errorGeneric;
  return text;
}

/// Detail is useful in Chinese, but an English UI must not expose a raw
/// Chinese exception detail. Technical details without CJK remain visible.
String? errorDetailText(Object error, AppStrings strings) {
  if (strings.lang != TextLang.en) return error.toString();
  if (error is AppException) {
    final detail = error.detail;
    if (detail == null || detail.isEmpty) return null;
    return _hasCjk(detail) ? null : detail;
  }
  if (error is NotesException) {
    final cause = error.cause;
    if (cause == null) return null;
    final text = cause.toString();
    return _hasCjk(text) ? null : text;
  }
  return null;
}
