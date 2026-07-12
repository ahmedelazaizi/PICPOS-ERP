// ═══════════════════════════════════════════════════════════════════════════
// Feature 004 — BranchChip widget tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers the visual contract of `BranchChip`:
//   • renders branch name when branchId resolves to a known branch
//   • returns SizedBox.shrink() when branchId is null
//   • returns SizedBox.shrink() when the branch was deleted
//                       (id no longer in allBranchesProvider)
//   • returns SizedBox.shrink() while the branches stream is loading
//   • produces a deterministic colour per branchId (same id → same colour)
//   • compact mode reduces font size
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/presentation/widgets/branch_chip.dart';

Branche _branch(int id, String name) => Branche(
      id: id,
      name: name,
      isActive: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

Widget _wrap({
  required Widget child,
  required Stream<List<Branche>> stream,
}) {
  return ProviderScope(
    overrides: [
      allBranchesProvider.overrideWith((ref) => stream),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BranchChip — rendering', () {
    testWidgets('renders branch name when id resolves', (tester) async {
      final branches = [_branch(1, 'فرع القاهرة'), _branch(2, 'فرع الإسكندرية')];
      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: 1),
        stream: Stream.value(branches),
      ));
      await tester.pump();

      expect(find.text('فرع القاهرة'), findsOneWidget);
      expect(find.text('فرع الإسكندرية'), findsNothing);
    });

    testWidgets('hides itself when branchId is null', (tester) async {
      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: null),
        stream: Stream.value([_branch(1, 'فرع القاهرة')]),
      ));
      await tester.pump();

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('فرع القاهرة'), findsNothing);
    });

    testWidgets('hides itself when branch was deleted (id missing)',
        (tester) async {
      // branchId 99 doesn't exist in the snapshot — the chip must vanish
      // rather than render "بدون فرع" or a red error state.
      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: 99),
        stream: Stream.value([_branch(1, 'فرع القاهرة')]),
      ));
      await tester.pump();

      expect(find.text('فرع القاهرة'), findsNothing);
      expect(find.text('بدون فرع'), findsNothing);
    });

    testWidgets('hides itself while branches are loading', (tester) async {
      // Use a StreamController so we control the lifecycle — no pending
      // timers leak when the test framework tears down.
      final controller = StreamController<List<Branche>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: 1),
        stream: controller.stream,
      ));
      await tester.pump();

      // The StreamProvider is in AsyncLoading state — chip hides.
      expect(find.textContaining('فرع'), findsNothing);
    });
  });

  group('BranchChip.colorFor — deterministic palette', () {
    test('same id always produces the same colour', () {
      expect(BranchChip.colorFor(1), BranchChip.colorFor(1));
      expect(BranchChip.colorFor(7), BranchChip.colorFor(7));
    });

    test('different ids inside the palette range produce different colours',
        () {
      // 8-colour palette → ids 1..8 should all differ from each other.
      final colors = {for (var i = 1; i <= 8; i++) BranchChip.colorFor(i)};
      expect(colors.length, 8,
          reason: 'palette has 8 distinct colours, none should collide');
    });

    test('palette wraps around on ids beyond the palette length', () {
      // id 9 should produce the same colour as id 1 (wrap-around at length 8).
      expect(BranchChip.colorFor(9), BranchChip.colorFor(1));
    });

    test('negative ids are mapped via abs() before modulo', () {
      expect(BranchChip.colorFor(-1), BranchChip.colorFor(1));
    });
  });

  group('BranchChip — compact mode', () {
    testWidgets('compact=true reduces font size compared to default',
        (tester) async {
      final branches = [_branch(1, 'فرع القاهرة')];

      // Default
      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: 1),
        stream: Stream.value(branches),
      ));
      await tester.pump();
      final defaultSize = tester
          .widget<Text>(find.text('فرع القاهرة'))
          .style!
          .fontSize!;

      // Compact
      await tester.pumpWidget(_wrap(
        child: const BranchChip(branchId: 1, compact: true),
        stream: Stream.value(branches),
      ));
      await tester.pump();
      final compactSize = tester
          .widget<Text>(find.text('فرع القاهرة'))
          .style!
          .fontSize!;

      expect(compactSize, lessThan(defaultSize),
          reason: 'compact mode is intended for dense table rows');
    });
  });
}
