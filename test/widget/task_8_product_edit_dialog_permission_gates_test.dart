// دفعة ٨ — ديالوج تعديل الصنف: قسم «إدارة الصلاحية» وأزرار الصورة.
//
// `products_expiry` و`products_image` كانوا أكواد بلا إنفاذ — القسمين
// بيترسموا لأي حد يقدر يفتح الديالوج.
//
// ── ليه مش `ProductEditDialog` كامل ───────────────────────────────────────
// الديالوج بيعمل `_refreshFromDatabase()` في `initState` عبر
// `productRepositoryProvider` → `AppDatabase` حقيقية. القسمين اتلفّوا في
// دالتين top-level والإنتاج بينادي نفس الدالتين، فالاختبار بيثبت التوصيلة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/product_edit_dialog.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(home: Scaffold(body: guarded)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  const marker = Text('محتوى القسم');

  group('products_expiry — قسم إدارة الصلاحية', () {
    testWidgets('بالصلاحية: القسم ظاهر', (tester) async {
      await pump(
        tester,
        buildProductExpirySectionGuarded(child: marker),
        [PermissionCodes.productsExpiry],
      );

      final guard =
          tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.productsExpiry);
      // حقول فورم — إخفاء، مش ديالوج كلمة سر مدير (درس هـ).
      expect(guard.allowManagerOverride, isFalse);
      expect(guard.fallback, isNotNull);
      expect(find.text('محتوى القسم'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: القسم مختفي', (tester) async {
      await pump(
        tester,
        buildProductExpirySectionGuarded(child: marker),
        const [],
      );
      expect(find.text('محتوى القسم'), findsNothing);
    });
  });

  group('products_image — أزرار صورة الصنف', () {
    testWidgets('بالصلاحية: الأزرار ظاهرة', (tester) async {
      await pump(
        tester,
        buildProductImageActionsGuarded(child: marker),
        [PermissionCodes.productsImage],
      );

      final guard =
          tester.widget<PermissionGuard>(find.byType(PermissionGuard));
      expect(guard.permission, PermissionCodes.productsImage);
      expect(guard.allowManagerOverride, isFalse);
      expect(find.text('محتوى القسم'), findsOneWidget);
    });

    testWidgets('بدون الصلاحية: الأزرار مختفية', (tester) async {
      await pump(
        tester,
        buildProductImageActionsGuarded(child: marker),
        const [],
      );
      expect(find.text('محتوى القسم'), findsNothing);
    });
  });
}
