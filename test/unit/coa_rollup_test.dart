import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/coa/coa_rollup.dart';

// Spec 135 BUG-E — pure roll-up of Chart-of-Accounts balances.
// leaf = own; parent = own + every descendant; grand total over roots only.
// Operates on plain (id, parentId, balance) records (CoaNode) so it stays off
// the data/database layer.

CoaNode n(int id, double balance, {int? parentId}) =>
    (id: id, parentId: parentId, balance: balance);

void main() {
  group('CoaRollup', () {
    test('leaf shows its own balance', () {
      final r = CoaRollup.compute([n(1, 100)]);
      expect(r.balanceOf(1, 100), 100);
    });

    test('parent rolls up own + descendants (multi-level)', () {
      // 1 (own 10) ─ 2 (own 20) ─ 4 (own 5)
      //            └ 3 (own 30)
      final nodes = [
        n(1, 10),
        n(2, 20, parentId: 1),
        n(3, 30, parentId: 1),
        n(4, 5, parentId: 2),
      ];
      final r = CoaRollup.compute(nodes);
      expect(r.balanceOf(4, 5), 5); // leaf 4
      expect(r.balanceOf(2, 20), 25); // 2: 20 + 5
      expect(r.balanceOf(3, 30), 30); // 3 leaf
      expect(r.balanceOf(1, 10), 65); // 1: 10 + 25 + 30
    });

    test('grand total over roots equals flat fold of all own balances', () {
      final nodes = [
        n(1, 10),
        n(2, 20, parentId: 1),
        n(3, 30, parentId: 1),
        n(4, 5, parentId: 2),
        n(10, 7), // second root
      ];
      final r = CoaRollup.compute(nodes);
      final roots = nodes.where((a) => a.parentId == null);
      final flatFold = nodes.fold<double>(0, (s, a) => s + a.balance);
      expect(r.grandTotalOfRoots(roots), flatFold); // 72
      expect(r.grandTotalOfRoots(roots), 72);
    });

    test('parent subtotal still includes children hidden by a filter', () {
      final full = [
        n(1, 0),
        n(2, 40, parentId: 1),
        n(3, 60, parentId: 1),
      ];
      // Roll-up computed over the FULL list (as the screen does).
      final r = CoaRollup.compute(full);
      // Even though a filtered view might only render account 1, its subtotal
      // reflects both hidden children.
      expect(r.balanceOf(1, 0), 100);
    });

    test('handles negative balances', () {
      final nodes = [
        n(1, 0),
        n(2, 100, parentId: 1),
        n(3, -40, parentId: 1),
      ];
      final r = CoaRollup.compute(nodes);
      expect(r.balanceOf(1, 0), 60);
    });

    test('balanceOf falls back to own balance for an unknown id', () {
      final r = CoaRollup.compute([n(1, 10)]);
      expect(r.balanceOf(999, 42), 42);
    });
  });
}
