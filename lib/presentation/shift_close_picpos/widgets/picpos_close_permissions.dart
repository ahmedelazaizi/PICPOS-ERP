// من يُغلق الوردية — قرارٌ خالص.
//
// طلبُ المالك 2026-08-14: دمجُ «بطاقة MSR» و«كلمة مرور المدير» في مدخلٍ
// واحد، ومن يقبله: **مديرٌ أو من يملك صلاحية الإغلاق**.
//
// ── الثغرةُ التي يسدُّها ──────────────────────────────────────────────────
// مسارُ `msr_card` كان ينادي `authenticateByPasswordOrCard` ويقبل أيَّ
// مستخدمٍ مسجَّل بلا فحصِ دورٍ ولا صلاحية، بينما `admin_password` يفحص أن
// صاحبَه مدير. فبطاقةُ أيّ كاشيرٍ كانت تُغلق الورديةَ بفرقٍ صفر — وهو نقضٌ
// لطلبِ المالك نفسِه في §٣ («المديرُ هو من يجرد»).

import '../../../core/permissions/permission_codes.dart';

/// هل يملك صاحبُ [permissions] إغلاقَ الوردية؟
///
/// `pos_shift_close` ليس من `criticalFinancialOps`، فتخطّي مدير النظام
/// مُعادٌ بالحرف كما في `PermissionGuard`.
bool canCloseShiftCodes(List<String> permissions) =>
    permissions.contains('system_admin') ||
    permissions.contains('*') ||
    permissions.contains(PermissionCodes.posShiftClose);
