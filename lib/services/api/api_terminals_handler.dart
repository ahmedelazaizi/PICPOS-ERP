// ═══════════════════════════════════════════════════════════════════════════
// API TERMINALS HANDLER — POS terminal registration (Feature 009 / T020)
// ═══════════════════════════════════════════════════════════════════════════
//
// Owns the server side of the per-terminal infrastructure introduced in
// Feature 009 / Phase 2. The companion service on the client is
// `lib/services/pos_terminal_registration_service.dart`, which calls
// POST /api/pos-terminals/register exactly once per device on the first
// successful boot (and again after a `wipeSeededMasterDataForClient` flow).
//
// The endpoint is idempotent on `deviceId`:
//   • If a `pos_terminals` row already exists for this device, return it.
//   • Otherwise insert a fresh row, mint a UUIDv7 `globalId`, and return it.
//
// `branchId` is non-null on the table, but the client doesn't know which
// branch it belongs to at first boot (branch assignment is an admin act).
// We default to the first active branch ordered by id, matching how
// shifts / warehouses fall back when no branch is supplied. The admin UI
// (T028b in US2) lets the operator move the terminal afterwards.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';
import 'api_handler_base.dart';

class ApiTerminalsHandler extends ApiHandlerBase {
  ApiTerminalsHandler(super.db, super.wsClients);

  /// POST /api/pos-terminals/register
  ///
  /// Request body:
  /// ```
  ///   {
  ///     "deviceId":  "[uuid]",        required — UUIDv7 from secure storage
  ///     "name":      "[display]",     optional — defaults to hostname
  ///     "hostname":  "[os hostname]", optional
  ///     "platform":  "[os name]"      optional, informational only
  ///   }
  /// ```
  ///
  /// Response: `{ "id": [int], "globalId": "[uuid]", "duplicate": [bool] }`.
  ///
  /// Idempotency: keyed on `deviceId` (also via the standard
  /// `Idempotency-Key` middleware below). A retried registration always
  /// returns the same `id` regardless of the path that hit it.
  // EXEMPT-PER-USER: terminal pairing happens BEFORE first login on the
  // new device. (Spec 077 Batch 5 allow-list — see §6 of endpoint-permission-map.md)
  Future<Response> register(Request request) async {
    try {
      final raw = await request.readAsString();
      final data = json.decode(raw) as Map<String, dynamic>;

      final deviceId = (data['deviceId'] as String?)?.trim() ?? '';
      if (deviceId.isEmpty) {
        return errorResponse(
          'Validation Error: deviceId is required',
          statusCode: 400,
        );
      }

      // Idempotency middleware support — the client sends
      // `idempotencyKey: deviceId` via ServerProxy. If we've already served
      // this exact key, replay the stored response.
      final idempotencyKey = request.headers['idempotency-key'] ??
          request.headers['Idempotency-Key'];
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        final cached = await checkIdempotency(idempotencyKey);
        if (cached != null) {
          debugPrint('[API] /pos-terminals/register: idempotent replay '
              'key=$idempotencyKey');
          return jsonResponse(cached);
        }
      }

      // 1. Existing row by deviceId — first-class idempotency.
      final existing = await (db.select(db.posTerminals)
            ..where((t) => t.deviceId.equals(deviceId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        final body = {
          'success': true,
          'duplicate': true,
          'id': existing.id,
          'globalId': existing.globalId ?? '',
          'name': existing.name,
          'branchId': existing.branchId,
          'message': 'Terminal already registered',
        };
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
          await storeIdempotency(
            idempotencyKey,
            body,
            actionType: 'register_pos_terminal_duplicate',
          );
        }
        await DiagnosticLogger.log(
          'API-POS-TERMINAL',
          '✓ duplicate registration deviceId=$deviceId → id=${existing.id}',
        );
        return jsonResponse(body);
      }

      // 2. Fresh registration. Resolve a default branch — the lowest-id
      //    active branch — so the FK is satisfied. Admins can move the
      //    terminal later via the management screen (T028b in US2).
      final defaultBranch = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true))
            ..orderBy([(b) => drift.OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingleOrNull();
      if (defaultBranch == null) {
        return errorResponse(
          'No active branch on the server — cannot register a terminal '
          'until at least one branch exists.',
          statusCode: 409,
        );
      }

      final hostname = (data['hostname'] as String?)?.trim();
      final providedName = (data['name'] as String?)?.trim();
      final resolvedName = (providedName != null && providedName.isNotEmpty)
          ? providedName
          : (hostname != null && hostname.isNotEmpty
              ? hostname
              : 'POS-${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}');

      final newGlobalId = UuidV7.generate();
      final newId = await db.into(db.posTerminals).insert(
            PosTerminalsCompanion.insert(
              name: resolvedName,
              deviceId: deviceId,
              branchId: defaultBranch.id,
              globalId: drift.Value(newGlobalId),
            ),
          );

      final body = {
        'success': true,
        'duplicate': false,
        'id': newId,
        'globalId': newGlobalId,
        'name': resolvedName,
        'branchId': defaultBranch.id,
        'message': 'Terminal registered',
      };
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        await storeIdempotency(
          idempotencyKey,
          body,
          actionType: 'register_pos_terminal',
        );
      }
      await DiagnosticLogger.log(
        'API-POS-TERMINAL',
        '✓ registered deviceId=$deviceId → id=$newId branch=${defaultBranch.id} '
        'name=$resolvedName',
      );

      // The new row will reach paired clients via PosTerminalSyncStrategy
      // (T012c) on their next pull.
      broadcast('pos_terminals');
      db.markTablesUpdated({db.posTerminals});

      return jsonResponse(body);
    } catch (e, st) {
      debugPrint('[API] /pos-terminals/register error: $e\n$st');
      await DiagnosticLogger.log(
        'API-POS-TERMINAL',
        '❌ registration error: $e',
      );
      return ApiErrors.fail(e, 'Failed to register terminal');
    }
  }
}
