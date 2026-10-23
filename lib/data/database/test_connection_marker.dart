import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Marks executors built by `openTestConnection()` (in-memory test DBs).
///
/// الإقلاع بيجدول المرحلة المؤجلة في الـ root zone عشان تشتغل على الاتصال
/// الحقيقي؛ قواعد الاختبار في الذاكرة لازم تفضل على `Future.microtask`
/// القديم (داخل fake-async بتاع الاختبار) وإلا الاختبار بيتعلّق.
final Expando<bool> _testExecutors = Expando<bool>('testExecutors');

/// Registers [executor] as an in-memory test executor and returns it.
QueryExecutor markTestExecutor(QueryExecutor executor) {
  _testExecutors[executor] = true;
  return executor;
}

/// Whether [executor] came from `openTestConnection()`.
bool isTestExecutor(QueryExecutor executor) => _testExecutors[executor] == true;

/// Runs the deferred startup phase. Real connections: root zone (a microtask
/// from beforeOpen inherits drift's closed zone -> 'Bad state: No element').
/// In-memory test DBs: plain microtask (root zone escapes fake-async, hangs).
/// An uncaught error in the root zone kills the process (e.g. the connection
/// closing mid-phase), so the job is wrapped and failures are only logged.
void scheduleDeferredPhase(QueryExecutor executor, Future<void> Function() job) {
  Future<void> safe() async {
    try {
      await job();
    } catch (e) {
      debugPrint('[Startup] deferred phase 6 aborted: $e');
    }
  }

  if (isTestExecutor(executor)) {
    Future.microtask(safe);
  } else {
    Zone.root.scheduleMicrotask(safe);
  }
}
