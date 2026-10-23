// Spec 129 F5 / T041 — JournalEntryGid formula contract.
//
// All auto-posted JE globalIds follow the canonical schema
//   `je-<sourceType>-<sourceGid>-<verb>`
// computed by `lib/core/utils/journal_entry_gid.dart`. This test pins:
//   (a) the produced string for every documented sourceType + verb,
//   (b) determinism — same args ⇒ same string on every call,
//   (c) the asserts that block ambiguous arguments.

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/utils/journal_entry_gid.dart';

void main() {
  group('Spec 129 F5 — JournalEntryGid.compute', () {
    const sourceGid = '0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e2f';

    test('canonical schema for all 9 sourceType values', () {
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceCommercialPaper,
          sourceGid: sourceGid,
          verb: 'cashed',
        ),
        'je-cp-$sourceGid-cashed',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceStockAdjustment,
          sourceGid: sourceGid,
          verb: 'post',
        ),
        'je-stockadj-$sourceGid-post',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceSalesReturn,
          sourceGid: sourceGid,
          verb: 'post',
        ),
        'je-saleret-$sourceGid-post',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourcePurchaseReturn,
          sourceGid: sourceGid,
          verb: 'post',
        ),
        'je-purret-$sourceGid-post',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceShiftOpen,
          sourceGid: sourceGid,
          verb: 'open',
        ),
        'je-shiftopen-$sourceGid-open',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceShiftClose,
          sourceGid: sourceGid,
          verb: 'close',
        ),
        'je-shiftclose-$sourceGid-close',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceSafeClose,
          sourceGid: sourceGid,
          verb: 'close',
        ),
        'je-safeclose-$sourceGid-close',
      );
      // Spec 135 — base sale/purchase autopost JE.
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourceSale,
          sourceGid: sourceGid,
          verb: 'post',
        ),
        'je-sale-$sourceGid-post',
      );
      expect(
        JournalEntryGid.compute(
          sourceType: JournalEntryGid.sourcePurchase,
          sourceGid: sourceGid,
          verb: 'post',
        ),
        'je-purchase-$sourceGid-post',
      );
    });

    test('two independent calls with the same args produce equal strings', () {
      final a = JournalEntryGid.compute(
        sourceType: 'cp',
        sourceGid: sourceGid,
        verb: 'bounced',
      );
      final b = JournalEntryGid.compute(
        sourceType: 'cp',
        sourceGid: sourceGid,
        verb: 'bounced',
      );
      expect(a, equals(b));
    });

    test('different verbs produce different strings (per-status dedup)', () {
      final pending = JournalEntryGid.compute(
        sourceType: 'cp',
        sourceGid: sourceGid,
        verb: 'pending',
      );
      final cashed = JournalEntryGid.compute(
        sourceType: 'cp',
        sourceGid: sourceGid,
        verb: 'cashed',
      );
      expect(pending, isNot(equals(cashed)));
    });

    test('sourceGid may contain hyphens (UUIDv7), but sourceType/verb may not', () {
      // Hyphenated sourceGid is allowed.
      expect(
        () => JournalEntryGid.compute(
          sourceType: 'cp',
          sourceGid: sourceGid, // has hyphens
          verb: 'pending',
        ),
        returnsNormally,
      );
      // Hyphenated sourceType is rejected (would break parsing).
      expect(
        () => JournalEntryGid.compute(
          sourceType: 'com-paper',
          sourceGid: sourceGid,
          verb: 'pending',
        ),
        throwsA(isA<AssertionError>()),
      );
      // Hyphenated verb is rejected.
      expect(
        () => JournalEntryGid.compute(
          sourceType: 'cp',
          sourceGid: sourceGid,
          verb: 'in-portfolio',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('empty arguments are rejected', () {
      expect(
        () => JournalEntryGid.compute(
          sourceType: '',
          sourceGid: sourceGid,
          verb: 'cashed',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => JournalEntryGid.compute(
          sourceType: 'cp',
          sourceGid: '',
          verb: 'cashed',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => JournalEntryGid.compute(
          sourceType: 'cp',
          sourceGid: sourceGid,
          verb: '',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
