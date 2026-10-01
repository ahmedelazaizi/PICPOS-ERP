// حارسُ العقد: سببُ المردود يصل **صفَّ المستند** — لا يموت في الودجت.
//
// ═══ فئةُ العطب — وهي مقيسةٌ لا مفترضة ═══
//
// قبل هذا العمل كانت القائمةُ موجودةً على الشاشة وتُملأ فعلاً، وتُخزَّن في
// `_selectedReasonCategory` و`_returnReasonController` — **حالةٌ محلّيّةٌ لا
// تغادر الودجت**. و`processReturn` لا يقرأهما، و`PurchaseReturns.reason`
// عمودٌ قائمٌ **بلا كاتبٍ واحدٍ** في المستودع كلّه.
//
// فالمستخدمُ يختار سبباً كلَّ مرّة، ولا يُسأل عنه أحدٌ أبداً — وهي بعينها
// عائلةُ «بُني ولم يُوصَل» المسجّلةُ في هذا المستودع ثلاثَ مرّات:
// رايةُ `table_bill_guest_order_enabled` · `InvoiceCurrencySelector` ·
// `Payments` + `PaymentAllocations`.
//
// ⚠️ **والسلسلةُ خمسُ حلقاتٍ لا واحدة**، وانقطاعُ أيٍّ منها يُعيد الحقلَ
// ميّتاً وكلُّ اختبارِ واجهةٍ أخضر: القائمةُ ← المزوّد ← المستودع ← القُمع
// (`autoPostPurchaseReturn`) ← صفُّ `PurchaseReturns`. وحلقةٌ سادسةٌ للعميل:
// حمولةُ الإرسال، وبدونها يموت الحقلُ على **كلّ** جهاز عميل — وهي أكثرُ
// التنصيبات.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

/// نصُّ الملفّ بلا أسطر التعليق، **وبلا `\r`**: الملفّاتُ هنا CRLF، فمرساةٌ
/// متعدّدةُ الأسطر مكتوبةٌ بـ`\n` لا تطابق شيئاً — وصمتُ عدمِ المطابقة يمرّ
/// أخضرَ في فحصٍ سلبيٍّ ويسقط في إيجابيّ. وقع فعلاً في أوّل تشغيلٍ لهذا
/// الحارس.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

// المرحلة C2: الاستمارةُ المعاد تصميمُها حلّت محلَّ لوح التفاصيل
// (`purchase_returns_picpos_details.dart`) — والسلسلةُ نفسُها تُحرَس فيها.
const _detailsPath =
    'lib/presentation/purchase_returns_picpos/screens/'
    'purchase_returns_picpos_form.dart';
const _providerPath = 'lib/presentation/providers/purchase_return_provider.dart';
const _repoPath = 'lib/data/repositories/purchases_repository_impl.dart';
const _autopostPath = 'lib/data/database/daos/accounting_autopost_dao.dart';

void main() {
  test('القائمةُ هي الأربعةُ التي أقرّها المالك — ولا «أخرى»', () {
    expect(AppConstants.purchaseReturnReasons, const [
      'عيب في المنتج',
      'خطأ في الطلب',
      'انتهاء صلاحية',
      'فائض',
    ]);
    // ⚠️ «أخرى» تُعيد النصَّ الحرَّ من الباب الخلفيّ، فيصير التصنيفُ غيرَ
    // قابلٍ للتجميع — وهو الغرضُ الوحيدُ من إغلاق القائمة.
    expect(AppConstants.purchaseReturnReasons.contains('أخرى'), isFalse);
  });

  test('ومستقلّةٌ عن قائمة مردود المبيعات', () {
    // تلك تحمل «تغيير رأي العميل» — سببٌ لا معنى له في ردٍّ إلى مورّد.
    expect(
      AppConstants.purchaseReturnReasons,
      isNot(equals(AppConstants.returnReasonCategories)),
    );
    expect(AppConstants.returnReasonCategories.contains('تغيير رأي العميل'),
        isTrue,
        reason: 'قائمةُ المبيعات تغيّرت — راجع أنّ القرارَ لم يمسّها');
  });

  test('والشاشةُ تقرأ القائمةَ الجديدة وتُبلِّغ المزوّد', () {
    final ui = _code(_detailsPath);
    expect(ui.contains('AppConstants.purchaseReturnReasons'), isTrue,
        reason: 'الشاشةُ ما زالت تعرض قائمةَ المبيعات');
    expect(ui.contains('notifier.updateReturnReason'), isTrue,
        reason: 'الاختيارُ لا يغادر الودجت — وهو عينُ العطب الأصليّ');
    expect(ui.contains('_selectedReasonCategory'), isFalse,
        reason: 'الحالةُ المحلّيّةُ الميّتةُ عادت');
  });

  test('والزرُّ لا يُنفَّذ بلا سبب', () {
    final ui = _code(_detailsPath);
    expect(ui.contains('state.returnReason != null'), isTrue,
        reason: 'القرارُ أنّ السببَ **إلزاميّ** — وبلا بوّابةٍ يمرّ فارغاً');
  });

  test('والمزوّدُ يمرّره إلى المستودع', () {
    expect(_code(_providerPath).contains('reason: state.returnReason'), isTrue,
        reason: 'السببُ يُحفَظ في الحالة ولا يُرسَل');
  });

  test('والمستودعُ يمرّره إلى القُمع — وفي حمولة العميل معاً', () {
    final repo = _code(_repoPath);
    expect(repo.contains('reason: reason'), isTrue,
        reason: 'المسارُ المحلّيُّ لا يمرّر السبب');
    expect(repo.contains("'reason': reason"), isTrue,
        reason: 'حمولةُ العميل بلا سبب — فيموت الحقلُ على كلّ جهاز عميل، '
            'وهي أكثرُ التنصيبات');
  });

  test('والقُمعُ يكتبه في صفّ المستند', () {
    // ⚠️ **في جسم الدالّة لا في الملفّ**: `reason` رمزٌ شائعٌ، ووجودُه في
    // ملفٍّ بحجم هذا لا يقول شيئاً.
    final code = _code(_autopostPath);
    final at = code.indexOf('PurchaseReturnsCompanion.insert(');
    expect(at, greaterThan(0), reason: 'صفُّ المستند ما عاد يُكتَب أصلاً');
    final body = code.substring(at, code.indexOf('),\n    );', at));
    expect(body.contains('reason: Value(reason)'), isTrue,
        reason: 'القُمعُ يستقبل السببَ ولا يكتبه — الحلقةُ الأخيرةُ مقطوعة، '
            'وكلُّ ما قبلها يبدو سليماً');
  });

  test('ومرساةُ العمود — `reason` ما زال في الجدول', () {
    final table = _code('lib/data/database/tables/sales_purchase_tables.dart');
    final at = table.indexOf('class PurchaseReturns extends Table {');
    expect(at, greaterThan(0));
    final body = table.substring(at, table.indexOf('\n}', at));
    expect(body.contains('TextColumn get reason'), isTrue,
        reason: 'العمودُ حُذف — فالسلسلةُ كلُّها تكتب في العدم');
  });
}
