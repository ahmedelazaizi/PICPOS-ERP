// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class PartySyncStrategy extends SyncStrategy {
  PartySyncStrategy(super.db);

  @override
  String get tableName => 'parties';

  @override
  String get apiEndpoint => '/api/parties';

  /// R5 / SYNC_ARCHITECTURE §3.2: parties (customers/suppliers) use
  /// last-write-wins because the same row gets edited from multiple
  /// branches — phone/address updates from a cashier MUST NOT be silently
  /// overwritten by an older server snapshot on the next pull. We compare
  /// `lastModifiedAt` on both sides via the base class's `resolveConflict`
  /// and skip the update when the local row is newer.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.lastWriteWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final parties = json['parties'] as List;
    for (final p in parties) {
      // Dedupe by globalId first. The client's optimistic write creates a
      // row with a local auto-increment id + a stable globalId; the server
      // then assigns its own id but preserves the same globalId. Matching
      // on globalId lets us merge the two identities into a single local
      // row (keeping the local id intact so existing FKs — invoices,
      // receipts, journal lines — keep pointing at the right party).
      final globalId = p['globalId'] as String?;
      Party? existing;
      if (globalId != null && globalId.isNotEmpty) {
        existing = await (db.select(db.parties)
              ..where((t) => t.globalId.equals(globalId)))
            .getSingleOrNull();
      }

      final companion = PartiesCompanion(
        name: Value(p['name'] as String),
        code: Value(p['code'] as String?),
        phone: Value(p['phone'] as String?),
        address: Value(p['address'] as String?),
        taxId: Value(p['taxId'] as String?),
        tin: Value(p['tin'] as String?),
        globalId: Value(globalId),
        isCustomer: Value(parseBool(p['isCustomer'], true)),
        isSupplier: Value(parseBool(p['isSupplier'], false)),
        isDeliveryCompany: Value(parseBool(p['isDeliveryCompany'], false)),
        isFavorite: Value(parseBool(p['isFavorite'], false)),
        balance: Value(parseDouble(p['balance'])),
        creditLimit: Value(parseDouble(p['creditLimit'])),
        fixedDiscount: Value(parseDouble(p['fixedDiscount'])),
        priceLevel: Value(p['priceLevel'] as String? ?? 'default'),
        accountId: Value(parseIntNullable(p['accountId'])),
        groupId: Value(parseIntNullable(p['groupId'])),
        isActive: Value(parseBool(p['isActive'], true)),
      );

      if (existing != null) {
        // R5 lastWriteWins: consult resolveConflict before overwriting. If
        // the local row carries a newer lastModifiedAt than the server
        // payload, we KEEP the local version and log a SYNC-WARN. Without
        // this guard, a cashier's recent phone/address edit gets silently
        // wiped on the next pull.
        final shouldApply = await resolveConflict(
          recordId: existing.id.toString(),
          localData: {
            'updatedAt': existing.lastModifiedAt?.toIso8601String() ??
                existing.createdAt.toIso8601String(),
            'globalId': existing.globalId,
            'name': existing.name,
            'phone': existing.phone,
          },
          serverData: {
            'updatedAt': p['lastModifiedAt'] as String? ??
                p['updatedAt'] as String? ??
                p['createdAt'] as String? ??
                DateTime.now().toIso8601String(),
            'globalId': globalId,
            'name': p['name'],
            'phone': p['phone'],
          },
        );
        if (shouldApply) {
          // Update in place — do NOT touch the primary key.
          await (db.update(db.parties)
                ..where((t) => t.id.equals(existing!.id)))
              .write(companion);
        } else {
          await DiagnosticLogger.log(
            'SYNC-WARN',
            'parties skipped — local edit newer than server '
                '(globalId=$globalId localId=${existing.id} '
                'name="${existing.name}" — lastWriteWins kept local)',
          );
        }
      } else {
        // No globalId match — narrow name-based fallback intended ONLY to
        // catch the seeded duplicates we know exist:
        //   1. Real customers/suppliers with the same phone on both sides
        //   2. Delivery-company singletons identifiable by priceLevel
        // We deliberately DO NOT match purely on name+role, because real
        // users have legitimate same-named parties (multiple "أحمد"s without
        // phones) and a too-broad merger silently destroys data.
        final partyName = p['name'] as String? ?? '';
        final partyPhone = p['phone'] as String?;
        final isDelivery = parseBool(p['isDeliveryCompany'], false);
        final priceLevel = p['priceLevel'] as String? ?? 'default';

        // Tier A: exact name + phone match (only when both sides have a phone)
        if (partyName.isNotEmpty && partyPhone != null && partyPhone.isNotEmpty) {
          final candidates = await (db.select(db.parties)
            ..where((t) => t.name.equals(partyName))
            ..limit(10)
          ).get();
          for (final c in candidates) {
            if (c.phone == partyPhone) {
              existing = c;
              debugPrint('[PartySyncStrategy] Dedup by name+phone: "$partyName" → local id=${c.id}');
              await DiagnosticLogger.log(
                'SYNC-WARN',
                'parties matched on name+phone fallback '
                    '(name="$partyName" phone=$partyPhone serverId=${p['id']} '
                    'serverGlobalId=$globalId localId=${c.id})',
              );
              break;
            }
          }
        }

        // Tier B: delivery-company match by priceLevel — the seed sets
        // priceLevel to 'talabat' / 'careem' / 'ashyae' for the three brand
        // singletons, which is a unique business key independent of name.
        // This catches the local seed regardless of whether the server
        // renamed the party (e.g. "طلبات" → "شركة توصيل طلبات").
        if (existing == null &&
            isDelivery &&
            priceLevel != 'default' &&
            const {'talabat', 'careem', 'ashyae'}.contains(priceLevel)) {
          existing = await (db.select(db.parties)
            ..where((t) =>
                t.isDeliveryCompany.equals(true) &
                t.priceLevel.equals(priceLevel))
            ..limit(1)
          ).getSingleOrNull();
          if (existing != null) {
            debugPrint('[PartySyncStrategy] Dedup delivery by priceLevel=$priceLevel → local id=${existing.id}');
            await DiagnosticLogger.log(
              'SYNC-WARN',
              'parties matched on delivery-priceLevel fallback '
                  '(priceLevel=$priceLevel serverName="$partyName" '
                  'serverId=${p['id']} serverGlobalId=$globalId '
                  'localId=${existing.id})',
            );
          }
        }

        // Tier C (Cluster 035 / Issue 2 — 2026-05-12): known-seed-name
        // re-link for delivery companies. Catches the case where:
        //   • Migration v30 ran on a client install, creating local
        //     'طلبات' / 'كريم' / 'اشيائي' rows with NEW local globalIds.
        //   • Server has its own copies with DIFFERENT globalIds AND
        //     priceLevel='default' (so Tier B misses).
        // Without this, the first sync inserts the server's rows fresh,
        // producing the field-reported "اشيائي appears twice" duplicates.
        // Same pattern as Feature 035's Tier 4 re-link for canonical
        // branches — restricted to a hard-coded seed-name set so it can't
        // accidentally merge two legitimately same-named delivery parties
        // that the merchant created manually.
        if (existing == null && isDelivery && partyName.isNotEmpty) {
          const knownDeliverySeedNames = <String>{
            'طلبات', 'كريم', 'اشيائي',
            'شركة توصيل طلبات',
            'شركة توصيل كريم',
            'شركة توصيل اشيائي',
          };
          if (knownDeliverySeedNames.contains(partyName)) {
            existing = await (db.select(db.parties)
              ..where((t) =>
                  t.isDeliveryCompany.equals(true) &
                  t.name.equals(partyName))
              ..limit(1)
            ).getSingleOrNull();
            if (existing != null) {
              debugPrint('[PartySyncStrategy] Dedup delivery by seed-name="$partyName" → local id=${existing.id}');
              await DiagnosticLogger.log(
                'SYNC-WARN',
                'parties matched on delivery-seed-name fallback '
                    '(name="$partyName" serverId=${p['id']} '
                    'serverGlobalId=$globalId localId=${existing.id} '
                    'localPriceLevel=${existing.priceLevel} '
                    'serverPriceLevel=$priceLevel)',
              );
            }
          }
        }

        if (existing != null) {
          // Found via fallback — update in place, keep local id so FKs stay valid
          await (db.update(db.parties)
                ..where((t) => t.id.equals(existing!.id)))
              .write(companion);
        } else {
          // Genuinely new party — insert with server's id
          await db.into(db.parties).insertOnConflictUpdate(
                companion.copyWith(id: Value(parseInt(p['id']))),
              );
        }
      }
    }
    // Force UI refresh after sync
    if (parties.isNotEmpty) {
      db.markTablesUpdated({db.parties});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.parties).insertOnConflictUpdate(record as PartiesCompanion);
  }
}