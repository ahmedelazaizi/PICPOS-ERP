// CRUD API endpoints extracted from ApiHandler (PIR C-01).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import 'package:drift/drift.dart';
import '../../core/auth/bootstrap_admin.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';
import 'm1_wh/wh_error_classifier.dart' show isUniqueViolation;
import '../../domain/models/attachment_policy.dart';
import '../../domain/models/floor_plan_layout.dart';
import '../cheque_receipt_jes.dart';
import '../sync/strategies/setting_sync_strategy.dart'
    show isDeviceLocalSettingKey, isServerSecretSettingKey;
import 'api_user_context.dart';
import 'web_session_guard.dart';
import '../../domain/entities/accounting_entities.dart';
import 'api_handler_base.dart';
import 'api_voucher_handler.dart' show resolveClientAccountId;
import '../../core/config/brand.dart';

part 'data/api_data_expenses.dart';
part 'data/api_data_operations.dart';
part 'data/api_data_cash.dart';
part 'data/api_data_inventory.dart';
part 'data/api_data_users_roles.dart';
part 'data/api_data_org_structure.dart';
part 'data/api_data_accounting.dart';
part 'data/api_data_treasury.dart';
part 'data/api_data_commercial_papers.dart';
part 'data/api_data_documents.dart';
part 'data/api_data_system.dart';
part 'data/api_data_attachments.dart';

/// Handles all data CRUD API endpoints (non-sales, non-display).
class ApiDataHandler extends ApiHandlerBase {
  ApiDataHandler(super.db, super.wsClients);

  // ═══════════════════════════════════════════════════════════════
  // FK Resolution Helpers (Client SQLite IDs → Server PostgreSQL IDs)
  // ═══════════════════════════════════════════════════════════════

  /// Resolve a client-provided warehouseId to a valid server warehouseId.
  Future<int> _resolveWarehouseId(int clientWarehouseId,
      {int? branchId, String? warehouseGlobalId}) async {
    // Spec 136 ISS-26 (#2 hardening / Spec 132) — resolve by globalId FIRST
    // when the caller threads it, so a mirror/client whose local warehouse ids
    // diverge from the server still routes the stock movement to the CORRECT
    // server warehouse (instead of a "Strict Mapping Violation" or landing in
    // the wrong warehouse). Falls back to the raw-id lookup for legacy callers.
    Warehouse? existing;
    if (warehouseGlobalId != null && warehouseGlobalId.isNotEmpty) {
      existing = await (db.select(db.warehouses)
            ..where((w) => w.globalId.equals(warehouseGlobalId))
            ..limit(1))
          .getSingleOrNull();
    }
    existing ??= await (db.select(db.warehouses)
          ..where((w) => w.id.equals(clientWarehouseId)))
        .getSingleOrNull();
    if (existing == null) {
      throw Exception(
          'Strict Mapping Violation: Warehouse ID $clientWarehouseId '
          '(globalId=$warehouseGlobalId) not found on server.');
    }
    // L4 (2026-04-28): Authorization check — when client declares its branch,
    // ensure the warehouse belongs to that branch (prevents cross-branch ops).
    if (branchId != null && existing.branchId != null && existing.branchId != branchId) {
      throw Exception(
        'Authorization Error: warehouse ${existing.id} belongs to branch '
        '${existing.branchId} but client declared branch $branchId. '
        'Cross-branch operation denied.',
      );
    }
    return existing.id;
  }

  /// Resolve a client-provided userId to a valid server userId.
  /// Primary: exact ID match. Fallback: username lookup (handles client/server
  /// auto-increment divergence when user was created in client mode).
  /// Resolve client-provided user ID to server-side ID with admin fallback.
  /// See `api_sales_handler.dart::_resolveUserId` for the full rationale —
  /// the short version: NEVER throw, always preserve the incoming record by
  /// attributing to admin as a last resort.
  Future<int> _resolveUserId(int clientUserId, {String? fallbackUsername}) async {
    final existing = await (db.select(db.users)
          ..where((u) => u.id.equals(clientUserId)))
        .getSingleOrNull();
    if (existing != null) return clientUserId;

    if (fallbackUsername != null && fallbackUsername.isNotEmpty) {
      final byUsername = await (db.select(db.users)
            ..where((u) => u.username.equals(fallbackUsername)))
          .getSingleOrNull();
      if (byUsername != null) {
        debugPrint('[API] _resolveUserId: ID $clientUserId not found — '
            'fell back to username "$fallbackUsername" → server ID ${byUsername.id}');
        return byUsername.id;
      }
    }

    final admin = await (db.select(db.users)
          ..where((u) => u.username.equals('admin') & u.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (admin != null) {
      debugPrint('[API] ⚠ _resolveUserId: clientUserId=$clientUserId '
          '(username="$fallbackUsername") not found — attributing to admin '
          '(id=${admin.id}) to preserve data');
      // ⚠️ أثرٌ **باقٍ** لا `debugPrint` وحدَه: هذا السطرُ يجعل سجلّاً يُنسب
      // إلى مديرِ النظام بدل صاحبِه، فيصير رقمٌ في «المبيعات حسب الكاشير»
      // كاذباً بلا أن يعلم أحد. و`debugPrint` يختفي في الإصدار — فبلاغُ
      // المالك «التقريرُ غيرُ دقيق» كان بلا أيّ أثرٍ يُقاس عليه.
      // (‏مقيسٌ في `test/unit/user_attribution_fallback_visible_test.dart`.)
      unawaited(DiagnosticLogger.log(
          'USER-ATTRIBUTION',
          '⚠ سجلٌّ أُسنِد إلى admin(id=${admin.id}) لأن '
          'clientUserId=$clientUserId username="$fallbackUsername" '
          'غيرُ موجودٍ على السيرفر — تقاريرُ «حسب المستخدم» ستنسبه للمدير'));
      return admin.id;
    }

    throw Exception('No valid user on server — cannot persist record. '
        'clientUserId=$clientUserId fallbackUsername=$fallbackUsername');
  }

  /// Resolve a nullable userId — returns null if input is null.
  Future<int?> _resolveUserIdNullable(int? clientUserId, {String? fallbackUsername}) async {
    if (clientUserId == null) return null;
    return _resolveUserId(clientUserId, fallbackUsername: fallbackUsername);
  }

}
