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

  test('nonToggleable فيه ٣٣ كود بالظبط (نتيجة الفرز — بكت ب+ج+د)', () {
    expect(
      PermissionCodes.nonToggleable.length,
      33,
      reason:
          'عدد الأكواد المستحيل حلّها بإنفاذ لازم يفضل ٣٣ (٢٣ بكت ب + ٨ '
          'بكت ج + ٢ بكت د) — لو اتغيّر، يبقى فيه كود اتضاف/اتشال من غير '
          'ما التريّاج يتراجع',
    );
  });

  test('knownUnenforced فيه ٤٧ كود بالظبط (مقياس تقدّم حقيقي بعد الفرز)', () {
    expect(
      PermissionEnforcementRegistry.knownUnenforced.length,
      47,
      reason:
          'الـ٤٧ دول هما اللي فعلاً لسه محتاجين إنفاذ — لو الرقم اتغيّر '
          'لازم يبقى بسبب دفعة إنفاذ حقيقية اتنفّذت (تقل) أو كود جديد '
          'اتضاف لـmasterList بلا إنفاذ (تزيد)',
    );
  });
}
