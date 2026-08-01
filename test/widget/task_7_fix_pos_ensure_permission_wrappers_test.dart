// Task 7 — fix round: الـ"seam" الأخف اللي طلبه المراجع.
//
// المراجعة الأولى لقت مشكلتين حرجتين، السبب فيهم واحد: فورك تالت
// (`TablePosScreen` — خدمة الطاولات) اتفوّت في التعداد الأول لكل من
// `pos_weight_dialog` و`pos_note_add`. بعد ما اتغطّى الفورك التالت، طلب
// المراجع كمان: بدل ما يفضل الفحص "predicate نقيّة + `if`/`toast`/`return`
// مكتوبين يدوي في نقطة الاستدعاء" (لو حد مسح سطر الـreturn بس، الاختبارات
// الـ٣٦ كلها فاضلة خضرا)، يتلمّ الكل في دالة async واحدة top-level
// (`ensureXPermission(WidgetRef, BuildContext)`) — سطر واحد في نقطة
// الاستدعاء، وأصعب إنه ينكسر جزئياً.
//
// ── ليه Consumer صغير مش شاشة كاملة ────────────────────────────────────────
// الدوال دي بتاخد `WidgetRef`/`BuildContext` حقيقيين — مش ممكن نبنيهم من
// غير widget tree خالص (WidgetRef مالوش constructor عام). الحل: نركّب
// `Consumer` واحد بس جوه `MaterialApp` فاضية (بدون أي شاشة أو DB)، نمسك
// الـref/context بتوعه، وننادي الدالة عليهم مباشرة — بالظبط الشكل اللي
// المراجع اقترحه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos/screens/pos_main_screen.dart'
    as uralcash;
import 'package:ural_erp/presentation/pos/screens/pos_table_service_screen.dart'
    as tablepos;
import 'package:ural_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:ural_erp/presentation/screens/tables_screen.dart' as tables;

void main() {
  /// يركّب `Consumer` واحد فاضي، يمسك `ref`/`context`، وينادي [call] عليهم.
  /// يرجّع النتيجة، بعد ما يسيب وقت افتراضي كافي (٣ ثواني) عشان أي مؤقّت
  /// تلقائي-الإخفاء جوّه `showPosToast`/`AppToast.show` يخلّص وما يسيبش
  /// "Timer is still pending" عند تنظيف الاختبار.
  Future<bool> runEnsure(
    WidgetTester tester,
    List<String> perms,
    Future<bool> Function(WidgetRef ref, BuildContext context) call,
  ) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              // لازم `ref.watch` هنا مش `ref.read` بس — نفس درس Task 6b:
              // من غير watch، أول قراءة لـcurrentUserPermissionsProvider جوه
              // الدالة اللي بنختبرها (تحت) بتقع وقت التحميل (AsyncLoading)
              // فترجع `[]` دايماً حتى لو الـoverride هيرجع قايمة فيها الكود.
              // في الإنتاج، ودجتات شقيقة على نفس الشاشة (PosHeader، إلخ)
              // بتعمل الـwatch ده قبل ما أي ضغطة تبقى ممكنة أصلاً.
              ref.watch(currentUserPermissionsProvider);
              capturedRef = ref;
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final result = await call(capturedRef, capturedContext);
    await tester.pump();
    // يسيب وقت افتراضي كافي لأي توست يقفل مؤقّته لوحده قبل ما الاختبار يخلص.
    await tester.pump(const Duration(seconds: 3));
    return result;
  }

  group('ensurePosWeightDialogPermission — الأفرع التلاتة', () {
    testWidgets('UralCash (pos_main_operations.dart): مرفوض بلا الكود',
        (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        uralcash.ensurePosWeightDialogPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('UralCash: مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posWeightDialog],
        uralcash.ensurePosWeightDialogPermission,
      );
      expect(result, isTrue);
    });

    testWidgets('PicPos (picpos_pos_operations.dart): مرفوض بلا الكود',
        (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        picpos.ensurePosWeightDialogPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('PicPos: مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posWeightDialog],
        picpos.ensurePosWeightDialogPermission,
      );
      expect(result, isTrue);
    });

    testWidgets(
        'خدمة الطاولات (table_pos_operations.dart) — الفورك التالت اللي '
        'فات التريَّاج الأول: مرفوض بلا الكود', (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        tablepos.ensurePosWeightDialogPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('خدمة الطاولات: مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posWeightDialog],
        tablepos.ensurePosWeightDialogPermission,
      );
      expect(result, isTrue);
    });
  });

  group('ensurePosWorkOrderPermission — موقعين', () {
    testWidgets(
        'إعادة طباعة من فاتورة سابقة (pos_main_operations.dart): مرفوض بلا الكود',
        (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        uralcash.ensurePosWorkOrderPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('إعادة طباعة من فاتورة سابقة: مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posWorkOrder],
        uralcash.ensurePosWorkOrderPermission,
      );
      expect(result, isTrue);
    });

    testWidgets('طباعة أمر شغل طاولة (table_order_dialogs.dart): مرفوض بلا الكود',
        (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        tables.ensurePosWorkOrderPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('طباعة أمر شغل طاولة: مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posWorkOrder],
        tables.ensurePosWorkOrderPermission,
      );
      expect(result, isTrue);
    });
  });

  group('ensurePosNoteAddPermission — خدمة الطاولات (مسار كتابة تاني اكتشفناه)',
      () {
    testWidgets('مرفوض بلا الكود', (tester) async {
      final result = await runEnsure(
        tester,
        const [],
        tablepos.ensurePosNoteAddPermission,
      );
      expect(result, isFalse);
    });

    testWidgets('مسموح مع الكود', (tester) async {
      final result = await runEnsure(
        tester,
        [PermissionCodes.posNoteAdd],
        tablepos.ensurePosNoteAddPermission,
      );
      expect(result, isTrue);
    });

    testWidgets('مسموح لمدير النظام حتى من غير الكود صراحة', (tester) async {
      final result = await runEnsure(
        tester,
        const ['system_admin'],
        tablepos.ensurePosNoteAddPermission,
      );
      expect(result, isTrue);
    });
  });
}
