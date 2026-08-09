// ═══════════════════════════════════════════════════════════════════════════
// حارسُ دخانٍ لشاشات التقارير — تُفتَح فتُرسَم، بلا استثناءٍ وبلا فيضان.
// ═══════════════════════════════════════════════════════════════════════════
//
// كانت تغطيةُ الواجهات مركّزةً على الصلاحيات والورديات، ولا اختبارَ **يفتح**
// شاشةَ تقريرٍ أصلاً. فعطلُ التخطيط أو استثناءُ البناء لا يظهر إلا للمستخدم.
// ومقيسٌ أن الفئة حقيقية: فيضانٌ أفقيٌّ في رأس `report_builder_screen`
// اكتُشف بالمصادفة 2026-08-09 لأن اختباراً فتح الشاشة لأوّل مرة.
//
// ── ما يفحصه ─────────────────────────────────────────────────────────────
// أن الشاشة **تُرسَم**: لا استثناءَ في البناء ولا `RenderFlex overflow`.
// لا يفحص صحّةَ الأرقام — لذلك سويّاتُ الوحدات.
//
// ── والمقاسُ مكتبيٌّ عن قصد ────────────────────────────────────────────────
// المقاسُ الافتراضيّ ٨٠٠×٦٠٠، وخطُّ الاختبار يرسم كلَّ محرفٍ مربّعاً كاملَ
// العرض فيخرج النصُّ العربيُّ أعرضَ من الواقع ويولّد فيضاناتٍ **وهمية**.
// وهذه الشاشات تعمل على سطح مكتب، فالقياسُ عند ١٩٢٠×١٠٨٠.
//
// ⚠️ ومع ذلك يبقى الخطُّ متضخّماً: فيضانٌ صغير (عشراتُ البكسلات) هنا **مشتبهٌ
//    به لا مؤكَّد**، ويحتاج تأكيداً بخطٍّ حقيقيّ قبل تعديل التخطيط.
//
// ═══════════════════════════════════════════════════════════════════════════
// 🔴 لماذا أربعُ شاشاتٍ من خمسَ عشرة — مانعٌ مقيسٌ لم يُحَلّ بعد
// ═══════════════════════════════════════════════════════════════════════════
// الإحدى عشرةُ الباقية (‏CategoryProfit · Delivery · Expenses · Inventory ·
// Purchases · Sales · Shifts · Tax · TopProducts · Treasury · VatReconciliation)
// **لا تفشل في الرسم**. المقيس بالتشخيص 2026-08-09:
//
//   • جسمُ الاختبار **ينتهي كاملاً** في كلّ الحالات (‏`pumpWidget` وحدَه، أو
//     مع `pump()`، أو مع `pump(7s)`) — وطُبع ذلك صراحةً.
//   • ثم تنتهي المهلةُ **بعد** الجسم ⇒ التعليقُ في تفكيك `testWidgets`،
//     ينتظر عملاً غير متزامنٍ تتركه الشاشةُ حيّاً.
//   • لا يحلُّه تفكيكُ الشجرة صراحةً (`pumpWidget(SizedBox())`) ولا
//     `runAsync` — كلاهما جُرّب وفشل.
//   • ولا يميّز الأربعَ عن الإحدى عشرة أيُّ تبعيةٍ بعينها: نسبةُ استعمال
//     `BranchWarehouseFilterBar` و`branchScopeProvider` و`Future.microtask`
//     متقاربةٌ في المجموعتين.
//
// فالمانعُ **تجهيزةٌ ناقصة لا عطلُ منتج**، ولا يجوز عدُّ فشله دليلَ خلل.
// الخطوةُ التالية: تعقّبُ المهمة المعلّقة (‏`debugPrintScheduleFrameStacks`
// أو تغليفُ الشاشة بمنطقةٍ تُحصي المهام غير المنتهية) ثم توسيعُ القائمة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/reports/ar_aging_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/consumption_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/purchase_returns_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/sales_returns_report_screen.dart';

/// شاشاتُ التقارير التي تُفتَح وتُفكَّك نظيفةً في بيئة الاختبار اليوم.
///
/// ⚠️ القائمةُ يدويةٌ لأن Dart لا يعدّد الأصناف وقت التشغيل. وهي **ليست**
/// كلَّ شاشات التقارير — انظر المانعَ أعلاه.
final Map<String, Widget Function()> smokeableReportScreens = {
  'ArAgingReportScreen': () => const ArAgingReportScreen(),
  'ConsumptionReportScreen': () => const ConsumptionReportScreen(),
  'PurchaseReturnsReportScreen': () => const PurchaseReturnsReportScreen(),
  'SalesReturnsReportScreen': () => const SalesReturnsReportScreen(),
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  for (final entry in smokeableReportScreens.entries) {
    testWidgets('${entry.key} تُرسَم بلا استثناءٍ ولا فيضان',
        timeout: const Timeout(Duration(seconds: 45)), (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: entry.value()),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // ‏`pumpWidget` يبتلع استثناءَ البناء ويُسجّله، فالفحصُ صريح. والفيضانُ
      // يُسجَّل بنفس الطريقة، فهذا السطرُ يمسك الاثنين.
      expect(tester.takeException(), isNull,
          reason: 'الشاشةُ رمت أو فاضت أثناء البناء — يراها المستخدمُ '
              'شاشةً حمراء أو شريطاً مقصوصاً');
    });
  }
}
