// ═══════════════════════════════════════════════════════════════════════════
// AUDIT LOG — severity-aware wrapper over ActivityLogger
// ═══════════════════════════════════════════════════════════════════════════
//
// Thin facade that adds:
//   1. Severity levels (info / warning / critical).
//   2. A structured `payload` map that is JSON-stringified into the
//      existing `new_value` column of the activity_logs table.
//   3. Global static accessor — so safe-mode / startup / ConfigService
//      can emit audit entries before the widget tree (and hence Riverpod
//      providers) is alive.
//
// It does NOT add a new table. The `activity_logs` table already powers
// the audit-trail UI; we reuse it to avoid yet-another-table sprawl.
//
// Usage:
//   await AuditLog.configure(activityLogger); // once, from main.dart
//   AuditLog.record('profile_changed',
//     level: AuditLevel.critical,
//     payload: {'from': 'retail', 'to': 'restaurant'});
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'activity_logger.dart';

/// Severity of an audit event. Used by the UI to filter/highlight and
/// by downstream collectors (if we ever wire one up) to decide what
/// level of alerting to apply.
enum AuditLevel { info, warning, critical }

extension AuditLevelX on AuditLevel {
  String get label {
    switch (this) {
      case AuditLevel.info:     return 'info';
      case AuditLevel.warning:  return 'warning';
      case AuditLevel.critical: return 'critical';
    }
  }
}

class AuditLog {
  static ActivityLogger? _logger;

  /// Wire the service to a live `ActivityLogger`. Called once from
  /// `main.dart` after the DB is open. Before this runs, `record()`
  /// swallows events to `debugPrint` so early-boot errors don't crash.
  static void configure(ActivityLogger logger) {
    _logger = logger;
  }

  /// Records an audit event. Non-throwing by design — audit failures
  /// must never take down the operation being audited. Errors land in
  /// `debugPrint` only.
  ///
  /// [userId] / [userName] are optional; pass them when the call site
  /// has access to the auth state. For system-level events (safe-mode,
  /// startup, scheduled jobs) leave them `null` / `'SYSTEM'`.
  static Future<void> record(
    String event, {
    required AuditLevel level,
    Map<String, dynamic>? payload,
    int? userId,
    String userName = 'SYSTEM',
    String entityType = 'system',
    int? entityId,
  }) async {
    final logger = _logger;
    // Fire-and-forget the debug stream so we still see events during
    // development / crash reports even before configure() ran.
    debugPrint('[AUDIT][${level.label}] $event '
        '${payload == null ? '' : jsonEncode(payload)}');
    if (logger == null) return;
    try {
      await logger.log(
        userId: userId,
        userName: userName,
        action: event,
        entityType: entityType,
        entityId: entityId,
        description: _describe(event, level, payload),
        // Encode the structured payload into `newValue` so the existing
        // audit-trail UI can show it as-is without a schema change.
        newValue: payload == null ? null : jsonEncode({
          'level': level.label,
          'payload': payload,
        }),
      );
    } catch (e, st) {
      debugPrint('[AUDIT] record failed: $e\n$st');
    }
  }

  static String _describe(
      String event, AuditLevel level, Map<String, dynamic>? payload) {
    final prefix = switch (level) {
      AuditLevel.critical => '[حرج]',
      AuditLevel.warning  => '[تحذير]',
      AuditLevel.info     => '[معلومة]',
    };
    if (payload == null || payload.isEmpty) return '$prefix $event';
    // Show a short, Arabic-friendly key-value summary for the description
    // column. Full JSON is in `newValue` for forensic inspection.
    final summary = payload.entries
        .take(3)
        .map((e) => '${e.key}=${e.value}')
        .join('، ');
    return '$prefix $event — $summary';
  }
}
