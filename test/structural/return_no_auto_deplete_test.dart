// A sales RETURN must never run auto-deplete — that consumes the raw
// materials a second time instead of giving them back.
//
// `SalesTransactionOrchestrator.createSalesInvoice` handles both directions:
// a normal sale and a POS quick return (`saleType: 'return'`, quantities
// POSITIVE, the finished item goes back into stock). The journal-entry call at
// the bottom of that method is correctly guarded with `saleType != 'return'`
// — and the comment above it explains exactly why a return needs its own
// treatment. The auto-deplete block ~90 lines earlier had only the
// `!isClientMode` half of that guard.
//
// Result on a BOM item: returning one meal restored the meal AND deducted
// another meal's worth of ingredients. Reversal already has its own
// implementation (`manufacturing_dao.reverseSaleConsumption`, called from the
// returns dialog) — auto-deplete has no role on a return at all.
//
// WHY THIS TEST IS STRUCTURAL: exercising the real path needs a live
// AppDatabase plus CartItemEntity fixtures plus a KitchenService, i.e. a
// full-screen-weight integration harness — the class of test this repo has
// measured at 10-minute timeouts. The same trade-off (and the same source-
// assert form) is documented in outbox_unhandled_op_dispatch_test.dart. The
// assertion below fails against pre-fix source, which is what it is for.
//
// If a behavioural test is added later, it belongs in test/integration and
// should assert: after createSalesInvoice(saleType: 'return') for a BOM item,
// the raw materials' stock is UNCHANGED (or restored) — never lower.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const relPath = 'lib/data/repositories/sales_transaction_orchestrator.dart';
  late String source;

  setUpAll(() {
    final file = File(relPath);
    expect(file.existsSync(), isTrue, reason: 'expected orchestrator at $relPath');
    source = file.readAsStringSync();
  });

  test('auto-deplete is skipped for saleType == return', () {
    // Scope the assertion to the region that actually guards the
    // auto-deplete call. A naive whole-file `contains("saleType != 'return'")`
    // passes against pre-fix source because the JOURNAL-ENTRY guard ~90 lines
    // BELOW already spells it that way — the first draft of this test did
    // exactly that and proved nothing.
    final callIndex = source.indexOf('applyAutoDepleteForSale(');
    expect(callIndex, greaterThan(0),
        reason: 'expected an applyAutoDepleteForSale call site');

    // Walk back to the `if` that opens the block containing the call.
    final head = source.substring(0, callIndex);
    final guardIndex = head.lastIndexOf('if (!isClientMode');
    expect(guardIndex, greaterThan(0),
        reason: 'the auto-deplete block is expected to be gated on '
            'isClientMode — if that changed, re-derive this assertion');

    final guardLine = source.substring(
        guardIndex, source.indexOf(')', guardIndex) + 1);

    expect(guardLine.contains('isReturnSale') || guardLine.contains("'return'"),
        isTrue,
        reason: 'applyAutoDepleteForSale must not run on a return. Without '
            'the guard, returning a BOM item restores the finished good and '
            'deducts its raw materials a second time — stock drains by one '
            'recipe per return, and the consumption rows record a '
            'consumption that never happened.\n'
            'Guard found: $guardLine');
  });

  test('the return flag the guard reads is derived from saleType', () {
    expect(source.contains("saleType == 'return'"), isTrue,
        reason: 'isReturnSale must be derived from saleType, not from an '
            'unrelated flag that a caller might forget to set');
  });

  test('legacy assertion kept honest — JE guard still present', () {
    // The JE guard is the sibling this fix mirrors; if it ever disappears the
    // return path regresses in the other direction (a second, wrong-direction
    // revenue JE on top of autoPostSalesReturn's contra-revenue entry).
    expect(source.contains("saleType != 'return' && !isClientMode"), isTrue,
        reason: 'the sales JE must stay skipped for returns — '
            'autoPostSalesReturn already posts the contra-revenue entry');
  });

  test('the reversal path exists and is what returns use', () {
    // Guards against a future "fix" that re-adds auto-deplete to the return
    // path instead of routing to the reversal that already exists.
    final reversal = File('lib/data/repositories/returns_repository_impl.dart')
        .readAsStringSync();
    expect(reversal.contains('reverseSaleConsumption('), isTrue,
        reason: 'returns give raw materials BACK via reverseSaleConsumption; '
            'if this call disappears, the return path has silently lost its '
            'only correct BOM handling');
  });
}
