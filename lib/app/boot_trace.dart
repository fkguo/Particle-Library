import 'package:flutter/foundation.dart';

/// Startup timing marks.
///
/// Only active work is a [Stopwatch] read per mark; all printing is gated on
/// [kDebugMode] so release builds stay quiet. Use one trace for the whole boot
/// so phase durations can be compared across runs.
class BootTrace {
  BootTrace([this.label = 'boot']);

  /// Debug builds always trace. Release builds can opt in with
  /// `--dart-define=PDG_BOOT_TRACE=true` when a startup measurement is needed.
  static const bool _releaseTrace = bool.fromEnvironment('PDG_BOOT_TRACE');

  static bool get enabled => kDebugMode || _releaseTrace;

  final String label;
  final Stopwatch _watch = Stopwatch()..start();
  final List<String> _marks = <String>[];

  int get elapsedMs => _watch.elapsedMilliseconds;

  void mark(String name) {
    final ms = _watch.elapsedMilliseconds;
    _marks.add('$name=${_delta(ms)}');
    if (enabled) debugPrint('TRACE $label $name ${ms}ms');
  }

  /// Seconds since the previous mark, in milliseconds.
  int _last = 0;
  String _delta(int ms) {
    final delta = ms - _last;
    _last = ms;
    return '+${delta}ms';
  }

  void dump() {
    if (!enabled) return;
    debugPrint('TRACE $label ${_marks.join(' ')} total=${elapsedMs}ms');
  }
}
