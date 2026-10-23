// حارسُ العقد: **سندا القبض والصرف — مسارُ مالٍ منقولٌ وشيكٌ بمبلغه.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **لا قسمةَ بالتساوي على الشيكات.** الحواران يكتبان
//    `amount / count`، فثلاثةُ شيكاتٍ بـ١٠٠٠ و٢٠٠٠ و٣٠٠٠ تُكتَب ٢٠٠٠
//    و٢٠٠٠ و٢٠٠٠ في `commercial_papers`. والمجموعُ صحيحٌ فلا شيءَ يبدو
//    معطوباً — حتى يحين تحصيلُ أوّلِ شيكٍ فيُقيَّد بمبلغٍ لم يُكتَب على
//    الورقة، أو يرتدّ بمبلغٍ مخترَع.
//
// ‏٢) 🔴 **وإصلاحاتُ المسار منقولةٌ لا مُعادةُ الكتابة**: فحصُ مواصفة ١٣٣
//    قبل أيّ كتابة · المعرّفُ العامُّ المشترَك · فرعُ المشغِّل · وإسقاطُ
//    الخزنة للشيك في سند الصرف.
//
// ‏٣) 🔴 **والتوزيعُ لا يُكتَب في وضع العميل**: المعرّفاتُ محلّيّةٌ
//    والاستراتيجيّتان تكتبان بمعرّفات الخادم عبر `insertOnConflictUpdate`.
//
// ‏٤) **والتوصيلُ ستّةُ مواضعَ لكلٍّ منهما.**

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';

