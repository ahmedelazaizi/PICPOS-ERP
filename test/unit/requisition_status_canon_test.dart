import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/requisition_status.dart';

/// Spec 148 (S-ISSUE) — the canonical status vocabulary must round-trip and
/// any legacy/unknown DB string must degrade to `pending` (so old rows still
/// render and filter). Guards the `enum == String` class of defect at its root.
void main() {
  group('RequisitionStatus canonical mapping', () {
    test('round-trips all four canonical values', () {
      for (final s in RequisitionStatus.values) {
        expect(parseStatus(statusToDb(s)), s,
            reason: 'parseStatus(statusToDb($s)) must equal $s');
      }
    });

    test('statusToDb produces the expected canonical strings', () {
      expect(statusToDb(RequisitionStatus.pending), 'pending');
      expect(statusToDb(RequisitionStatus.approved), 'approved');
      expect(statusToDb(RequisitionStatus.rejected), 'rejected');
      expect(statusToDb(RequisitionStatus.fulfilled), 'fulfilled');
    });

    test('legacy/unknown strings map to pending', () {
      for (final legacy in const [
        'draft',
        'submitted',
        'partiallyFulfilled',
        'cancelled',
        '',
        'garbage',
        'PENDING', // case-sensitive: not the canonical lowercase
      ]) {
        expect(parseStatus(legacy), RequisitionStatus.pending,
            reason: 'legacy "$legacy" must degrade to pending');
      }
    });

    test('canonical strings parse to their enum', () {
      expect(parseStatus('pending'), RequisitionStatus.pending);
      expect(parseStatus('approved'), RequisitionStatus.approved);
      expect(parseStatus('rejected'), RequisitionStatus.rejected);
      expect(parseStatus('fulfilled'), RequisitionStatus.fulfilled);
    });
  });
}
