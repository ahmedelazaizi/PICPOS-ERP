// Task 7 — نقطة البيع: جرس الإشعارات وتنبيه نقص المخزون في الهيدر.
//
// `pos_notifications` و`pos_low_stock_alert` كانا الودجتين (`PosNotificationBell`،
// `PosLowStockIndicator`) بيتركّبوا في `pos_header.dart` من غير أي فحص
// صلاحية خالص — عرض بحت (مفيش كتابة)، فالحارس `fallback: SizedBox.shrink()`.
//
// ── ليه مش PosHeader كامل ─────────────────────────────────────────────────
// `PosHeader` بياخد ٩ callbacks مطلوبة وبيعتمد على `posControllerProvider`
// وقاعدة بيانات. الودجتين اتلفّوا في دالتين top-level
// (`buildPosNotificationBellGuarded`/`buildPosLowStockIndicatorGuarded`) في
// `pos_header.dart` عشان يتبنوا لوحدهم ونثبت إن الإنتاج فعلاً بينادي نفس
// الدالة دي (مش نسخة موازية للاختبار بس).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/pos/widgets/header/pos_low_stock_indicator.dart';
import 'package:ural_erp/presentation/pos/widgets/header/pos_notification_bell.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_header.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pumpGuarded(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
          // مفيش قاعدة بيانات في هذا الاختبار — pos_low_stock_indicator.dart
          // بيقرا الصنف المنخفض عبر productRepositoryProvider الحقيقي، اللي
          // بيفتح AppDatabase() حقيقية لو ما اتقفلش هنا (نفس فخ الـ١٠ دقايق
          // اللي Task 6a واجهه). Stream فاضي كفاية لإثبات إن الحارس بيلفّ
          // الودجت الحقيقي، من غير ما نلمس أي DB.
          lowStockProductsProvider.overrideWith(
            (ref) => Stream.value(const <ProductEntity>[]),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: guarded))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('pos_notifications — جرس الإشعارات', () {
    testWidgets('الحارس مربوط بالكود الصح مع fallback مش allowManagerOverride',
        (tester) async {
      await pumpGuarded(
        tester,
        buildPosNotificationBellGuarded(),
        [PermissionCodes.posNotifications],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posNotifications);
      expect(guard.allowManagerOverride, isFalse);
      expect(guard.fallback, isNotNull);
      expect(find.byType(PosNotificationBell), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: الجرس مختفي تماماً', (tester) async {
      await pumpGuarded(tester, buildPosNotificationBellGuarded(), const []);
      expect(find.byType(PosNotificationBell), findsNothing);
    });
  });

  group('pos_low_stock_alert — تنبيه نقص المخزون', () {
    testWidgets('الحارس مربوط بالكود الصح مع fallback مش allowManagerOverride',
        (tester) async {
      await pumpGuarded(
        tester,
        buildPosLowStockIndicatorGuarded(),
        [PermissionCodes.posLowStockAlert],
      );

      final guard = tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.posLowStockAlert);
      expect(guard.allowManagerOverride, isFalse);
      expect(guard.fallback, isNotNull);
      expect(find.byType(PosLowStockIndicator), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: التنبيه مختفي تماماً', (tester) async {
      await pumpGuarded(tester, buildPosLowStockIndicatorGuarded(), const []);
      expect(find.byType(PosLowStockIndicator), findsNothing);
    });
  });
}
