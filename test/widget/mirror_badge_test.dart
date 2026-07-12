// MM.B Widget Tests — MirrorBadge
//
// Verifies the connectivity classifier (online / slow / offline) and the
// rendered states of the mirror-mode sidebar badge. The classifier is the
// public contract the badge promises to its host (AppShell), so the
// staleness thresholds defined in the MM.A foundation doc are pinned
// here as test cases:
//
//   • <30s        → online   ("الآن", green dot)
//   • 30s–5min    → slow     ("بطىء", amber dot)
//   • >5min/null  → offline  ("خارج الاتصال", red dot)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/presentation/widgets/mirror_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
      // Dark scaffold mimics the actual sidebar background — the badge
      // uses white-on-translucent text/borders that disappear against
      // the default Scaffold background.
      home: Scaffold(
        backgroundColor: const Color(0xFF1E293B),
        body: Center(child: child),
      ),
    );

DateTime _utcAgo(Duration d) => DateTime.now().toUtc().subtract(d);

void main() {
  group('MirrorBadge.classify — staleness tiers', () {
    test('null lastHandshakeAt → offline', () {
      expect(MirrorBadge.classify(null), MirrorConnectivity.offline);
    });

    test('handshake 5s ago → online', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(seconds: 5))),
        MirrorConnectivity.online,
      );
    });

    test('handshake exactly at 30s boundary → online (inclusive)', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(seconds: 30))),
        MirrorConnectivity.online,
        reason: '30s is the upper bound of the green tier per MM.A spec',
      );
    });

    test('handshake 31s ago → slow', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(seconds: 31))),
        MirrorConnectivity.slow,
      );
    });

    test('handshake 4 minutes ago → slow', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(minutes: 4))),
        MirrorConnectivity.slow,
      );
    });

    test('handshake exactly at 5min boundary → slow (inclusive)', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(minutes: 5))),
        MirrorConnectivity.slow,
      );
    });

    test('handshake 6 minutes ago → offline', () {
      expect(
        MirrorBadge.classify(_utcAgo(const Duration(minutes: 6))),
        MirrorConnectivity.offline,
      );
    });
  });

  group('MirrorBadge — visibility', () {
    testWidgets('hidden when serverDisplayName is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const MirrorBadge(
          serverDisplayName: null,
          lastHandshakeAt: null,
        ),
      ));
      // Badge collapses to SizedBox.shrink — no "🪞" leading glyph.
      expect(find.textContaining('🪞'), findsNothing);
    });

    testWidgets('hidden when serverDisplayName is empty string',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MirrorBadge(
          serverDisplayName: '',
          lastHandshakeAt: null,
        ),
      ));
      expect(find.textContaining('🪞'), findsNothing);
    });

    testWidgets('visible when serverDisplayName is set', (tester) async {
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq.example.com:8080',
          lastHandshakeAt: _utcAgo(const Duration(seconds: 5)),
        ),
      ));
      expect(find.textContaining('🪞'), findsOneWidget);
      expect(find.text('hq.example.com:8080'), findsOneWidget);
    });
  });

  group('MirrorBadge — status label per tier', () {
    testWidgets('online tier shows "الآن"', (tester) async {
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: _utcAgo(const Duration(seconds: 5)),
        ),
      ));
      expect(find.text('الآن'), findsOneWidget);
      expect(find.text('بطىء'), findsNothing);
      expect(find.text('خارج الاتصال'), findsNothing);
    });

    testWidgets('slow tier shows "بطىء"', (tester) async {
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: _utcAgo(const Duration(minutes: 2)),
        ),
      ));
      expect(find.text('بطىء'), findsOneWidget);
    });

    testWidgets('offline tier (null handshake) shows "خارج الاتصال"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: null,
        ),
      ));
      expect(find.text('خارج الاتصال'), findsOneWidget);
    });
  });

  group('MirrorBadge — dot colour reflects tier', () {
    Color? dotColorOf(WidgetTester tester) {
      // The connectivity dot is the only Container with shape: circle in
      // the badge. Find it directly so the assertion stays robust against
      // unrelated styling changes (padding, border, etc.).
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        final deco = c.decoration;
        if (deco is BoxDecoration && deco.shape == BoxShape.circle) {
          return deco.color;
        }
      }
      return null;
    }

    testWidgets('online → green', (tester) async {
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: _utcAgo(const Duration(seconds: 5)),
        ),
      ));
      expect(dotColorOf(tester), AppColors.success);
    });

    testWidgets('slow → amber', (tester) async {
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: _utcAgo(const Duration(minutes: 2)),
        ),
      ));
      expect(dotColorOf(tester), AppColors.warning);
    });

    testWidgets('offline → red', (tester) async {
      await tester.pumpWidget(_wrap(
        const MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: null,
        ),
      ));
      expect(dotColorOf(tester), AppColors.error);
    });
  });

  group('MirrorBadge — onTap', () {
    testWidgets('fires onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        MirrorBadge(
          serverDisplayName: 'hq',
          lastHandshakeAt: _utcAgo(const Duration(seconds: 5)),
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.text('hq'));
      expect(tapped, isTrue);
    });
  });
}
