// test/unit/permission_nontoggleable_registry_test.dart
//
// `PermissionCodes.nonToggleable` و`PermissionEnforcementRegistry.
// knownUnenforced` لازم يفضلوا مجموعتين منفصلتين تماماً: كود واحد إما لسه
// محتاج إنفاذ (knownUnenforced) وإما مستحيل يتحلّ بإنفاذ (nonToggleable) —
// مش الاتنين مع بعض (Task 5، 2026-08-01).
//
// الاكتمال (إن كل كود بلا إنفاذ حقيقي موجود في واحدة من المجموعتين، ومفيش
// كود ضايع من التتبّع بالكامل) بيتفحص في
// `permission_enforcement_coverage_test.dart` اللي بيمسح `lib/` فعلياً.
// الاختبار ده بيركّز على حاجة تانية: إن المجموعتين ما بيتقاطعوش، وإن حجمهم
// ثابت كنتيجة معروفة للفرز — لو كود اتشال من واحدة من غير ما يتضاف
// للتانية بالسبب الصحيح، بيختفي من التتبّع بالكامل، وده بالظبط نوع
// الانزلاق اللي خلّى ٨٠ كود يفضلوا من غير رقابة لحدّ ما حصل السويب.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/core/permissions/permission_enforcement_registry.dart';

void main() {
  test('nonToggleable و knownUnenforced ما بيتقاطعوش', () {
    final nonToggleable = PermissionCodes.nonToggleable.keys.toSet();
    const knownUnenforced = PermissionEnforcementRegistry.knownUnenforced;

    final overlap = nonToggleable.intersection(knownUnenforced).toList()
      ..sort();

    expect(
      overlap,
      isEmpty,
      reason:
          'أكواد مسجّلة في المجموعتين مع بعض — كل كود لازم يبقى في واحدة '
          'بس (إما لسه محتاج إنفاذ، أو مستحيل يتحلّ):\n'
          '${overlap.join('\n')}',
    );
  });

  // ٣٣ (الفرز) → ٣٤ (دفعة ١١: `dashboard_sales_total` اتنقل هنا لأن مفيش
  // كارت «إجمالي مبيعات» منفصل — نفس كارت `dashboard_sales_today` بفلتر
  // فترة أوسع، فتشغيله كان هيتطلّب اختراع ودجت جديدة).
  test('nonToggleable فيه ٣٤ كود بالظبط (نتيجة الفرز — بكت ب+ج+د)', () {
    expect(
      PermissionCodes.nonToggleable.length,
      34,
      reason:
          'عدد الأكواد المستحيل حلّها بإنفاذ لازم يفضل ٣٤ (٢٣ بكت ب + ٨ '
          'بكت ج + ٢ بكت د + dashboard_sales_total من دفعة ١١) — لو اتغيّر، '
          'يبقى فيه كود اتضاف/اتشال من غير ما التريّاج يتراجع',
    );
  });

  // مسار الانكماش (كل رقم = دفعة إنفاذ حقيقية اتنفّذت):
  //   ٤٧ (الفرز، Task 5) → ٤٠ (٦أ) → ٣٣ (٦ب) → ٢٥ (٧) → ١٩ (٨: الأصناف)
  //   → ١٣ (٩: المستندات والطباعة) → ٧ (١٠: الإعدادات والنظام)
  //   → ٣ (١١: لوحة التحكم — ٣ اتنفّذوا وواحد اتنقل لـnonToggleable)
  //
  // الرقم ده كان فاضل ٤٧ من Task 5 لحد دفعة ٨ — يعني الاختبار كان أحمر من
  // غير ما حد ياخد باله عبر تلات دفعات، لأن الدفعات كانت بتشغّل اختباراتها
  // المستهدفة بس والبوابة الكاملة اتأجّلت. الدرس: أي دفعة بتشيل من السجل
  // لازم تحدّث الرقم ده في نفس الكوميت.
  test('knownUnenforced فيه ٣ أكواد بالظبط (مقياس تقدّم حقيقي بعد الفرز)', () {
    expect(
      PermissionEnforcementRegistry.knownUnenforced.length,
      3,
      reason:
          'التلاتة دول هما اللي فعلاً لسه محتاجين إنفاذ — لو الرقم اتغيّر '
          'لازم يبقى بسبب دفعة إنفاذ حقيقية اتنفّذت (تقل) أو كود جديد '
          'اتضاف لـmasterList بلا إنفاذ (تزيد)',
    );
  });
}
