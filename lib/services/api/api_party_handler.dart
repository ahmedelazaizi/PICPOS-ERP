// ═══════════════════════════════════════════════════════════════════════════
// API PARTY HANDLER — CRUD for Parties (Customers / Suppliers)
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiDataHandler for maintainability (PIR C-01).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:drift/drift.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import 'api_user_context.dart';
import 'api_handler_base.dart';

/// Handles party (customer / supplier) CRUD API endpoints.
class ApiPartyHandler extends ApiHandlerBase {
  ApiPartyHandler(super.db, super.wsClients);

  /// Spec 077 Batch 2 — polymorphic permission resolver for party
  /// endpoints. Parties carry independent `isCustomer` / `isSupplier`
  /// boolean flags (a party can be both). The gate picks the more
  /// restrictive supplier-side perm whenever the supplier flag is on
  /// — creating a supplier record (even if the party is also a
  /// customer) is the structurally more privileged operation.
  ///
  /// `op` is one of `'add' | 'edit' | 'delete'`.
  String _partyPermissionFor(String op, {required bool isSupplier}) {
    switch (op) {
      case 'add':
        return isSupplier
            ? PermissionCodes.suppliersAdd
            : PermissionCodes.customersAdd;
      case 'edit':
        return isSupplier
            ? PermissionCodes.suppliersEdit
            : PermissionCodes.customersEdit;
      case 'delete':
        return isSupplier
            ? PermissionCodes.suppliersDelete
            : PermissionCodes.customersDelete;
      default:
        throw ArgumentError('Unknown party op: $op');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Parties (Customers / Suppliers)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postParty(Request request) async {
    try {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Spec 077 Batch 2 (Spec 060 Phase 2): polymorphic per-user gate.
      // Body MUST be parsed first so we can read isSupplier — gate auto-
      // passes when the settings flag is off, so the body re-use below
      // is safe (we never re-read the request stream).
      final perm = await ApiUserCtx.requirePermission(
        request,
        db,
        _partyPermissionFor('add',
            isSupplier: parseBool(data['isSupplier'], false)),
      );
      if (perm != null) return perm;

      // UUID-First idempotency (Phase 1): if the client supplied a globalId
      // and a party with that UUID already exists, return its id instead of
      // inserting again. Handles retry-after-network-blip and outbox replay.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.parties)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postParty: globalId=$incomingGlobalId already '
              'exists as serverId=${existing.id} — idempotent');
          return jsonResponse({'success': true, 'serverId': existing.id});
        }
      }
      // Honour a caller-supplied code so client + server stay aligned;
      // the DAO will auto-generate one if absent or empty.
      final clientCode = (data['code'] as String?)?.trim();

      // ── Natural-key fallback idempotency ──────────────────────────────
      // When the client's globalId doesn't match but a party with the same
      // code (or name+phone) already exists on the server, adopt the
      // incoming globalId onto that row rather than inserting a duplicate.
      // Mirrors the postProduct code/barcode fallback.
      Party? existingByNaturalKey;
      if (clientCode != null && clientCode.isNotEmpty) {
        existingByNaturalKey = await (db.select(db.parties)
              ..where((p) => p.code.equals(clientCode))
              ..limit(1))
            .getSingleOrNull();
      }
      if (existingByNaturalKey == null) {
        final incomingName = (data['name'] as String?)?.trim();
        final incomingPhone = (data['phone'] as String?)?.trim();
        if (incomingName != null && incomingName.isNotEmpty &&
            incomingPhone != null && incomingPhone.isNotEmpty) {
          existingByNaturalKey = await (db.select(db.parties)
                ..where((p) => p.name.equals(incomingName) & p.phone.equals(incomingPhone))
                ..limit(1))
              .getSingleOrNull();
        }
      }
      if (existingByNaturalKey != null) {
        if ((existingByNaturalKey.globalId == null || existingByNaturalKey.globalId!.isEmpty) &&
            incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
          await (db.update(db.parties)
                ..where((p) => p.id.equals(existingByNaturalKey!.id)))
              .write(PartiesCompanion(globalId: Value(incomingGlobalId)));
        }
        debugPrint('[API] postParty natural-key match: '
            'adopted incoming globalId onto serverId=${existingByNaturalKey.id} '
            '(code=$clientCode) — prevented duplicate insert.');
        return jsonResponse({'success': true, 'serverId': existingByNaturalKey.id});
      }

      final id = await db.insertParty(
        PartiesCompanion(
          globalId: (incomingGlobalId != null && incomingGlobalId.isNotEmpty)
              ? Value(incomingGlobalId)
              : const Value.absent(),
          code: (clientCode != null && clientCode.isNotEmpty)
              ? Value(clientCode)
              : const Value.absent(),
          name: Value(data['name'] as String),
          phone: Value(data['phone'] as String?),
          address: Value(data['address'] as String?),
          isSupplier: Value(parseBool(data['isSupplier'], false)),
          isCustomer: Value(parseBool(data['isCustomer'], true)),
          isDeliveryCompany: Value(parseBool(data['isDeliveryCompany'], false)),
          taxId: Value(data['taxId'] as String?),
          creditLimit: Value(parseDoubleNullable(data['creditLimit']) ?? 0),
          paymentTermsDays:
              Value((data['paymentTermsDays'] as num?)?.toInt() ?? 0),
          balance: Value(parseDoubleNullable(data['balance']) ?? 0),
          fixedDiscount: Value(
            parseDoubleNullable(data['fixedDiscount']) ?? 0,
          ),
          priceLevel: Value(data['priceLevel'] as String? ?? 'default'),
          groupId: Value(parseIntNullable(data['groupId'])),
           currencyId: Value(parseIntNullable(data['currencyId'] ?? data['currency_id'])),
        ),
      );
      broadcast('parties');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      debugPrint('[API] postParty error: $e');
      return errorResponse('Failed to create party: $e');
    }
  }

  Future<Response> putParty(Request request, String id) async {
    try {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final party = await db.getPartyById(int.parse(id));
      if (party == null) return errorResponse('Party not found', statusCode: 404);

      // Spec 077 Batch 2: gate on the STORED row's flag (not the body —
      // the body may omit it and isSupplier shouldn't be mutable via
      // a routine name/phone edit anyway).
      final perm = await ApiUserCtx.requirePermission(
        request,
        db,
        _partyPermissionFor('edit', isSupplier: party.isSupplier),
      );
      if (perm != null) return perm;

      // groupId is optional and uses Value(null) to distinguish
      // "unset — keep existing" from "clear the membership".
      final hasGroupIdKey = data.containsKey('groupId');
      final nextGroupId = hasGroupIdKey
          ? parseIntNullable(data['groupId'])
          : party.groupId;
      await db.updateParty(
        party.copyWith(
          name: data['name'] as String? ?? party.name,
          phone: Value(data['phone'] as String? ?? party.phone),
          address: Value(data['address'] as String? ?? party.address),
          taxId: Value(data['taxId'] as String? ?? party.taxId),
          creditLimit:
              parseDoubleNullable(data['creditLimit']) ?? party.creditLimit,
          paymentTermsDays:
              (data['paymentTermsDays'] as num?)?.toInt() ??
                  party.paymentTermsDays,
          balance: parseDoubleNullable(data['balance']) ?? party.balance,
          fixedDiscount:
              parseDoubleNullable(data['fixedDiscount']) ??
              party.fixedDiscount,
          priceLevel: data['priceLevel'] as String? ?? party.priceLevel,
          groupId: Value(nextGroupId),
        ),
      );
      broadcast('parties');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putParty error: $e');
      return errorResponse('Failed to update party: $e');
    }
  }

  Future<Response> deleteParty(Request request, String id) async {
    try {
      final partyId = int.parse(id);

      // Spec 077 Batch 2: gate on the existing row's flag. If the row
      // is already gone the operation is a no-op (idempotent delete);
      // returning success without gating doesn't leak existence in any
      // way an authenticated caller couldn't already determine.
      final party = await db.getPartyById(partyId);
      if (party == null) {
        return jsonResponse({'success': true});
      }
      final perm = await ApiUserCtx.requirePermission(
        request,
        db,
        _partyPermissionFor('delete', isSupplier: party.isSupplier),
      );
      if (perm != null) return perm;

      await db.deleteParty(partyId);
      broadcast('parties');
      broadcastRecordDeleted('parties', partyId);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete party: $e');
    }
  }
}
