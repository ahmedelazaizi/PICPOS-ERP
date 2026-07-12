/// Day-23 Widget Tests — SyncStatusBadge
///
/// 10 tests that verify every visual state of the sync status badge that lives
/// in the App Shell header. The badge communicates outbox health at a glance:
///
///   • Hidden       — both counts are zero
///   • Warning (yellow) — pending operations are waiting to sync
///   • Error   (red)    — dead-letter queue is non-empty (permanent failures)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/widgets/sync_status_badge.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('SyncStatusBadge — sync outbox state display', () {
    // ── Visibility ──────────────────────────────────────────────────────────

    testWidgets('hidden when pendingCount = 0 and deadLetterCount = 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SyncStatusBadge(pendingCount: 0, deadLetterCount: 0)),
      );
      // The badge collapses to SizedBox.shrink() — no Container, no Text
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('visible when pendingCount > 0', (tester) async {
      await tester.pumpWidget(
        _wrap(const SyncStatusBadge(pendingCount: 3)),
      );
      expect(find.byType(Container), findsAtLeastNWidgets(1));
    });

    testWidgets('visible when deadLetterCount > 0 even if pendingCount = 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SyncStatusBadge(pendingCount: 0, deadLetterCount: 2),
        ),
      );
      expect(find.byType(Container), findsAtLeastNWidgets(1));
    });

    // ── Label text ───────────────────────────────────────────────────────────

    testWidgets('shows pending count as plain number when no dead letters',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SyncStatusBadge(pendingCount: 7)),
      );
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows dead-letter count followed by "!" when queue non-empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SyncStatusBadge(pendingCount: 3, deadLetterCount: 2),
        ),
      );
      expect(find.text('2 !'), findsOneWidget);
    });

    testWidgets(
        'dead-letter label takes priority over pending count when both > 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SyncStatusBadge(pendingCount: 5, deadLetterCount: 1),
        ),
      );
      expect(find.text('1 !'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    // ── Icon ─────────────────────────────────────────────────────────────────

    testWidgets('shows cloud-upload icon when only pending count > 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SyncStatusBadge(pendingCount: 4)),
      );
      expect(find.byIcon(PhosphorIconsBold.cloudArrowUp), findsOneWidget);
    });

    testWidgets('shows cloud-slash icon when dead-letter count > 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SyncStatusBadge(pendingCount: 0, deadLetterCount: 1),
        ),
      );
      expect(find.byIcon(PhosphorIconsBold.cloudSlash), findsOneWidget);
    });

    // ── Tap callback ─────────────────────────────────────────────────────────

    testWidgets('onTap callback fires when badge is tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrap(
          SyncStatusBadge(
            pendingCount: 2,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(tapped, isTrue);
    });

    // ── Color semantics ──────────────────────────────────────────────────────

    testWidgets('badge uses warning color when only pending count is set',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SyncStatusBadge(pendingCount: 3)),
      );
      // Find the badge Container scoped to the SyncStatusBadge subtree.
      final badgeContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SyncStatusBadge),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.decoration is BoxDecoration)
          .toList();

      expect(badgeContainers, isNotEmpty, reason: 'badge must render a Container');
      final decoration = badgeContainers.first.decoration as BoxDecoration;
      final color = decoration.color;
      expect(color, isNotNull);

      // SyncStatusBadge sets `AppColors.warning.withValues(alpha: 0.9)` for
      // the pending (non-dead-letter) state.  Compare directly.
      expect(
        color,
        equals(AppColors.warning.withValues(alpha: 0.9)),
        reason: 'pending badge must use warning (amber) color, not error (red)',
      );
    });
  });
}
