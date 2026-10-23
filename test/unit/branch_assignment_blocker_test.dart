// تجهيزةُ المستخدمِ التي تُنتج نطاقاً فارغاً — قرارٌ خالصٌ قابلٌ للقياس.
//
// ── العطبُ الذي وُلدت منه (مقيسٌ 2026-08-23) ────────────────────────────────
// حوارُ «إضافة مستخدم» يبدأ على «كل الفروع (مدير / إدارة)»، وهذا الخيارُ
// **لا يكتب صفَّ إسنادٍ واحداً**. والفراغُ يعني «الكلَّ» لمديرِ النظام
// والمديرِ الماليّ وحدَهما؛ ولغيرِهما يعني `no-assignments-fail-closed` —
// أي **لا يرى شيئاً**.
//
// فكاشيرٌ أُنشئ على الافتراض يبيع فعلاً (فرعُ الفاتورة يُشتقّ من المخزن)
// ثمّ لا يرى ما باع (النطاقُ يُشتقّ من إسناداته). وهو ما وقع فعلاً لحساب
// `userId=2` في سجلّ 2026-08-22: `allowed=[] ⚠ EMPTY SCOPE`.
//
// فالمنعُ من أصله أرخصُ من معالجةِ أثره — وهذا الملفُّ يقيس القرار.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/branch_assignment_scope.dart';

void main() {
  group('«كل الفروع» لغيرِ المميَّز تجهيزةٌ ناقصة', () {
    test('دورٌ مميَّزٌ مع «كل الفروع» ⇒ سليم', () {
      expect(
        branchAssignmentBlocker(
          roleHasFullBranchAccess: true,
          allBranchesChosen: true,
          selectedBranchCount: 0,
        ),
        isNull,
        reason: 'الفراغُ لمديرِ النظام يعني الكلَّ فعلاً',
      );
    });

    test('دورٌ غيرُ مميَّزٍ مع «كل الفروع» ⇒ يُمنَع ويُسمّى البديل', () {
      final msg = branchAssignmentBlocker(
        roleHasFullBranchAccess: false,
        allBranchesChosen: true,
        selectedBranchCount: 0,
      );
      expect(msg, isNotNull);
      expect(msg, contains('فرع محدد'),
          reason: 'المنعُ يقول ماذا يفعل المستخدمُ لا «غير مسموح» وحدَها');
    });

    test('دورٌ غيرُ مميَّزٍ مع «فرع محدد» وبلا اختيار ⇒ يُمنَع', () {
      expect(
        branchAssignmentBlocker(
          roleHasFullBranchAccess: false,
          allBranchesChosen: false,
          selectedBranchCount: 0,
        ),
        isNotNull,
      );
    });

    test('دورٌ غيرُ مميَّزٍ مع فرعٍ واحدٍ ⇒ سليم', () {
      expect(
        branchAssignmentBlocker(
          roleHasFullBranchAccess: false,
          allBranchesChosen: false,
          selectedBranchCount: 1,
        ),
        isNull,
      );
    });
  });

  group('قاعدةُ الامتياز', () {
    test('الاسمان المميَّزان هما نفسُهما في توأم القاعدة', () {
      // ⚠️ توأمُ `UserDao.isFullBranchAccessUser` — والقاعدةُ مكرّرةٌ هناك
      // بالحرف. انحرافُ أحدِهما يعطي منتقياً يأذن بما يرفضه المزوِّد.
      expect(fullBranchAccessRoleNames, {'مدير النظام', 'مدير مالي'});
    });
  });
}
