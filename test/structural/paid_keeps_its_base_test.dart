// حارسُ العقد: **`paid` يُكتَب في موضعَين، وقاعدتُه تُكتَب معه.**
//
// ═══ الثابت ═══
//
//     sales_invoices.paid = paid_unallocated + Σ payment_allocations
//
// ═══ 🔴 ولماذا يُحرَس بالعدّ لا بالنيّة ═══
//
// `PaymentAllocationSyncStrategy` تُعيد حسابَ `paid` من هذه المعادلة. فكلُّ
// كاتبٍ يرفع `paid` **بلا تخصيصٍ** ولا يرفع القاعدةَ معه يُمحى أثرُه عند
// أوّلِ إعادةِ حساب — بلا رسالةٍ ولا سجلّ: الصفُّ صحيحٌ والمجموعُ صحيحٌ
// والمعادلةُ هي الخطأ.
//
// وكاتبٌ خامسٌ يُضاف غداً في `sales_mutations_dao.dart` لن يعرف بالثابت،
// فالعدُّ هو ما يوقفه.
//
// ═══ ⚠️ وطفرتان نجتا أثناء بناء هذا الحارس — وكلتاهما معلومة ═══
//
// ‏١) استبدالُ الكتابةِ المباشرة في `_advanceInvoicePaid` بـ
//    `updateSalesInvoicePaidAmount` **نجا**: الصيغتان متكافئتان ما دام صفُّ
//    التخصيص يُدرَج **قبل** الرفع. والكتابةُ المباشرةُ تبقى لأنّها لا تعتمد
//    على ترتيب، والشرحُ فوقها يقول ذلك بدل أن يدّعي غيرَه.
//
// ‏٢) كفُّ `_writeSalesInvoicePaid` عن كتابة القاعدة **نجا** من أوّل صياغةٍ
//    للفحوص — لأنّها كانت تقيس تخصيصاً وحدَه. والثابتُ يُكسَر في الاتّجاه
//    الآخر: تحصيلٌ **بعد** تخصيصٍ قائم. فأُضيف المشهد.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
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

const _sales = 'lib/data/database/daos/sales_mutations_dao.dart';
const _alloc = 'lib/data/database/daos/payment_allocations_dao.dart';
const _strategy =
    'lib/services/sync/strategies/payment_allocation_sync_strategy.dart';
const _table = 'lib/data/database/tables/sales_purchase_tables.dart';

