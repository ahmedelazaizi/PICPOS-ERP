// Spec 029 / US4 — Lightweight perf-trace helper.
//
// Emits `[PERF] <screen> <event>: <ms>ms` lines when [kPerfDebug] is
// true. Off in release builds (kPerfDebug is `const false` for
// production; flip to `true` locally to run an audit per
// quickstart.md §US4).
//
// Used by:
//   - lib/presentation/products/products.dart                 first-paint
//   - lib/presentation/screens/inventory/inventory.dart        first-paint
//   - lib/presentation/products/providers/products_controller.dart
//                                                              search-query counter
//   - SchedulerBinding.addTimingsCallback                      frame-over-budget
//
// The intent is verification, not always-on instrumentation. Cluster
// 023/024/027 already shipped the perf wins; US4's job is to confirm
// they hold on real beta data and document the numbers in
// `specs/029-sync-regression-hardening/perf-audit.md`.

import 'dart:async' show unawaited;
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';

import '../logging/diagnostic_logger.dart';

/// Spec 032 v3 diagnostic — route PERF emissions through both
/// `debugPrint` (visible only when running under `flutter run`) AND
/// `DiagnosticLogger.log` (writes to `Documents/uralcash_login_log.txt`,
/// which is the only output channel visible on a Windows release build
/// that doesn't attach a console). The file write is fire-and-forget so
/// it doesn't block the frame.
void _emit(String message) {
  debugPrint('[PERF] $message');
  unawaited(DiagnosticLogger.log('PERF', message));
}

/// Master kill-switch. Compile-time `const false` in release; flip to
/// `true` locally when running the audit. The compiler tree-shakes
/// every `if (kPerfDebug) { ... }` block when this is false, so the
/// instrumentation has zero runtime cost in production.
///
/// Spec 032 v3 diagnostic — was TEMPORARILY flipped to `true` to capture a
/// products / inventory scroll trace on a real POS device. Restored to
/// `false` (Spec 136, 2026-06-04): it had been left on, and the per-frame
/// `DiagnosticLogger.log` file write on every >16ms frame was itself the
/// cause of the field-reported severe lag ("تقل شديد جدا"). The compiler
/// tree-shakes every `if (kPerfDebug)` block when this is false → zero cost.
const bool kPerfDebug = false;

/// Lightweight rebuild counter — emits one debugPrint per N rebuilds
/// of a given widget. Use sparingly during scroll instrumentation; the
/// flood of `debugPrint`s itself can degrade frame timings.
class PerfRebuildCounter {
  PerfRebuildCounter(this.label, {this.everyN = 10});
  final String label;
  final int everyN;
  int _n = 0;
  void tick() {
    if (!kPerfDebug) return;
    _n++;
    if (_n % everyN == 0 || _n <= 3) {
      _emit('$label rebuild #$_n');
    }
  }
}

/// Logs scroll position deltas with throttling so the console is
/// readable during a sustained drag. Emits at most one line every
/// [throttleMs] milliseconds.
class PerfScrollLogger {
  PerfScrollLogger(this.label, {this.throttleMs = 100});
  final String label;
  final int throttleMs;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  void log(double pixels, double maxExtent) {
    if (!kPerfDebug) return;
    final now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds < throttleMs) return;
    _lastEmit = now;
    _emit(
      '$label scroll: ${pixels.toStringAsFixed(0)} / '
      '${maxExtent.toStringAsFixed(0)}',
    );
  }
}

/// Single-shot first-paint timer. Construct in `initState`, call
/// [emit] inside the first post-frame callback. The `Stopwatch`
/// starts at construction; [emit] stops it and prints the elapsed
/// milliseconds.
class PerfFirstPaint {
  PerfFirstPaint(this.screen) : _stopwatch = Stopwatch()..start();

  final String screen;
  final Stopwatch _stopwatch;
  bool _emitted = false;

  /// Print the first-paint duration. Idempotent — subsequent calls
  /// are no-ops. Safe to call from `addPostFrameCallback`.
  void emit() {
    if (!kPerfDebug || _emitted) return;
    _emitted = true;
    _stopwatch.stop();
    _emit('$screen first-paint: ${_stopwatch.elapsedMilliseconds}ms');
  }
}

/// Counter for debounced query bursts. Increment in the controller's
/// query method; periodically [flush] the count and reset.
class PerfQueryCounter {
  PerfQueryCounter(this.screen);

  final String screen;
  int _count = 0;
  DateTime _windowStart = DateTime.now();

  void inc() {
    if (!kPerfDebug) return;
    _count++;
    final age = DateTime.now().difference(_windowStart);
    // Auto-flush every second; gives the audit recipe a per-second
    // sample without requiring the test driver to call [flush]
    // explicitly.
    if (age >= const Duration(seconds: 1)) {
      flush();
    }
  }

  void flush() {
    if (!kPerfDebug) return;
    if (_count > 0) {
      debugPrint('[PERF] $screen search-query x$_count');
    }
    _count = 0;
    _windowStart = DateTime.now();
  }
}

/// Helper to plug into `SchedulerBinding.instance.addTimingsCallback`.
/// Only emits a line when a frame's total budget exceeds [budgetMs] —
/// keeps the log readable on a smooth scroll session.
void perfReportFrameOverBudget(
  String screen,
  Iterable<FrameTiming> timings, {
  int budgetMs = 16,
}) {
  if (!kPerfDebug) return;
  for (final t in timings) {
    final totalMs = t.totalSpan.inMicroseconds / 1000;
    if (totalMs > budgetMs) {
      _emit(
        '$screen frame-over-budget: '
        '${totalMs.toStringAsFixed(1)}ms (build ${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)}ms / '
        'raster ${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)}ms)',
      );
    }
  }
}
