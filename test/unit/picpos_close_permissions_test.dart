// من يُغلق الوردية حين تُدمج البطاقةُ وكلمةُ المرور في مدخلٍ واحد.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «الإغلاقُ بالبطاقة أو الباسورد — دمجٌ بكبسةٍ واحدة.»
//
// ── وثغرةٌ مقيسةٌ يسدّها الدمج ─────────────────────────────────────────────
// المسارانِ اليومَ غيرُ متماثلَين في `pos_closing_controller.dart:472-508`:
//   • `msr_card` ينادي `authenticateByPasswordOrCard` ويقبل **أيَّ** مستخدمٍ
//     مسجَّل — بلا أيّ فحصِ دورٍ أو صلاحية.
//   • `admin_password` وحدَه يفحص أن صاحبَه مديرٌ فعلاً.
// أيْ أن بطاقةَ أيّ كاشيرٍ تُغلق الورديةَ بفرقٍ صفر. وقرارُ المالك بين
// ثلاثةِ خيارات كان «مديرٌ **أو من يملك صلاحية الإغلاق**» — فالمدخلُ
// الموحَّدُ يفحص `pos_shift_close`، لا وجودَ المستخدم فحسب.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/shift_close_picpos/widgets/picpos_close_permissions.dart';

void main() {
  test('من يملك pos_shift_close يُغلق', () {
    expect(
      canCloseShiftCodes(const [PermissionCodes.posShiftClose]),
      isTrue,
    );
  });

  test('ومديرُ النظام يمرّ بلا كودٍ صريح', () {
    expect(canCloseShiftCodes(const ['system_admin']), isTrue);
    expect(canCloseShiftCodes(const ['*']), isTrue);
  });

  test('وكاشيرٌ بلا الصلاحية لا يُغلق — وهي الثغرةُ التي سدّها الدمج', () {
    // قبلَه: بطاقتُه تمرّ في مسار `msr_card` بلا أيّ فحص.
    expect(
      canCloseShiftCodes(const [
        PermissionCodes.posAccess,
        PermissionCodes.posSave,
      ]),
      isFalse,
    );
  });

  test('ولا قائمةٌ فارغة', () {
    expect(canCloseShiftCodes(const []), isFalse);
  });
}
