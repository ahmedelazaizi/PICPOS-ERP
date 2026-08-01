// ═══════════════════════════════════════════════════════════════════════════
// قسم «الورديات المفتوحة على الفرع» — اللي بيعوّض الإغلاق الإجباري.
//
// إلغاء البوابة شال الآلية اللي كانت بتضمن إن مفيش وردية تتساب بلا ترصيد.
// بدل ما نمنع الكاشير، بنحطّ المسؤولية على المشرف: مين عنده `pos_shift_close`
// بيشوف كل وردية مفتوحة على الفرع باسم صاحبها ووقت فتحها، ويقفلها.
//
// ── ليه القسم في `ShiftCloseScreen` مش شاشة جديدة ─────────────────────────
// الخطة كانت بتقول `open_shifts_screen.dart` جديدة. لقيت إن `ShiftCloseScreen`
// موجودة خلاص، **مبوّبة بنفس الكود** (`ScreenId.shiftClose` →
// `pos_shift_close`) وليها عنصر قائمة «إغلاق الوردية». شاشة تانية بنفس
// الصلاحية جنبها كانت هتبقى تكرار في القائمة وفي التوصيل. القسم اتحطّ جوّه.
//
// ── ليه دالة عليا مش الشاشة كاملة ────────────────────────────────────────
// `ShiftCloseScreen` بتقرا `posClosingControllerProvider` اللي بيحسب تعداد
// الوردية المالي من قاعدة بيانات حقيقية (درس دفعة ٦أ).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/shift_close_screen.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

ShiftData _shift(int id, int userId, {DateTime? start}) => ShiftData(
      id: id,
      userId: userId,
      startTime: start ?? DateTime(2026, 8, 2, 8),
      openingBalance: 100,
      status: 'open',
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget section,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: section)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('بتعرض كل وردية مفتوحة باسم صاحبها', (tester) async {
    await pump(
      tester,
      buildOpenShiftsSection(
        shifts: [_shift(11, 1), _shift(12, 2)],
        userNames: const {1: 'أحمد', 2: 'منى'},
        currentUserId: 1,
        canCloseOthers: true,
        onClose: (_) {},
      ),
      [PermissionCodes.posShiftClose],
    );

    expect(find.textContaining('#11'), findsOneWidget);
    expect(find.textContaining('#12'), findsOneWidget);
    expect(find.textContaining('أحمد'), findsOneWidget);
    expect(find.textContaining('منى'), findsOneWidget);
  });

  testWidgets('الإغلاق محروس بـ pos_shift_close وبينفّذ للي معاه الصلاحية',
      (tester) async {
    final closed = <int>[];
    await pump(
      tester,
      buildOpenShiftsSection(
        shifts: [_shift(11, 1)],
        userNames: const {1: 'أحمد'},
        currentUserId: 1,
        canCloseOthers: true,
        onClose: (s) => closed.add(s.id),
      ),
      [PermissionCodes.posShiftClose],
    );

    final guard = tester.widget<PermissionGuard>(
      find.byType(PermissionGuard).first,
    );
    expect(guard.permission, PermissionCodes.posShiftClose);
    // درس f8d3fa9 — الحارس بيمسك الضغطة، فلازم يعرف يشغّل إيه بعد الموافقة.
    expect(guard.onGranted, isNotNull);

    await tester.tap(find.text('إغلاق الوردية'));
    await tester.pump();
    expect(closed, [11]);
  });

  testWidgets('بلا pos_shift_close → الإغلاق ما بيتنفّذش من غير موافقة مدير',
      (tester) async {
    final closed = <int>[];
    await pump(
      tester,
      buildOpenShiftsSection(
        shifts: [_shift(11, 1)],
        userNames: const {1: 'أحمد'},
        currentUserId: 1,
        canCloseOthers: true,
        onClose: (s) => closed.add(s.id),
      ),
      const [],
    );

    await tester.tap(find.text('إغلاق الوردية'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(closed, isEmpty);
    expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
  });

  testWidgets('وردية كاشير تاني: الزرار معطّل لمين مش مدير', (tester) async {
    // `PosClosingController` بيحلّ الوردية حسب `isOriginallyAdmin`: غير المدير
    // بيقفل **ورديته هو** مهما كان اللي ضغط عليه. فتفعيل الزرار على وردية
    // غيره كان هيقفل الوردية الغلط بصمت — أخطر من إنه يبقى معطّل.
    final closed = <int>[];
    await pump(
      tester,
      buildOpenShiftsSection(
        shifts: [_shift(12, 2)],
        userNames: const {2: 'منى'},
        currentUserId: 1,
        canCloseOthers: false,
        onClose: (s) => closed.add(s.id),
      ),
      [PermissionCodes.posShiftClose],
    );

    await tester.tap(find.text('إغلاق الوردية'), warnIfMissed: false);
    await tester.pump();
    expect(closed, isEmpty);
    expect(find.textContaining('مدير النظام'), findsOneWidget,
        reason: 'لازم يتقال ليه الزرار مقفول بدل ما يبقى ميت بلا سبب');
  });

  testWidgets('مفيش ورديات مفتوحة → حالة فاضية واضحة', (tester) async {
    await pump(
      tester,
      buildOpenShiftsSection(
        shifts: const [],
        userNames: const {},
        currentUserId: 1,
        canCloseOthers: true,
        onClose: (_) {},
      ),
      [PermissionCodes.posShiftClose],
    );

    expect(find.textContaining('لا توجد ورديات مفتوحة'), findsOneWidget);
  });
}