void main() {
  test('🔴 العمودُ قائمٌ وله شرحُه', () {
    final t = _code(_table);
    expect(t.contains('RealColumn get paidUnallocated'), isTrue,
        reason: 'قاعدةُ حساب المسدَّد اختفت — والثابتُ كلُّه معلَّقٌ عليها');
  });

  test('🔴 و`paid` يُكتَب في موضعَين لا أكثر', () {
    final code = _code(_sales);
    expect(_count(code, 'paid: Value('), 2,
        reason: '🔴 كاتبٌ ثالثٌ لـ`paid` في هذا الملفّ لا يعرف القاعدةَ — '
            'وأوّلُ إعادةِ حسابٍ تمحو ما كتبه. والموضعان: الإدراجُ '
            '(القاعدةُ = المسدَّدُ كلُّه) و`_writeSalesInvoicePaid` (القاعدةُ '
            '= المسدَّدُ ناقصَ مجموعِ التخصيصات).');
    expect(_count(code, 'paidUnallocated: Value('), 2,
        reason: 'موضعُ كتابةٍ لـ`paid` بلا قاعدته');
  });

  test('🔴 والضابطُ يحسب القاعدةَ من مجموع التخصيصات', () {
    final code = _code(_sales);
    final at = code.indexOf('Future<void> _writeSalesInvoicePaid(');
    expect(at, greaterThan(0), reason: 'الموضعُ الجامعُ للثابت اختفى');
    // ⚠️ **الجسمُ يبدأ بعد `async {` لا عند التوقيع**: التوقيعُ نفسُه ينتهي
    //    بـ`\n  }) async {` فيطابقه `indexOf('\n  }')` ويقصّ الجسمَ كلَّه —
    //    فيمرّ الفحصُ أحمرَ على شيفرةٍ سليمة. وقع فعلاً عند كتابة الحارس.
    final open = code.indexOf('async {', at);
    final body = code.substring(open, code.indexOf('\n  }', open));
    expect(body.contains('getPaymentAllocationsTotal(invoiceId)'), isTrue,
        reason: '🔴 قاعدةٌ لا تُطرَح منها التخصيصاتُ تُضاعفها: يصير '
            '`paid = paid + Σ` عند أوّل إعادةِ حساب');
    expect(body.contains('base < 0 ? 0 : base'), isTrue,
        reason: 'قاعدةٌ سالبةٌ تُنتج مسدَّداً أقلَّ من مجموع تخصيصاتٍ قائمة');
  });

  test('🔴 والتخصيصُ يرفع المسدَّدَ ولا يمسّ القاعدة', () {
    final code = _code(_alloc);
    expect(code.contains('paidUnallocated'), isFalse,
        reason: '🔴 التخصيصُ الذي يكتب القاعدةَ يُلغي أثرَ نفسِه: إعادةُ '
            'الحساب تُرجع المسدَّدَ إلى ما كان');
    expect(_count(code, 'paid: Value(newPaid)'), 2,
        reason: 'الرفعُ للمبيعات والمشتريات معاً — وكتابةُ المبلغ بدل '
            'الجمع تمحو ما سبقه');
  });

  test('🔴 والتوزيعُ لا يحرّك مالاً', () {
    final code = _code(_alloc);
    for (final money in const [
      'createReceiptVoucher(',
      'createPaymentVoucher(',
      'createJournalEntry(',
      'updateSafeBalance(',
      'updatePartyBalance(',
    ]) {
      expect(code.contains(money), isFalse,
          reason: '🔴 السندُ حرّك المالَ سلفاً — و$money هنا يضاعف النقديّةَ '
              'ويقيّد العميلَ مرّتين، والقيدان متّزنان فلا فحصَ اتّزانٍ '
              'يمسكهما');
    }
  });

  test('🔴 وفاتورةُ المزامنة تحمل قاعدتَها في المسارَين', () {
    const salesSync = 'lib/services/sync/strategies/sales_sync_strategy.dart';
    final code = _code(salesSync);
    // 🔴 **البابُ الآخر لنفس العطب**: إدراجٌ أو تحديثٌ يكتب `paid` بلا
    //    قاعدته يهبط بها إلى صفر، فيُصفَّر المسدَّدُ عند أوّل تخصيص.
    expect(_count(code, 'paidUnallocated: Value(await serverPaidUnallocated())'),
        2,
        reason: '🔴 مسارٌ من مسارَي الكتابة بلا قاعدة — والمسارُ الآخرُ '
            'سليمٌ فيبدو كلُّ شيءٍ موصولاً');
    final at = code.indexOf('Future<double> serverPaidUnallocated()');
    expect(at, greaterThan(0));
    final open = code.indexOf('async {', at);
    final body = code.substring(open, code.indexOf('\n    }', open));
    expect(body.contains('getPaymentAllocationsTotal(serverId)'), isTrue,
        reason: '🔴 خادمٌ أقدمُ لا يرسل المفتاح: السقوطُ على `paid` وحدَه '
            'يضاعف التخصيصاتِ الواصلةَ قبل صفِّ الفاتورة');
  });

  test('🔴 وإعادةُ الحساب جمعٌ لا استبدال', () {
    final code = _code(_strategy);
    expect(code.contains('invoice.paidUnallocated +'), isTrue,
        reason: '🔴 `paid = Σ allocations` تمحو ما دُفع عند البيع: فاتورةٌ '
            'دُفع منها ٣٠٠ نقداً وخُصِّص لها ٧٠٠ تعود ٧٠٠ — تختفي '
            'الثلاثُمئة ويتضخّم رصيدُ العملاء');
    expect(code.contains('getSalesInvoiceById(invoiceId)'), isTrue,
        reason: 'القاعدةُ لا تُقرأ أصلاً');
  });
}
