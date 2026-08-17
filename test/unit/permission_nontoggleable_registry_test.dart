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
  // ٣٤ → ٣٣ (Task 8، 2026-08-16: `tables_print_bill` خرج من هنا — الميزةُ
  // بقت مخطَّطةً في المهمتين ٩ و١٠ بدل ما تفضل مستحيلة، فصار مكانُه
  // `PermissionEnforcementRegistry.knownUnenforced` لحدّ ما يُبنى الإنفاذ).
  test('nonToggleable فيه ٣٣ كود بالظبط (نتيجة الفرز — بكت ب+ج+د، ناقص Task 8)',
      () {
    expect(
      PermissionCodes.nonToggleable.length,
      33,
      reason:
          'عدد الأكواد المستحيل حلّها بإنفاذ لازم يفضل ٣٣ (٢٣ بكت ب + ٨ '
          'بكت ج + ٢ بكت د + dashboard_sales_total من دفعة ١١، ناقص '
          'tables_print_bill اللي خرج من هنا في Task 8) — لو اتغيّر، يبقى '
          'فيه كود اتضاف/اتشال من غير ما التريّاج يتراجع',
    );
  });

  // مسار الانكماش (كل رقم = دفعة إنفاذ حقيقية اتنفّذت):
  //   ٤٧ (الفرز، Task 5) → ٤٠ (٦أ) → ٣٣ (٦ب) → ٢٥ (٧) → ١٩ (٨: الأصناف)
  //   → ١٣ (٩: المستندات والطباعة) → ٧ (١٠: الإعدادات والنظام)
  //   → ٣ (١١: لوحة التحكم — ٣ اتنفّذوا وواحد اتنقل لـnonToggleable)
  //   → ٠ (١٢: التقارير — آخر تلات أكواد في السجل)
  //
  // الرقم ده كان فاضل ٤٧ من Task 5 لحد دفعة ٨ — يعني الاختبار كان أحمر من
  // غير ما حد ياخد باله عبر تلات دفعات، لأن الدفعات كانت بتشغّل اختباراتها
  // المستهدفة بس والبوابة الكاملة اتأجّلت. الدرس: أي دفعة بتشيل من السجل
  // لازم تحدّث الرقم ده في نفس الكوميت.
  // خلص فاضياً بدفعة ١٢. Task 8 (2026-08-16) ضاف كودين جداد لـmasterList
  // (تصنيف الطاولات) بلا إنفاذ بعد — مش بقية شغل قديم: 'tables_discount'
  // (زرّ الخصم لسه ما بُنيش، تبنيه المهامّ ٩-١٢) و'tables_print_bill'
  // (خرج من nonToggleable لأن الميزة بقت مخطَّطة في المهمتين ٩ و١٠). لاحظ
  // إن السجل مش مقياس كافي لـ«الصلاحية شغّالة»: باج المحرك d01fdfdc خلّى
  // treasury_balance_view و dashboard_profit ما يخبّوش حاجة وهما مش في
  // السجل أصلاً.
  // ٢ → ١ (مراجعةُ ما قبل الدمج، 2026-08-17): 'tables_print_bill' خرج —
  // كبسةُ «طباعة الفاتورة» بقت موصولةً بفحصٍ صريحٍ ثم
  // `TableSessionService.requestBill` والطباعة، بدل توست «قيدُ الإنجاز».
  // فاضل 'tables_discount' وحده: زرُّ الخصم لسه ما بُنيش في واجهة الطاولات.
  test('knownUnenforced فيه كودُ خصم الطاولة وحده', () {
    expect(
      PermissionEnforcementRegistry.knownUnenforced,
      {'tables_discount'},
      reason:
          'السجل المتوقَّع يقتصر على كودِ خصم الطاولة لحدّ ما يُبنى زرُّه '
          'ويُوصَل بالإنفاذ. لو ظهر كودٌ تانٍ أو اختفى ده، يبقى فيه تغيير '
          'غير متوقَّع محتاج مراجعة.',
    );
  });
}