String _code(String path) => [
  for (final line in readLibrarySource(path).split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

const _form =
    'lib/presentation/treasury_picpos/screens/voucher_form_picpos.dart';
const _receipt =
    'lib/presentation/treasury_picpos/screens/receipt_voucher_picpos_screen.dart';
const _payment =
    'lib/presentation/treasury_picpos/screens/payment_voucher_picpos_screen.dart';

void main() {
  test('🔴 لا قسمةَ بالتساوي على الشيكات في الشاشتَين', () {
    for (final f in [_receipt, _payment]) {
      final code = _code(f);
      // 🔴 **يُعَدُّ الأثرُ لا يُنفى الإملاء.** أوّلُ صيغةٍ كانت
      //    `contains('/ count')` — **ونجت منها** طفرةُ
      //    `v.grossAmount / v.cheques.length`: قسمةٌ بالتساوي بإملاءٍ آخر،
      //    و`amount: c.amount` يبقى مكتوباً في الكتابة الثانية فيبدو
      //    كلُّ شيءٍ سليماً.
      //
      //    والكتابةُ **مزدوجةٌ** (الخادمُ ثمّ المحلّيُّ بنفس المعرّف)، فكلُّ
      //    ملفٍّ يقرأ مبلغَ الشيك **مرّتين**. وواحدةٌ تكفي لتخرج الورقةُ
      //    إلى الخادم بمبلغٍ ومحلّيّاً بآخر.
      expect(
        _count(code, 'amount: c.amount'),
        2,
        reason:
            '🔴 كتابةٌ من الكتابتَين لا تقرأ مبلغَ الشيك في $f — '
            'فثلاثةُ شيكاتٍ بـ١٠٠٠ و٢٠٠٠ و٣٠٠٠ تُكتَب ٢٠٠٠ لكلٍّ منها، '
            'ثمّ يُحصَّل أوّلُها بمبلغٍ لم يُكتَب على الورقة',
      );
      expect(
        code.contains('/ count'),
        isFalse,
        reason: 'قسمةٌ بالتساوي بإملائها القديم في $f',
      );
    }
    // والنموذجُ يشتقّ الإجماليَّ من الشيكات لا العكس.
    expect(_code(_form).contains('double get _chequesTotal'), isTrue);
  });

  test('🔴 وإصلاحاتُ المسار منقولةٌ', () {
    final receipt = _code(_receipt);
    // مواصفة ١٣٣ — الفحصُ **قبل** أيّ كتابة.
    expect(
      receipt.contains('ChequeReceiptPreflight.validate('),
      isTrue,
      reason:
          '🔴 بلا الفحص: أوراقُ القبض غيرُ مربوطةٍ ⇒ قيدُ صفرٍ صامتٌ '
          'يترك العميلَ مديناً بلا إشارة',
    );
    // Issue 12 — معرّفٌ واحدٌ للكتابتَين.
    expect(
      receipt.contains('globalId: sharedGlobalId'),
      isTrue,
      reason: '🔴 معرّفان ⇒ يرى الكاشيرُ السندَ مرّتين بعد المزامنة',
    );
    expect(
      _count(receipt, 'sharedGlobalId'),
      greaterThanOrEqualTo(3),
      reason: 'المعرّفُ لا يصل الكتابتَين معاً',
    );

    for (final f in [_receipt, _payment]) {
      expect(
        _code(f).contains('activeBranchIdProvider'),
        isTrue,
        reason:
            '🔴 مواصفة ١٣٥ BUG-C: السندُ يُنسَب لفرع الخزنة بدل فرع '
            'المشغِّل في $f',
      );
    }

    // 🔴 سندُ الصرف يُسقط الخزنةَ للشيك — وإلّا خرجت نقديّةٌ مرّتين.
    final payment = _code(_payment);
    // E-fix ١ — نداءُ الخادم صار `ClientVoucherInterceptor.submit` ويمرّر
    // خزنةَ المستند للتحويل، فيُعَدّ الشرطُ نفسُه لا بادئةُ الوسيط.
    expect(
      _count(payment, "v.method == 'check' ? null : v.safeId"),
      2,
      reason:
          '🔴 مسارٌ من المسارَين يمرّر الخزنةَ للشيك — والقيدُ يملكه '
          'ترحيلُ الأوراق التجارية، فتخرج النقديّةُ مرّتين',
    );
  });

  test('🔴 والتوزيعُ لا يُكتَب في وضع العميل', () {
    for (final f in [_receipt, _payment]) {
      final code = _code(f);
      // 🔴 **الشرطُ نفسُه لا اسمُه.** أوّلُ صيغةٍ كانت
      //    `contains('interceptedByServer')` — **ونجت منها** طفرةُ
      //    `if (interceptedByServer && false)`: الاسمُ باقٍ والفرعُ ميّت.
      expect(
        _count(code, 'if (interceptedByServer) {'),
        1,
        reason:
            '🔴 التوزيعُ من جهازٍ عميلٍ يسكّ معرّفاتٍ محلّيّةً تصادم '
            'معرّفاتِ الخادم عند السحب فتُستبدَل صامتاً — في $f',
      );
      expect(
        code.contains('return;'),
        isTrue,
        reason: 'الحارسُ لا يرتدّ فعلاً في $f',
      );
      expect(
        code.contains('recordVoucherAllocations('),
        isTrue,
        reason: 'لوحُ التوزيع لا يكتب شيئاً في $f',
      );
    }
  });

  test('🔴 و«أودِعه فوراً» ينقل الحالةَ بقيدها', () {
    final code = _code(_receipt);
    // 🔴 **مربّعٌ يُعرَض ولا ينقل حالةً هو وعدٌ كاذب.** المحرّكُ يُنشئ
    //    الورقةَ عند `pending` ويقيّد أوراقَ القبض؛ والإيداعُ حالةٌ تاليةٌ
    //    لها قيدُها. وطفرةُ `if (v.depositImmediately && false)` نجت من
    //    أوّل صياغةٍ لهذا الملفّ: الفحوصُ كانت تقيس **ظهورَ** المربّع وحدَه.
    expect(
      _count(code, 'if (v.depositImmediately) {'),
      1,
      reason:
          '🔴 المربّعُ يُعرَض ولا يفعل — ويبقى الشيكُ برسم التحصيل '
          'والمستخدمُ يظنّه مودعاً',
    );
    expect(
      code.contains("'deposited'"),
      isTrue,
      reason: 'الانتقالُ لا يُطلَب أصلاً',
    );
    expect(
      code.contains('updatePaperStatus('),
      isTrue,
      reason: 'الحالةُ تُكتَب بيدٍ بدل المسار الذي يقيّد الانتقال',
    );
    // ⚠️ ولا تُزيَّف الحالةُ عند الإنشاء: `createPaper` بلا `status`.
    expect(
      code.contains("status: 'deposited'"),
      isFalse,
      reason:
          '🔴 زيفُ الحالة عند الإنشاء يُظهر الشيكَ مودعاً ولا قيدَ '
          'يقابله',
    );
  });

  test('⚠️ ولا زرَّ مسوّدةٍ في النموذج', () {
    final code = _code(_form);
    expect(
      code.contains('draft:'),
      isFalse,
      reason:
          '⚠️ لا حالةَ مسوّدةٍ في المحرّك (`SafeTransactions` بلا عمود '
          'حالة، و`createReceiptVoucher` بلا `asDraft`) — وزرٌّ يحفظ '
          'مُرحَّلاً وهو يقول «مسودة» يوهم بتأجيل حركةِ مال',
    );
    expect(
      code.contains('kVoucherNumberPlaceholder'),
      isTrue,
      reason: '🔴 رقمٌ مخمَّنٌ على الترويسة — والمولّدُ داخلَ معاملة الحفظ',
    );
  });

  group('والتوصيلُ ستّةُ مواضعَ لكلٍّ منهما', () {
    const expected = <ScreenId, ({int index, String label, AppScreen screen})>{
      ScreenId.receiptVoucher: (
        index: 68,
        label: 'سند قبض',
        screen: AppScreen.receiptVoucher,
      ),
      ScreenId.paymentVoucher: (
        index: 69,
        label: 'سند صرف',
        screen: AppScreen.paymentVoucher,
      ),
    };

    expected.forEach((id, e) {
      test('«${e.label}»', () {
        expect(id.navigationIndex, e.index);
        expect(e.screen.value, id.navigationIndex);
        // ⚠️ **`treasury_view` عن قصد**: `treasury_receipts_create` و
        //    `treasury_payments_create` **غيرُ ممنوحَين لأيّ دور** في
        //    `RoleGrantMatrix.defaultGrants`، فربطُ الشاشتَين بهما كان
        //    يسحبهما من الجميع. والحواران يُبلَغان اليومَ بـ`treasury_view`.
        expect(
          screenPermissionMap[id],
          'treasury_view',
          reason: 'صلاحيّةٌ غيرُ ممنوحةٍ لأحدٍ تُخفي الشاشةَ عن الجميع',
        );
        expect(ScreenRegistry.unified, contains(id));
        expect(
          _code(
            'lib/app_main_screen.dart',
          ).contains('appScreen: AppScreen.${e.screen.name},'),
          isTrue,
        );
        final item = kAllNavItemDefs.where((n) => n.index == e.index).toList();
        expect(
          item,
          hasLength(1),
          reason: 'بلا مدخلٍ هنا لا يراها المستخدمُ مهما صحّ الباقي',
        );
        expect(item.single.label, e.label);
        expect(item.single.group, 'accounting');
        expect(item.single.permission, screenPermissionMap[id]);
      });
    });
  });
}
