// Spec 129 F2 / T057 — Structural guard against new manual `broadcast(...)`
// call sites outside the `ApiHandlerBase.withBroadcast` wrapper.
//
// Contract (contracts/broadcast-wrapper.md §3 + §4): every mutating
// endpoint MUST route its broadcasts through the wrapper so the declared
// `tables` set acts as a single source of truth for mirror/client fan-out.
// New endpoints that directly call `broadcast('X')` reintroduce the class
// of bugs Spec 129 closed (mirrors silently behind HQ state).
//
// Migration baseline (2026-05-25): Phase 4A migrated the 18 endpoints
// listed in spec.md (postSalesReturn + 2 purchase-return paths +
// postBranch + postProduct + 13 in api_data_handler). The remaining
// ~96 direct `broadcast(...)` calls in the API handler files are
// pre-existing legacy callers (single-table broadcasts on simple CRUD
// endpoints — postRole, postPriceList, postUser, etc.). A follow-up spec
// will migrate them in a separate sweep.
//
// To prevent regression in the meantime, this test pins a per-file count
// baseline. New direct-broadcast call sites push a file's count above its
// baseline and fail CI; deleted ones lower the count and require updating
// the baseline. A file not in the baseline must contain zero direct calls.
//
// Documented exemptions (the wrapper's internal mechanism + the unrelated
// `StreamController.broadcast()` from dart:async):
//   - lib/services/api/api_handler_base.dart  — defines `broadcast(...)`
//                                                 and the `withBroadcast`
//                                                 wrapper-internal call.
//   - lib/services/sync_event_bus.dart        — `StreamController.broadcast()`.
//                                                 Different API entirely.
//
// To MIGRATE a file off the baseline:
//   1. Route each `broadcast('X')` line through the appropriate endpoint's
//      `ApiHandlerBase.withBroadcast(endpointLabel, tables, body)`.
//   2. Re-run this test; it reports the new count.
//   3. Lower the baseline number in this file to match.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Per-file count of `broadcast(...)` direct-call sites that pre-date the
/// Spec 129 Phase 4A migration. New code that touches these files must NOT
/// increase the count; a future spec is expected to migrate each entry to
/// the wrapper and lower the number.
///
/// Counts the literal occurrences of `broadcast(` at the start of a line
/// (allowing leading whitespace), matching the same regex this test uses.
const Map<String, int> _baselineDirectBroadcastCounts = <String, int>{
  // 18 calls migrated by Phase 4A; remaining are the legacy single-table
  // broadcasts on CRUD endpoints (postRole, putRole, postPriceList,
  // postPartyGroup, postQuotation, postPurchaseOrder, postSalesOrder,
  // postUser, putUser, deleteUser, postWarehouse, putWarehouse,
  // putCostCenter, postCostCenter, putAccount, postAccount,
  // putRenewPaper, postEndorsePaper, putSafe, deleteSafe, etc.).
  // api_data_handler.dart was split into part files (pure move); its 86
  // legacy calls now live in these files (sum unchanged).
  'lib/services/api/data/api_data_accounting.dart': 8,
  'lib/services/api/data/api_data_commercial_papers.dart': 2,
  'lib/services/api/data/api_data_documents.dart': 20,
  'lib/services/api/data/api_data_expenses.dart': 3,
  'lib/services/api/data/api_data_inventory.dart': 8,
  'lib/services/api/data/api_data_org_structure.dart': 16,
  'lib/services/api/data/api_data_system.dart': 11,
  'lib/services/api/data/api_data_treasury.dart': 6,
  'lib/services/api/data/api_data_users_roles.dart': 12,
  'lib/services/api/api_party_handler.dart': 4,
  'lib/services/api/api_product_handler.dart': 10,
  // Spec 136 (5f06b24): postPurchase broadcasts safe_transactions+
  // journal_entries+accounting+parties+inventory+stock_movements so the mirror
  // pulls the cash-purchase payment voucher — legacy direct calls; migrate
  // postPurchase to withBroadcast in a follow-up.
  'lib/services/api/api_purchase_handler.dart': 13,
  'lib/services/api/api_sales_handler.dart': 7,
  'lib/services/api/api_terminals_handler.dart': 1,
};

/// Files explicitly exempt from the grep. These define or wrap the
/// broadcast primitive — flagging them would be a false positive.
const Set<String> _exemptFiles = <String>{
  'lib/services/api/api_handler_base.dart',
  'lib/services/sync_event_bus.dart',
};

final RegExp _broadcastCallSite =
    RegExp(r'^\s*broadcast(?:RecordDeleted)?\(', multiLine: true);

void main() {
  test('Spec 129 F2 / FR-203 — no NEW direct broadcast() calls outside '
      'the withBroadcast wrapper', () {
    final servicesDir = Directory('lib/services');
    expect(servicesDir.existsSync(), isTrue,
        reason: 'Test must run from URAL-ERP repo root.');

    final actualCounts = <String, int>{};
    for (final entity in servicesDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final normPath = entity.path.replaceAll(r'\', '/');
      if (_exemptFiles.contains(normPath)) continue;

      final content = entity.readAsStringSync();
      final matches = _broadcastCallSite.allMatches(content).length;
      if (matches > 0) actualCounts[normPath] = matches;
    }

    // 1. Any file with direct calls must appear in the baseline.
    final unknownOffenders = actualCounts.keys
        .where((p) => !_baselineDirectBroadcastCounts.containsKey(p))
        .toList()
      ..sort();
    expect(
      unknownOffenders,
      isEmpty,
      reason: '[no_manual_broadcast] NEW file(s) contain direct broadcast(...) '
          'calls — route through ApiHandlerBase.withBroadcast(...) per '
          'specs/129-mirror-broadcast-discipline/contracts/broadcast-wrapper.md.\n'
          'Offenders:\n${unknownOffenders.map((p) => '  $p').join('\n')}',
    );

    // 2. Each baseline file's count must NOT exceed its baseline. A lower
    //    count is fine (someone migrated a few calls); the test reports the
    //    new count so the baseline can be tightened in a follow-up commit.
    final regressed = <String>[];
    final tightenable = <String>[];
    for (final entry in _baselineDirectBroadcastCounts.entries) {
      final actual = actualCounts[entry.key] ?? 0;
      if (actual > entry.value) {
        regressed.add('  ${entry.key}: baseline=${entry.value} actual=$actual '
            '(+${actual - entry.value} new direct broadcast(...) call(s))');
      } else if (actual < entry.value) {
        tightenable.add('  ${entry.key}: baseline=${entry.value} actual=$actual '
            '(can be tightened to $actual)');
      }
    }

    expect(
      regressed,
      isEmpty,
      reason: '[no_manual_broadcast] direct broadcast(...) call count rose '
          'above the baseline in:\n${regressed.join('\n')}\n\n'
          'Either migrate the new call site to ApiHandlerBase.withBroadcast '
          'or — if intentionally adding to the legacy queue — bump the '
          'baseline in test/structural/no_manual_broadcast_test.dart with '
          'a comment explaining why.',
    );

    // Informational: if baselines can be tightened, print so the next
    // commit can reflect the progress. This does NOT fail the test.
    if (tightenable.isNotEmpty) {
      // ignore: avoid_print
      print('[no_manual_broadcast] baseline(s) can be tightened:\n'
          '${tightenable.join('\n')}');
    }
  });
}
