// ═══════════════════════════════════════════════════════════════════════════
// Spec 131 — FR-005 sale-time pre-flight check
// ═══════════════════════════════════════════════════════════════════════════
//
// Structural / source-level invariants for the pre-flight added to
// SalesTransactionOrchestrator. The full behavioural matrix lives in
// quickstart.md cells 3 + 4 — running the orchestrator end-to-end would
// require booting the full sale-write stack (multiple DAOs, accounting
// service, kitchen service, etc.). These pins ensure the wire stays
// connected.
//
// Behavioural assertions:
//   1. _preflightSaleParity is invoked at the top of completeSalesTransaction.
//   2. The check is gated on SyncInterceptor.isClientMode (covers client +
//      mirror; bypasses standalone + server).
//   3. The five master-data kinds (warehouse, branch, customer, costCenter,
//      safe) are each represented in the check list.
//   4. customer check skips when adhocCustomerName is non-empty.
//   5. Throwing path emits both [MIRROR-MASTERDATA-CHECK all_resolved=false]
//      and [MIRROR-CACHE-DIVERGENCE].
//   6. Happy path emits exactly one [MIRROR-MASTERDATA-CHECK all_resolved=true].
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/data/repositories/sales_transaction_orchestrator.dart')
          .readAsStringSync();

  group('Spec 131 FR-005 — pre-flight wiring', () {
    test('completeSalesTransaction invokes _preflightSaleParity', () {
      final start = src.indexOf('Future<SaleResult> completeSalesTransaction');
      expect(start, isNot(-1));
      // Look at the first 1600 chars of the method body for the call.
      final body = src.substring(start, start + 1600);
      expect(body, contains('await _preflightSaleParity(request)'),
          reason: 'Pre-flight MUST run before any DB write — i.e., at the '
              'top of completeSalesTransaction, not deeper inside.');
    });

    test('_preflightSaleParity bails early on server/standalone', () {
      // The first statement of the helper body returns when
      // SyncInterceptor.isClientMode is false. Match the pattern.
      expect(
          src,
          contains(
              'Future<void> _preflightSaleParity'),
          reason: 'Helper must exist.');
      // Look up to 200 chars after the signature.
      final idx = src.indexOf('Future<void> _preflightSaleParity');
      final tail = src.substring(idx, idx + 400);
      expect(tail, contains('if (!SyncInterceptor.isClientMode) return;'),
          reason: 'Server/standalone modes must bypass the pre-flight.');
    });

    test('five master-data kinds are referenced in the check list', () {
      // The check builder enumerates each kind via the
      // MirrorMasterDataKind enum value.
      expect(src, contains('MirrorMasterDataKind.warehouse'));
      expect(src, contains('MirrorMasterDataKind.branch'));
      expect(src, contains('MirrorMasterDataKind.customer'));
      expect(src, contains('MirrorMasterDataKind.costCenter'));
      expect(src, contains('MirrorMasterDataKind.safe'));
    });

    test('customer check skips when adhocCustomerName is non-empty', () {
      expect(
          src,
          contains(
              "req.adhocCustomerName == null || req.adhocCustomerName!.isEmpty"),
          reason: 'Adhoc customers have no FK in parties — skip the check.');
    });

    test('check uses indexed SELECT 1 ... LIMIT 1 PK lookups', () {
      // _existsInMasterTable produces a parameterised PK lookup with
      // LIMIT 1 — keeps the query plan stable and cheap.
      expect(src, contains('SELECT 1 AS p FROM \$table WHERE id = ? LIMIT 1'),
          reason: 'PK lookup MUST be indexed + bounded.');
    });

    test('breadcrumbs cover both pass and fail paths', () {
      // The fail path emits both check (all_resolved=false) and divergence
      // lines; the pass path emits the check (all_resolved=true).
      expect(src, contains("'MIRROR-MASTERDATA-CHECK'"));
      expect(src, contains("'MIRROR-CACHE-DIVERGENCE'"));
      expect(src, contains('all_resolved=true'));
      expect(src, contains('all_resolved=false'));
      expect(src, contains('origin=pre-flight'));
    });

    test('throws MirrorCacheDivergenceException on first miss', () {
      expect(src, contains('throw MirrorCacheDivergenceException('));
      // First-miss-wins: the throw is INSIDE the for loop body.
      final loopIdx = src.indexOf('for (final check in checks)');
      expect(loopIdx, isNot(-1));
      final throwIdx = src.indexOf('throw MirrorCacheDivergenceException(',
          loopIdx);
      expect(throwIdx, isNot(-1));
      // Throw should be reasonably close to the loop (within ~3 KB), not
      // hoisted out of it.
      expect(throwIdx - loopIdx, lessThan(3000),
          reason: 'First-miss-wins requires the throw inside the for-loop.');
    });
  });

  group('Spec 131 FR-005 — exception type', () {
    final excSrc = File(
            'lib/services/sync/mirror_cache_divergence_exception.dart')
        .readAsStringSync();

    test('5 MirrorMasterDataKind variants exist', () {
      expect(excSrc, contains('enum MirrorMasterDataKind'));
      expect(excSrc, contains('warehouse'));
      expect(excSrc, contains('branch'));
      expect(excSrc, contains('customer'));
      expect(excSrc, contains('costCenter'));
      expect(excSrc, contains('safe'));
    });

    test('arabicName extension provides all 5 nouns', () {
      expect(excSrc, contains("'مخزن'"));
      expect(excSrc, contains("'فرع'"));
      expect(excSrc, contains("'عميل'"));
      expect(excSrc, contains("'مركز تكلفة'"));
      expect(excSrc, contains("'خزينة'"));
    });

    test('breadcrumbName uses snake_case stable identifiers', () {
      expect(excSrc, contains("'warehouse'"));
      expect(excSrc, contains("'cost_center'"));
    });

    test('exception carries kind + requestedId + cachedIds', () {
      expect(excSrc, contains('final MirrorMasterDataKind kind'));
      expect(excSrc, contains('final int requestedId'));
      expect(excSrc, contains('final List<int> cachedIds'));
    });
  });
}
