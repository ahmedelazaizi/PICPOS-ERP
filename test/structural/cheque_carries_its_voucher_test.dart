// حارسُ العقد: **الورقةُ تحمل سندَها، والسندُ لا يُعَدّ حركةً**.
//
// ═══ ما يقيسه هذا الملفُّ وما لا يقيسه ═══
//
// الأثرُ نفسُه مقيسٌ على صفوفٍ حقيقيّةٍ في
// `test/unit/cheque_receipt_leaves_a_voucher_test.dart`. وهذا الحارسُ يثبّت
// **مواضعَ التوصيل** التي لا تبلغها قاعدةُ بياناتٍ في اختبارِ وحدة: حوارا
// القبض والصرف ودجتان، وشجرتُهما تحتاج تجهيزةً كاملة.
//
// ⚠️ **وفحصُ النصّ لا يفرّق بين شيفرةٍ تعمل وأخرى معطَّلةٍ بشرطٍ كاذب**
// (قِيس سابقاً: `if (false)` يمرّ من حارسٍ نصّيٍّ ومن `flutter analyze` معاً).
// فالمقيسُ هنا **وجودُ السلسلة** لا صحّةُ عملها: أن يُلتقَط معرّفُ السند من
// نداء الإنشاء، وأن يصل نداءَ الورقة. وهذا يُسقط الانحدارَ الواقعيّ —
// إسقاطُ المعامل في إعادة صياغة — لا كلَّ انحدارٍ متخيَّل.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _receiptDialog =
    'lib/presentation/treasury_picpos/widgets/receipt_voucher_dialog_picpos.dart';
const _paymentDialog =
    'lib/presentation/treasury_picpos/widgets/payment_voucher_dialog_picpos.dart';
const _papersDao = 'lib/data/database/daos/commercial_papers_dao.dart';
const _treasuryDao = 'lib/data/database/daos/treasury_dao.dart';
const _partyDao = 'lib/data/database/daos/party_dao.dart';
const _treasuryRepo = 'lib/data/repositories/treasury_repository_impl.dart';

void main() {
  test('🔴 السلسلةُ كاملةٌ في حواري القبض والصرف', () {
    // 🔴 والحلقةُ الأضعفُ هي **الالتقاط**: `createReceiptVoucher` كانت
    //    تُنادى بلا التقاط عائدها إطلاقاً، فالمعرّفُ لا يوجد ليُمرَّر.
    for (final (path, call) in [
      (_receiptDialog, 'treasuryRepo.createReceiptVoucher('),
      (_paymentDialog, 'treasuryRepo.createPaymentVoucher('),
    ]) {
      final code = _code(path);
      expect(code.contains('voucherRowId = await $call'), isTrue,
          reason: '$path لا يلتقط معرّفَ السند — فلا شيءَ يُمرَّر للورقة');
      expect(
        code.contains(
            'sourceVoucherId: voucherRowId > 0 ? voucherRowId : null,'),
        isTrue,
        reason: '$path لا يمرّر السندَ إلى الورقة — فالعمودُ يبقى بلا كاتب',
      );
    }
  });

  test('والـDAO يكتب العمودَ فعلاً', () {
    final code = _code(_papersDao);
    expect(code.contains('sourceVoucherId: Value(sourceVoucherId),'), isTrue,
        reason: 'المعاملُ يُستقبَل ولا يُكتَب — وهو عينُ ما كان: عمودٌ '
            'مشحونٌ بلا كاتب');
  });

  test('🔴 والاستثناءُ في كشف الحساب **موضعان** لا موضع', () {
    // 🔴 قارئان لا يرشّحان بالنوع: `getPartyLedger` و`getPartyTransactions`.
    //    واستثناءٌ في أحدهما وحدَه يترك الآخرَ يعرض سطرَ دفعةٍ ثانيةً —
    //    والعدُّ هو ما يمسك ذلك، لا `contains`.
    final code = _code(_partyDao);
    expect(
      'kChequeVoucherTxnType'.allMatches(code).length,
      2,
      reason: 'عددُ الاستثناءات ليس اثنين — قارئٌ يعدّ السندَ حركةً',
    );
  });

  test('والنوعُ ثابتٌ واحدٌ يُقرأ لا يُكتَب سلسلةً', () {
    // كتابةُ `'cheque_voucher'` بيدها في موضعَين تجعل استثناءً يفلت بصمت.
    final treasury = _code(_treasuryDao);
    expect(treasury.contains("const String kChequeVoucherTxnType ="), isTrue,
        reason: 'الثابتُ اختفى');
    expect(treasury.contains('transactionType: kChequeVoucherTxnType,'), isTrue,
        reason: 'الصفُّ يُكتَب بنوعٍ مكتوبٍ بيده');
    expect("'cheque_voucher'".allMatches(_code(_partyDao)).length, 0,
        reason: 'كشفُ الحساب يقارن بسلسلةٍ مكتوبةٍ بيدها لا بالثابت');
  });

  test('🔴 والصفُّ المستنديُّ يُطلَب للشيك وحدَه', () {
    // 🔴 فرضُه دائماً يقلب حارسَ مواصفة ١٣٣ أحمرَ («لا صفَّ للشيك») ويكتب
    //    صفّاً ثانياً لكلّ سندٍ نقديّ.
    final repo = _code(_treasuryRepo);
    expect(
      'chequeVoucherSafeId: isCheckPayment ?'.allMatches(repo).length,
      2,
      reason: 'أحدُ السندَين لا يشترط الشيك — فيُكتَب صفٌّ مستنديٌّ للنقد',
    );
  });

  test('ومرساةٌ — الرصيدُ لقطةٌ لا وعدٌ', () {
    // `balance + amount` تَعِد برصيدٍ لم يقع، ويقرؤها كشفُ الخزنة سطراً.
    final code = _code(_treasuryDao);
    final at = code.indexOf('Future<int> _writeChequeVoucherRow(');
    expect(at, greaterThan(0), reason: 'كاتبُ الصفّ المستنديّ اختفى');
    final body = code.substring(at, code.indexOf('Future<int> createReceiptVoucher(', at));
    expect(body.contains('balanceAfter: safe.balance,'), isTrue,
        reason: 'الصفُّ يَعِد برصيدٍ لم يقع');
    expect(body.contains('adjustSafeBalance'), isFalse,
        reason: 'السندُ المستنديُّ يحرّك رصيدَ الخزنة');
    expect(body.contains('adjustPartyBalance'), isFalse,
        reason: 'السندُ المستنديُّ ينقص ذمّةَ الطرف — ازدواجُ مواصفة ١٣٣');
  });
}
