import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../data/database/database.dart';
import '../data/database/sync_interceptor.dart';
import 'client_write_interceptor.dart';

// ── Module parts ─────────────────────────────────────────────────────────
part 'logging/log_sales.dart';
part 'logging/log_users.dart';
part 'logging/log_inventory.dart';
part 'logging/log_financial.dart';
part 'logging/log_parties.dart';
part 'logging/log_operations.dart';
part 'logging/log_system.dart';

/// Centralized service for recording forensic activity logs.
/// These logs are critical for auditing sensitive actions in the system.
///
/// The core class provides the generic [log] method. All domain-specific
/// convenience methods live in extensions inside the `logging/` folder:
///
///  • [ActivityLoggerSales]      — POS, void, discount, return, shift
///  • [ActivityLoggerUsers]      — login, logout, roles, permissions
///  • [ActivityLoggerInventory]  — products, stock, categories, PLU
///  • [ActivityLoggerFinancial]  — treasury, journal entries, fiscal year
///  • [ActivityLoggerParties]    — customers, suppliers, unified parties
///  • [ActivityLoggerOperations] — offers, delivery, HR, e-invoice, …
///  • [ActivityLoggerSystem]     — navigation, import/export, reports, backup
class ActivityLogger {
  final AppDatabase _db;

  ActivityLogger(this._db);

  // ─── Feature 010 / Cluster C — server-push cooldown ────────────────────
  //
  // Field-collected diagnostic logs from a beta restaurant showed activity-
  // log pushes hammering the server: every keystroke / cart action / nav
  // event fires `unawaited(pushActivityLog(...))`. Each push is its own HTTP
  // request, and each gets counted against the server's per-IP rate limiter
  // (api_rate_limiter.dart — 120 req / 60s per IP). The bucket is exhausted
  // in seconds, then EVERY write (sales, purchases, settings, shifts) gets
  // 429'd for the next minute. The downstream effect: a purchase invoice
  // never reaches the server, then the user processes a return on it, and
  // the server returns 404 because it can't find the parent invoice.
  //
  // Fix: when a push gets 429'd, remember the cooldown the server told us
  // (`retryAfterSeconds`) and skip activity-log pushes until it expires.
  // The local audit row is always persisted regardless, so forensics on
  // the device are intact; only the central-server mirror of audit data
  // loses entries from the burst window. Business writes get their
  // bucket headroom back.
  //
  // Successful pushes clear the cooldown early (server may have recovered).
  static DateTime? _serverPushCooldownUntil;

  /// Parse a server error message and return the requested cooldown if it
  /// looks like a 429 rate-limit response. Returns null for any other
  /// error (network, 5xx, etc.) — those should NOT trigger a cooldown
  /// since they are not back-pressure signals.
  ///
  /// Recognized shapes (matching api_rate_limiter.dart:121):
  ///   `Server error (429): {"error":"Too many requests","retryAfterSeconds":60}`
  @visibleForTesting
  static Duration? parseRateLimitCooldown(String errorMessage) {
    if (!errorMessage.contains('429') &&
        !errorMessage.contains('Too many requests')) {
      return null;
    }
    final match = RegExp(r'retryAfterSeconds["\s:]+(\d+)')
        .firstMatch(errorMessage);
    final secs = int.tryParse(match?.group(1) ?? '') ?? 60;
    return Duration(seconds: secs);
  }

  /// True if a prior push hit a 429 and we are still inside the
  /// server-requested cooldown window.
  @visibleForTesting
  static bool get isInPushCooldown {
    final until = _serverPushCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Reset cooldown state — for tests only.
  @visibleForTesting
  static void resetPushCooldownForTest() {
    _serverPushCooldownUntil = null;
  }

  /// Push the log to the server while respecting any active 429 cooldown.
  /// On a successful push, clears the cooldown early.
  static Future<void> _pushRespectingCooldown(
      Map<String, dynamic> payload) async {
    try {
      await ClientWriteInterceptor.pushActivityLog(payload);
      // Server accepted — clear any stale cooldown so subsequent logs
      // resume normal push behavior immediately.
      _serverPushCooldownUntil = null;
    } catch (e) {
      final cooldown = parseRateLimitCooldown(e.toString());
      if (cooldown != null) {
        // Pad the server-requested cooldown by 5s to avoid races at the
        // window boundary (server clock vs client clock can drift).
        _serverPushCooldownUntil =
            DateTime.now().add(cooldown + const Duration(seconds: 5));
        debugPrint(
            '[ActivityLogger] server 429 — pausing pushes until '
            '$_serverPushCooldownUntil');
      }
      // Non-rate-limit errors are swallowed (audit row is local-only).
    }
  }

  /// Log an activity to the database
  Future<void> log({
    required int? userId,
    required String userName,
    required String action,
    required String entityType,
    int? entityId,
    required String description,
    String? oldValue,
    String? newValue,
    double? amount,
    String? ipAddress,
    String? deviceInfo,
  }) async {
    try {
      final gid = const Uuid().v7();
      final now = DateTime.now();
      await _db
          .into(_db.activityLogs)
          .insert(
            ActivityLogsCompanion.insert(
              userId: Value(userId),
              userName: userName,
              action: action,
              entityType: entityType,
              entityId: Value(entityId),
              description: description,
              oldValue: Value(oldValue),
              newValue: Value(newValue),
              amount: Value(amount),
              ipAddress: Value(ipAddress),
              deviceInfo: Value(deviceInfo),
              createdAt: Value(now),
              globalId: Value(gid),
              lastModifiedAt: Value(now),
            ),
          );

      // In client mode push the log to the server so it appears in the
      // central activity log — non-blocking, with a 429 cooldown so a
      // burst of activity does not exhaust the per-IP rate-limit bucket
      // and starve real business writes (sales/purchases). See
      // _serverPushCooldownUntil docs above.
      if (SyncInterceptor.isClientMode && !isInPushCooldown) {
        unawaited(
          _pushRespectingCooldown({
            'globalId': gid,
            'userId': userId,
            'userName': userName,
            'action': action,
            'entityType': entityType,
            'entityId': entityId,
            'description': description,
            'oldValue': oldValue,
            'newValue': newValue,
            'amount': amount,
            'deviceInfo': deviceInfo,
            'createdAt': now.toIso8601String(),
          }),
        );
      }
    } catch (e) {
      // We don't want logging failures to crash the main app flow
      // but we should log them to the console.
      debugPrint('[ActivityLogger] Error recording log: $e');
    }
  }
}
